import { spawn } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuServerContext } from "@babymenu/contracts";

const SNAPSHOT_TABLE = "codex_quota_snapshot";
const FIVE_HOUR_SECONDS = 18_000;
const SEVEN_DAY_SECONDS = 604_800;
const WINDOW_TOLERANCE = 0.15;

type QuotaWindow = {
  id: "five_hour" | "weekly" | "spark_weekly" | "primary" | "secondary";
  label: string;
  percentUsed?: number;
  resetText?: string;
  resetAt?: string;
};

type CodexQuotaSnapshot = {
  source: "oauth" | "cli-rpc";
  accountEmail?: string;
  plan?: string;
  windows: QuotaWindow[];
  credits?: { balance?: number; hasCredits?: boolean; unlimited?: boolean };
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

function clampPercent(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.max(0, Math.min(100, value));
}

function closeTo(value: number, target: number): boolean {
  return Math.abs(value - target) / target <= WINDOW_TOLERANCE;
}

function classifyWindow(slot: "primary" | "secondary", durationSeconds: number | undefined): QuotaWindow["id"] {
  if (typeof durationSeconds === "number") {
    if (closeTo(durationSeconds, FIVE_HOUR_SECONDS)) return "five_hour";
    if (closeTo(durationSeconds, SEVEN_DAY_SECONDS)) return "weekly";
  }
  return slot;
}

function labelFor(id: QuotaWindow["id"]): string {
  switch (id) {
    case "five_hour":
      return "session";
    case "weekly":
      return "weekly";
    default:
      return id;
  }
}

function resolveAuthPath(): string {
  const codexHome = process.env.CODEX_HOME;
  if (codexHome) return join(codexHome, "auth.json");
  return join(homedir(), ".codex", "auth.json");
}

type AuthFile = {
  bearer: string;
  accountId?: string;
};

function readAuthFile(): AuthFile | null {
  const path = resolveAuthPath();
  if (!existsSync(path)) return null;
  let json: Record<string, unknown>;
  try {
    json = JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }

  const apiKey = json.OPENAI_API_KEY;
  if (typeof apiKey === "string" && apiKey.length > 0) {
    return { bearer: apiKey };
  }

  const tokens = json.tokens as Record<string, unknown> | undefined;
  if (!tokens) return null;
  const accessToken = (tokens.access_token ?? tokens.accessToken) as string | undefined;
  if (!accessToken || typeof accessToken !== "string") return null;
  const accountId = (tokens.account_id ?? tokens.accountId) as string | undefined;
  return { bearer: accessToken, accountId };
}

async function callUsageApi(auth: AuthFile): Promise<{ status: number; body: unknown } | null> {
  try {
    const headers: Record<string, string> = { Authorization: `Bearer ${auth.bearer}` };
    if (auth.accountId) headers["ChatGPT-Account-Id"] = auth.accountId;
    const res = await fetch("https://chatgpt.com/backend-api/wham/usage", { headers });
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

function windowFromEntry(slot: "primary" | "secondary", entry: unknown): QuotaWindow | null {
  if (!entry || typeof entry !== "object") return null;
  const e = entry as Record<string, unknown>;
  const percentUsed = clampPercent(e.used_percent ?? e.usedPercent);
  if (percentUsed === undefined) return null;
  const durationSeconds =
    typeof e.limit_window_seconds === "number"
      ? e.limit_window_seconds
      : typeof e.windowDurationMins === "number"
        ? e.windowDurationMins * 60
        : undefined;
  const id = classifyWindow(slot, durationSeconds);
  const resetEpoch = (e.reset_at ?? e.resetsAt) as number | undefined;
  const resetAt = typeof resetEpoch === "number" ? new Date(resetEpoch * 1000).toISOString() : undefined;
  return { id, label: labelFor(id), percentUsed, resetAt };
}

function normalizeOauthResponse(body: Record<string, unknown>): CodexQuotaSnapshot {
  const rateLimit = body.rate_limit as Record<string, unknown> | undefined;
  const windows: QuotaWindow[] = [];
  if (rateLimit) {
    const primary = windowFromEntry("primary", rateLimit.primary_window);
    const secondary = windowFromEntry("secondary", rateLimit.secondary_window);
    if (primary) windows.push(primary);
    if (secondary) windows.push(secondary);
  }

  const additionalRateLimits = body.additional_rate_limits;
  if (Array.isArray(additionalRateLimits)) {
    const spark = additionalRateLimits.find((entry) => {
      if (!entry || typeof entry !== "object") return false;
      return (entry as Record<string, unknown>).limit_name === "GPT-5.3-Codex-Spark";
    }) as Record<string, unknown> | undefined;
    const sparkRateLimit = spark?.rate_limit as Record<string, unknown> | undefined;
    const sparkWindow = windowFromEntry("primary", sparkRateLimit?.primary_window);
    if (sparkWindow) {
      windows.push({ ...sparkWindow, id: "spark_weekly", label: "spark weekly" });
    }
  }

  const creditsRaw = body.credits as Record<string, unknown> | undefined;
  let credits: CodexQuotaSnapshot["credits"];
  if (creditsRaw && (creditsRaw.has_credits === true || creditsRaw.unlimited === true)) {
    credits = {
      hasCredits: Boolean(creditsRaw.has_credits),
      unlimited: Boolean(creditsRaw.unlimited),
      balance: typeof creditsRaw.balance === "string" ? Number(creditsRaw.balance) : undefined,
    };
  }

  return {
    source: "oauth",
    accountEmail: typeof body.email === "string" ? body.email : undefined,
    plan: typeof body.plan_type === "string" ? body.plan_type : undefined,
    windows,
    credits,
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

function codexAppServerArgs(): string[] {
  return ["-s", "read-only", "-a", "untrusted", "app-server"];
}

async function runCliRpcProbe(): Promise<CodexQuotaSnapshot | null> {
  return new Promise((resolve) => {
    const child = spawn("codex", codexAppServerArgs(), { cwd: homedir(), stdio: ["pipe", "pipe", "pipe"] });

    let buffer = "";
    let settled = false;
    let nextId = 1;
    const pending = new Map<number, (result: Record<string, unknown>) => void>();

    const finish = (result: CodexQuotaSnapshot | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(hardTimeout);
      try {
        child.kill("SIGKILL");
      } catch {
        // already gone
      }
      resolve(result);
    };

    child.on("error", () => finish(null));

    child.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
      let newlineIndex: number;
      while ((newlineIndex = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 1);
        if (!line.trim()) continue;
        try {
          const message = JSON.parse(line) as { id?: number; result?: Record<string, unknown> };
          if (typeof message.id === "number" && pending.has(message.id)) {
            pending.get(message.id)!(message.result ?? {});
            pending.delete(message.id);
          }
        } catch {
          // ignore non-JSON or partial lines
        }
      }
    });

    function send(method: string, params: unknown, timeoutMs: number): Promise<Record<string, unknown> | null> {
      const id = nextId++;
      return new Promise((res) => {
        const timer = setTimeout(() => {
          pending.delete(id);
          res(null);
        }, timeoutMs);
        pending.set(id, (result) => {
          clearTimeout(timer);
          res(result);
        });
        child.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params: params ?? {} }) + "\n");
      });
    }

    (async () => {
      const init = await send("initialize", { clientInfo: { name: "baby-menu", version: "1.0.0" } }, 15000);
      if (!init) return finish(null);

      const [accountResult, rateLimitsResult] = await Promise.all([
        send("account/read", {}, 8000),
        send("account/rateLimits/read", {}, 8000),
      ]);
      if (!rateLimitsResult) return finish(null);

      const account = accountResult?.account as Record<string, unknown> | undefined;
      const rateLimits = rateLimitsResult.rateLimits as Record<string, unknown> | undefined;
      const windows: QuotaWindow[] = [];
      if (rateLimits) {
        const primary = windowFromEntry("primary", rateLimits.primary);
        const secondary = windowFromEntry("secondary", rateLimits.secondary);
        if (primary) windows.push(primary);
        if (secondary) windows.push(secondary);
      }

      const creditsRaw = rateLimits?.credits as Record<string, unknown> | undefined;
      let credits: CodexQuotaSnapshot["credits"];
      if (creditsRaw && (creditsRaw.hasCredits === true || creditsRaw.unlimited === true)) {
        credits = {
          hasCredits: Boolean(creditsRaw.hasCredits),
          unlimited: Boolean(creditsRaw.unlimited),
          balance: typeof creditsRaw.balance === "string" ? Number(creditsRaw.balance) : undefined,
        };
      }

      finish({
        source: "cli-rpc",
        accountEmail: typeof account?.email === "string" ? account.email : undefined,
        plan: typeof account?.planType === "string" ? account.planType : undefined,
        windows,
        credits,
        refreshedAt: new Date().toISOString(),
        stale: false,
      });
    })();

    const hardTimeout = setTimeout(() => finish(null), 25000);
  });
}

