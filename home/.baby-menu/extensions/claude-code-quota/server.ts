import { execFile, execFileSync, spawn } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { homedir, platform } from "node:os";
import { join } from "node:path";
import type { BabyMenuServerContext } from "@babymenu/contracts";

const SNAPSHOT_TABLE = "claude_code_quota_snapshot";

type Credential = {
  source: "keychain" | "file";
  accessToken: string;
  expiresAt?: number;
  subscriptionType?: string;
};

type QuotaWindow = {
  id: "five_hour" | "seven_day" | "seven_day_sonnet" | "seven_day_opus" | "extra_usage";
  label: string;
  percentUsed?: number;
  resetText?: string;
  resetAt?: string;
  spentUsd?: number;
  limitUsd?: number;
};

type ClaudeQuotaSnapshot = {
  source: "oauth" | "cli";
  accountEmail?: string;
  plan?: string;
  windows: QuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

function clampPercent(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.max(0, Math.min(100, value));
}

function parseCredentialBlob(raw: string, source: "keychain" | "file"): Credential | null {
  let json: Record<string, unknown>;
  try {
    json = JSON.parse(raw);
  } catch {
    return null;
  }
  const oauth = (json.claudeAiOauth as Record<string, unknown> | undefined) ?? json;
  const accessToken = (oauth.accessToken ?? oauth.access_token) as string | undefined;
  if (!accessToken || typeof accessToken !== "string") return null;
  const expiresAt = typeof oauth.expiresAt === "number" ? oauth.expiresAt : undefined;
  const subscriptionType = typeof oauth.subscriptionType === "string" ? oauth.subscriptionType : undefined;
  return { source, accessToken, expiresAt, subscriptionType };
}

function readKeychainCredential(): Credential | null {
  if (platform() !== "darwin") return null;
  try {
    const raw = execFileSync("security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], {
      encoding: "utf8",
      timeout: 5000,
    });
    return parseCredentialBlob(raw.trim(), "keychain");
  } catch {
    return null;
  }
}

function readFileCredential(): Credential | null {
  const path = join(homedir(), ".claude", ".credentials.json");
  if (!existsSync(path)) return null;
  try {
    const raw = readFileSync(path, "utf8");
    return parseCredentialBlob(raw, "file");
  } catch {
    return null;
  }
}

function isExpired(credential: Credential): boolean {
  return typeof credential.expiresAt === "number" && credential.expiresAt <= Date.now();
}

function resolveCredentialCandidates(): Credential[] {
  const keychain = readKeychainCredential();
  const file = readFileCredential();
  const usable = [keychain, file].filter((c): c is Credential => c !== null && !isExpired(c));

  if (platform() === "darwin" && keychain && !isExpired(keychain)) {
    const rest = usable.filter((c) => c !== keychain).sort((a, b) => (b.expiresAt ?? 0) - (a.expiresAt ?? 0));
    return [keychain, ...rest];
  }
  return usable.sort((a, b) => (b.expiresAt ?? 0) - (a.expiresAt ?? 0));
}

async function callUsageApi(credential: Credential): Promise<{ status: number; body: unknown } | null> {
  try {
    const res = await fetch("https://api.anthropic.com/api/oauth/usage", {
      headers: {
        Authorization: `Bearer ${credential.accessToken}`,
        "anthropic-beta": "oauth-2025-04-20",
      },
    });
    const text = await res.text();
    let body: unknown = null;
    try {
      body = JSON.parse(text);
    } catch {
      body = null;
    }
    return { status: res.status, body };
  } catch {
    return null;
  }
}

