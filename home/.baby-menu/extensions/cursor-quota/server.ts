import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuServerContext } from "@babymenu/contracts";

const DASHBOARD_USAGE_URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage";
const PLAN_INFO_URL = "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo";
const SNAPSHOT_TABLE = "cursor_quota_snapshot";
const SQLITE_CANDIDATES = ["sqlite3", "/usr/bin/sqlite3", "/opt/homebrew/bin/sqlite3", "/usr/local/bin/sqlite3"] as const;
const SQLITE_BUSY_TIMEOUT_MS = 1_000;
const SQLITE_HARD_TIMEOUT_MS = 4_000;
const REQUEST_TIMEOUT_MS = 15_000;
const MAX_PROCESS_OUTPUT_BYTES = 64 * 1024;
const MAX_API_RESPONSE_BODY_BYTES = 64 * 1024;
const MAX_SAFE_STRING_LENGTH = 512;
const CURSOR_AUTH_KEYS = [
  "cursorAuth/accessToken",
  "cursorAuth/cachedEmail",
  "cursorAuth/stripeMembershipType",
] as const;
const WINDOW_LABELS: Record<CursorQuotaWindow["id"], string> = {
  included_usage: "included usage",
  auto_usage: "auto usage",
  api_usage: "API usage",
};
const WINDOW_ORDER = Object.keys(WINDOW_LABELS) as CursorQuotaWindow["id"][];

type CursorAuthKey = (typeof CURSOR_AUTH_KEYS)[number];

type CursorQuotaWindow = {
  id: "included_usage" | "auto_usage" | "api_usage";
  label: string;
  kind?: "monthly";
  percentUsed: number;
  percentRemaining?: number;
  resetAt?: string;
};

type CursorQuotaSnapshot = {
  source: "api";
  accountEmail?: string;
  plan?: string;
  windows: CursorQuotaWindow[];
  refreshedAt: string;
  stale: boolean;
  status?: string;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

type CursorAuth = {
  accessToken: string;
  accountEmail?: string;
  membershipType?: string;
};

type ProcessResult =
  | { ok: true; stdout: string }
  | { ok: false; kind: "not_found" | "busy" | "timeout" | "failed" | "too_large" };

type ApiResult =
  | { ok: true; status: number; body: unknown }
  | { ok: false; kind: "network" | "timeout" | "too_large" };

function cursorStateDbPath(): string {
  return join(homedir(), "Library", "Application Support", "Cursor", "User", "globalStorage", "state.vscdb");
}

function runProcess(command: string, args: string[], timeoutMs: number): Promise<ProcessResult> {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"], windowsHide: true });
    } catch {
      resolve({ ok: false, kind: "not_found" });
      return;
    }

    let settled = false;
    let stdout = "";
    let stderr = "";
    let outputBytes = 0;

    const finish = (result: ProcessResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };

    child.stdout?.on("data", (chunk: Buffer) => {
      outputBytes += chunk.length;
      if (outputBytes > MAX_PROCESS_OUTPUT_BYTES) {
        child.kill("SIGKILL");
        finish({ ok: false, kind: "too_large" });
        return;
      }
      stdout += chunk.toString("utf8");
    });
    child.stderr?.on("data", (chunk: Buffer) => {
      outputBytes += chunk.length;
      if (outputBytes > MAX_PROCESS_OUTPUT_BYTES) {
        child.kill("SIGKILL");
        finish({ ok: false, kind: "too_large" });
        return;
      }
      stderr += chunk.toString("utf8");
    });
    child.once("error", (error: NodeJS.ErrnoException) => {
      finish({ ok: false, kind: error.code === "ENOENT" ? "not_found" : "failed" });
    });
    child.once("exit", (code) => {
      if (settled) return;
      if (code === 0) {
        finish({ ok: true, stdout });
        return;
      }
      finish({ ok: false, kind: /busy|locked/i.test(stderr) ? "busy" : "failed" });
    });

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      finish({ ok: false, kind: "timeout" });
    }, timeoutMs);
  });
}

async function discoverSqlite(): Promise<string | null> {
  for (const candidate of SQLITE_CANDIDATES) {
    const probe = await runProcess(candidate, ["-version"], 2_000);
    if (probe.ok) return candidate;
  }
  return null;
}

function parseAuthRows(stdout: string): Partial<Record<CursorAuthKey, string>> {
  const rows: Partial<Record<CursorAuthKey, string>> = {};
  for (const line of stdout.split(/\r?\n/)) {
    if (!line) continue;
    const separatorIndex = line.indexOf("\t");
    if (separatorIndex === -1) continue;
    const key = line.slice(0, separatorIndex) as CursorAuthKey;
    if (!CURSOR_AUTH_KEYS.includes(key)) continue;
    rows[key] = line.slice(separatorIndex + 1);
  }
  return rows;
}

type AuthReadResult =
  | { ok: true; auth: CursorAuth }
  | { ok: false; kind: "signin_required" | "sqlite_missing" | "busy" | "unavailable" };