async function getLastGoodSnapshot(context: BabyMenuServerContext): Promise<CodexQuotaSnapshot | null> {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
  const row = context.db.get<{ json: string }>(`SELECT json FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return null;
  try {
    return JSON.parse(row.json) as CodexQuotaSnapshot;
  } catch {
    return null;
  }
}

function saveSnapshot(context: BabyMenuServerContext, snapshot: CodexQuotaSnapshot) {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
  context.db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json`,
    [JSON.stringify(snapshot)],
  );
}

export const actions = {
  getQuota: async (_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult<CodexQuotaSnapshot>> => {
    const sourceTried: string[] = [];
    const auth = readAuthFile();

    let sawRejection = false;
    let sawTransportFailure = false;

    if (auth) {
      sourceTried.push("oauth");
      const response = await callUsageApi(auth);
      if (!response) {
        sawTransportFailure = true;
      } else if (response.status === 401 || response.status === 403) {
        sawRejection = true;
      } else if (response.status === 200 && response.body && typeof response.body === "object") {
        const snapshot = normalizeOauthResponse(response.body as Record<string, unknown>);
        saveSnapshot(context, snapshot);
        return { ok: true, data: snapshot };
      } else {
        sawTransportFailure = true;
      }
    }

    sourceTried.push("cli-rpc");
    const cliSnapshot = await runCliRpcProbe();
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

    if (!auth || sawRejection) {
      return { ok: false, error: "Run `codex` to log in.", sourceTried };
    }
    return { ok: false, error: "Codex quota unavailable", sourceTried };
  },
};