function normalizeOauthResponse(body: Record<string, unknown>, subscriptionType?: string): ClaudeQuotaSnapshot {
  const windows: QuotaWindow[] = [];

  const addWindow = (id: QuotaWindow["id"], label: string, entry: unknown) => {
    if (!entry || typeof entry !== "object") return;
    const e = entry as Record<string, unknown>;
    const percentUsed = clampPercent(e.utilization);
    if (percentUsed === undefined) return;
    windows.push({
      id,
      label,
      percentUsed,
      resetAt: typeof e.resets_at === "string" ? e.resets_at : undefined,
    });
  };

  addWindow("five_hour", "session", body.five_hour);
  addWindow("seven_day", "weekly", body.seven_day);
  addWindow("seven_day_sonnet", "sonnet weekly", body.seven_day_sonnet);
  addWindow("seven_day_opus", "opus weekly", body.seven_day_opus);

  const extra = body.extra_usage as Record<string, unknown> | undefined;
  if (extra && extra.is_enabled === true) {
    windows.push({
      id: "extra_usage",
      label: "extra usage",
      spentUsd: typeof extra.used_credits === "number" ? extra.used_credits / 100 : undefined,
      limitUsd: typeof extra.monthly_limit === "number" ? extra.monthly_limit / 100 : undefined,
    });
  }

  return {
    source: "oauth",
    plan: subscriptionType,
    windows,
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

const ANSI_PATTERN = /\x1b\][^\x07]*\x07|\x1b\[[0-9;?]*[a-zA-Z]/g;

function stripAnsi(input: string): string {
  return input.replace(ANSI_PATTERN, "").replace(/\r/g, "");
}

function extractPercentNear(text: string, heading: string): number | undefined {
  const idx = text.search(new RegExp(heading, "i"));
  if (idx === -1) return undefined;
  const window = text.slice(idx, idx + 200);
  const match = window.match(/(\d{1,3})\s*%/);
  if (!match) return undefined;
  return clampPercent(Number(match[1]));
}

function extractResetNear(text: string, heading: string): string | undefined {
  const idx = text.search(new RegExp(heading, "i"));
  if (idx === -1) return undefined;
  const window = text.slice(idx, idx + 200);
  const match = window.match(/resets?\s+(?:in|at)\s+[^\n]{1,40}/i);
  return match ? match[0].trim() : undefined;
}

function claudeOnPath(): Promise<boolean> {
  return new Promise((resolve) => {
    execFile("claude", ["--version"], { timeout: 5000 }, (error) => resolve(!error));
  });
}

async function runCliUsageProbe(): Promise<ClaudeQuotaSnapshot | null> {
  if (platform() !== "darwin") return null;
  if (!(await claudeOnPath())) return null;

  return new Promise((resolve) => {
    const child = spawn("script", ["-q", "/dev/null", "claude", "--allowed-tools", ""], {
      cwd: homedir(),
      stdio: ["pipe", "pipe", "pipe"],
      detached: true,
    });

    let buffer = "";
    let trustSent = false;
    let usageSent = false;
    let settled = false;

    const finish = (result: ClaudeQuotaSnapshot | null) => {
      if (settled) return;
      settled = true;
      clearInterval(poll);
      clearTimeout(hardTimeout);
      try {
        if (child.pid) process.kill(-child.pid, "SIGKILL");
      } catch {
        // process already gone
      }
      resolve(result);
    };

    child.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
    });
    child.on("error", () => finish(null));

    const poll = setInterval(() => {
      const plain = stripAnsi(buffer);
      if (!trustSent && /trust this folder/i.test(plain)) {
        trustSent = true;
        child.stdin.write("1\r");
        return;
      }
      if (trustSent && !usageSent && /Try "/i.test(plain)) {
        usageSent = true;
        setTimeout(() => {
          for (const ch of "/usage") child.stdin.write(ch);
          setTimeout(() => child.stdin.write("\r"), 300);
        }, 1000);
        return;
      }
      if (usageSent && /Current session/i.test(plain)) {
        const percentSession = extractPercentNear(plain, "Current session");
        const percentWeek = extractPercentNear(plain, "Current week");
        if (percentSession === undefined && percentWeek === undefined) return;
        const windows: QuotaWindow[] = [];
        if (percentSession !== undefined) {
          windows.push({
            id: "five_hour",
            label: "session",
            percentUsed: percentSession,
            resetText: extractResetNear(plain, "Current session"),
          });
        }
        if (percentWeek !== undefined) {
          windows.push({
            id: "seven_day",
            label: "weekly",
            percentUsed: percentWeek,
            resetText: extractResetNear(plain, "Current week"),
          });
        }
        finish({ source: "cli", windows, refreshedAt: new Date().toISOString(), stale: false });
      }
    }, 250);

    const hardTimeout = setTimeout(() => finish(null), 15000);
  });
}

async function getLastGoodSnapshot(context: BabyMenuServerContext): Promise<ClaudeQuotaSnapshot | null> {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
  const row = context.db.get<{ json: string }>(`SELECT json FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return null;
  try {
    return JSON.parse(row.json) as ClaudeQuotaSnapshot;
  } catch {
    return null;
  }
}

function saveSnapshot(context: BabyMenuServerContext, snapshot: ClaudeQuotaSnapshot) {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
  context.db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json`,
    [JSON.stringify(snapshot)],
  );
}

export const actions = {
  getQuota: async (_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult<ClaudeQuotaSnapshot>> => {
    const sourceTried: string[] = [];
    const candidates = resolveCredentialCandidates();

    let sawRejection = false;
    let sawTransportFailure = false;

    for (const credential of candidates) {
      sourceTried.push(credential.source);
      const response = await callUsageApi(credential);
      if (!response) {
        sawTransportFailure = true;
        continue;
      }
      if (response.status === 401 || response.status === 403) {
        sawRejection = true;
        continue;
      }
      if (response.status === 200 && response.body && typeof response.body === "object") {
        const snapshot = normalizeOauthResponse(response.body as Record<string, unknown>, credential.subscriptionType);
        saveSnapshot(context, snapshot);
        return { ok: true, data: snapshot };
      }
      sawTransportFailure = true;
    }

    sourceTried.push("cli");
    const cliSnapshot = await runCliUsageProbe();
    if (cliSnapshot) {
      saveSnapshot(context, cliSnapshot);
      return { ok: true, data: cliSnapshot };
    }

    if (sawTransportFailure && !sawRejection) {
      const lastGood = await getLastGoodSnapshot(context);
      if (lastGood) {
        return { ok: true, data: { ...lastGood, stale: true } };
      }
    }

    if (candidates.length === 0 || sawRejection) {
      return { ok: false, error: "Claude sign-in required", sourceTried };
    }
    return { ok: false, error: "Claude quota unavailable", sourceTried };
  },
};