async function readCursorAuth(): Promise<AuthReadResult> {
  const dbPath = cursorStateDbPath();
  if (!existsSync(dbPath)) return { ok: false, kind: "signin_required" };

  const sqlite = await discoverSqlite();
  if (!sqlite) return { ok: false, kind: "sqlite_missing" };

  const quotedKeys = CURSOR_AUTH_KEYS.map((key) => `'${key}'`).join(", ");
  const query = `SELECT key, value FROM ItemTable WHERE key IN (${quotedKeys});`;
  const result = await runProcess(
    sqlite,
    ["-readonly", "-cmd", `.timeout ${SQLITE_BUSY_TIMEOUT_MS}`, "-cmd", ".mode tabs", dbPath, query],
    SQLITE_HARD_TIMEOUT_MS,
  );

  if (!result.ok) {
    if (result.kind === "busy" || result.kind === "timeout") return { ok: false, kind: "busy" };
    return { ok: false, kind: "unavailable" };
  }

  const rows = parseAuthRows(result.stdout);
  const accessToken = rows["cursorAuth/accessToken"];
  if (!accessToken) return { ok: false, kind: "signin_required" };

  return {
    ok: true,
    auth: {
      accessToken,
      accountEmail: rows["cursorAuth/cachedEmail"] || undefined,
      membershipType: rows["cursorAuth/stripeMembershipType"] || undefined,
    },
  };
}

async function postCursorApi(url: string, accessToken: string): Promise<ApiResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
        "connect-protocol-version": "1",
      },
      body: "{}",
      signal: controller.signal,
    });

    const textResult = await readResponseText(response, controller);
    if (!textResult.ok) return { ok: false, kind: "too_large" };

    const text = textResult.text;
    let body: unknown = null;
    if (text.trim().length > 0) {
      try {
        body = JSON.parse(text);
      } catch {
        body = null;
      }
    }

    return { ok: true, status: response.status, body };
  } catch (error) {
    return { ok: false, kind: error instanceof Error && error.name === "AbortError" ? "timeout" : "network" };
  } finally {
    clearTimeout(timer);
  }
}

async function readResponseText(
  response: Response,
  controller: AbortController,
): Promise<{ ok: true; text: string } | { ok: false; kind: "too_large" }> {
  if (!response.body) return { ok: true, text: "" };

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let text = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      bytes += value.byteLength;
      if (bytes > MAX_API_RESPONSE_BODY_BYTES) {
        controller.abort();
        try {
          await reader.cancel();
        } catch {
          // Best effort only. The important part is that the body is not parsed.
        }
        return { ok: false, kind: "too_large" };
      }

      text += decoder.decode(value, { stream: true });
    }
  } finally {
    reader.releaseLock();
  }

  text += decoder.decode();
  return { ok: true, text };
}

function finitePercent(value: unknown): number | undefined {
  const numeric = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : Number.NaN;
  if (!Number.isFinite(numeric)) return undefined;
  return Math.max(0, Math.min(100, numeric));
}

function resetIso(value: unknown): string | undefined {
  const epochMs = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : Number.NaN;
  if (!Number.isFinite(epochMs)) return undefined;
  const date = new Date(epochMs);
  if (Number.isNaN(date.getTime())) return undefined;
  return date.toISOString();
}

function membershipPlanName(value?: string): string | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  if (!trimmed) return undefined;
  return trimmed
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function planNameFrom(body: unknown): string | undefined {
  if (!body || typeof body !== "object") return undefined;
  const planInfo = (body as Record<string, unknown>).planInfo;
  if (!planInfo || typeof planInfo !== "object") return undefined;
  const planName = (planInfo as Record<string, unknown>).planName;
  return typeof planName === "string" && planName.trim() ? planName : undefined;
}

function normalizeUsage(body: unknown, auth: CursorAuth, plan?: string): CursorQuotaSnapshot | null {
  if (!body || typeof body !== "object") return null;
  const raw = body as Record<string, unknown>;
  const planUsage = raw.planUsage;
  if (!planUsage || typeof planUsage !== "object") return null;

  const usage = planUsage as Record<string, unknown>;
  const resetAt = resetIso(raw.billingCycleEnd);
  const windows: CursorQuotaWindow[] = [];
  const mappings: Array<[CursorQuotaWindow["id"], string, unknown]> = [
    ["included_usage", WINDOW_LABELS.included_usage, usage.totalPercentUsed],
    ["auto_usage", WINDOW_LABELS.auto_usage, usage.autoPercentUsed],
    ["api_usage", WINDOW_LABELS.api_usage, usage.apiPercentUsed],
  ];

  for (const [id, label, value] of mappings) {
    const percentUsed = finitePercent(value);
    if (percentUsed === undefined) continue;
    windows.push({
      id,
      label,
      kind: "monthly",
      percentUsed,
      percentRemaining: Math.max(0, 100 - percentUsed),
      resetAt,
    });
  }

  if (windows.length === 0) return null;

  const status = raw.displayMessage;
  return {
    source: "api",
    accountEmail: auth.accountEmail,
    plan: plan ?? membershipPlanName(auth.membershipType),
    windows,
    refreshedAt: new Date().toISOString(),
    stale: false,
    status: typeof status === "string" && status.trim() ? status : undefined,
  };
}

function safeString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > MAX_SAFE_STRING_LENGTH || /[\u0000-\u001f\u007f]/.test(trimmed)) return undefined;
  return trimmed;
}

function safeIsoDate(value: unknown): string | undefined {
  const text = safeString(value);
  if (!text) return undefined;
  const date = new Date(text);
  if (Number.isNaN(date.getTime())) return undefined;
  return date.toISOString();
}

function sanitizeCachedSnapshot(value: unknown): CursorQuotaSnapshot | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  if (raw.source !== "api" || !Array.isArray(raw.windows)) return null;

  const refreshedAt = safeIsoDate(raw.refreshedAt);
  if (!refreshedAt || typeof raw.stale !== "boolean") return null;

  const seen = new Set<CursorQuotaWindow["id"]>();
  const windows: CursorQuotaWindow[] = [];

  for (const windowValue of raw.windows) {
    if (!windowValue || typeof windowValue !== "object") return null;
    const rawWindow = windowValue as Record<string, unknown>;
    const id = rawWindow.id;
    if (typeof id !== "string" || !Object.prototype.hasOwnProperty.call(WINDOW_LABELS, id)) return null;

    const windowId = id as CursorQuotaWindow["id"];
    if (seen.has(windowId)) return null;
    seen.add(windowId);

    const percentUsed = finitePercent(rawWindow.percentUsed);
    if (percentUsed === undefined) return null;

    const resetAt = safeIsoDate(rawWindow.resetAt);
    windows.push({
      id: windowId,
      label: WINDOW_LABELS[windowId],
      kind: "monthly",
      percentUsed,
      percentRemaining: Math.max(0, 100 - percentUsed),
      resetAt,
    });
  }

  if (windows.length === 0) return null;
  windows.sort((a, b) => WINDOW_ORDER.indexOf(a.id) - WINDOW_ORDER.indexOf(b.id));

  return {
    source: "api",
    accountEmail: safeString(raw.accountEmail),
    plan: safeString(raw.plan),
    windows,
    refreshedAt,
    stale: false,
    status: safeString(raw.status),
  };
}

function ensureSnapshotTable(context: BabyMenuServerContext) {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
}

function getLastGoodSnapshot(context: BabyMenuServerContext): CursorQuotaSnapshot | null {
  ensureSnapshotTable(context);
  const row = context.db.get<{ json: string }>(`SELECT json FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row || typeof row.json !== "string" || row.json.length > MAX_PROCESS_OUTPUT_BYTES) return null;
  try {
    return sanitizeCachedSnapshot(JSON.parse(row.json));
  } catch {
    return null;
  }
}

function saveSnapshot(context: BabyMenuServerContext, snapshot: CursorQuotaSnapshot) {
  ensureSnapshotTable(context);
  context.db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json`,
    [JSON.stringify(snapshot)],
  );
}

function staleFallback(context: BabyMenuServerContext, sourceTried: string[]): QuotaResult<CursorQuotaSnapshot> {
  sourceTried.push("cache");
  const lastGood = getLastGoodSnapshot(context);
  if (lastGood) return { ok: true, data: { ...lastGood, stale: true } };
  return { ok: false, error: "Cursor quota unavailable", sourceTried };
}

export const actions = {
  getQuota: async (_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult<CursorQuotaSnapshot>> => {
    const sourceTried: string[] = ["local-db"];
    const authResult = await readCursorAuth();

    if (!authResult.ok) {
      if (authResult.kind === "signin_required") return { ok: false, error: "Cursor sign-in required", sourceTried };
      if (authResult.kind === "busy") return staleFallback(context, sourceTried);
      return { ok: false, error: "Cursor quota unavailable", sourceTried };
    }

    sourceTried.push("dashboard-api");
    const usageResponse = await postCursorApi(DASHBOARD_USAGE_URL, authResult.auth.accessToken);
    if (!usageResponse.ok) return staleFallback(context, sourceTried);
    if (usageResponse.status === 401 || usageResponse.status === 403) {
      return { ok: false, error: "Cursor sign-in required", sourceTried };
    }
    if (usageResponse.status < 200 || usageResponse.status >= 300) return staleFallback(context, sourceTried);

    let plan = membershipPlanName(authResult.auth.membershipType);
    sourceTried.push("plan-info");
    const planResponse = await postCursorApi(PLAN_INFO_URL, authResult.auth.accessToken);
    if (planResponse.ok && planResponse.status >= 200 && planResponse.status < 300) {
      plan = planNameFrom(planResponse.body) ?? plan;
    }

    const snapshot = normalizeUsage(usageResponse.body, authResult.auth, plan);
    if (!snapshot) return staleFallback(context, sourceTried);

    saveSnapshot(context, snapshot);
    return { ok: true, data: snapshot };
  },
};
