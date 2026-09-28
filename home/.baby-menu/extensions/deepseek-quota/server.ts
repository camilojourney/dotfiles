import { readFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { BabyMenuServerContext } from "@babymenu/contracts";

const SNAPSHOT_TABLE = "deepseek_quota_snapshot";

type BalanceInfo = {
  currency: string;
  totalBalance: number;
  grantedBalance: number;
  toppedUpBalance: number;
};

type DeepseekQuotaSnapshot = {
  source: "api";
  available: boolean;
  balances: BalanceInfo[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

function resolveOpencodeAuthPath(): string {
  const dataHome = process.env.XDG_DATA_HOME;
  if (dataHome) return join(dataHome, "opencode", "auth.json");
  return join(homedir(), ".local", "share", "opencode", "auth.json");
}

function readDeepseekKey(): string | null {
  const path = resolveOpencodeAuthPath();
  if (!existsSync(path)) return null;
  try {
    const json = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
    const entry = json.deepseek as Record<string, unknown> | undefined;
    if (!entry || entry.type !== "api") return null;
    const key = entry.key;
    return typeof key === "string" && key.length > 0 ? key : null;
  } catch {
    return null;
  }
}

function toNumber(value: unknown): number {
  const n = typeof value === "string" ? Number(value) : typeof value === "number" ? value : NaN;
  return Number.isFinite(n) ? n : 0;
}

async function callBalanceApi(key: string): Promise<{ status: number; body: unknown } | null> {
  try {
    const res = await fetch("https://api.deepseek.com/user/balance", {
      headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
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

function normalizeResponse(body: Record<string, unknown>): DeepseekQuotaSnapshot | null {
  const rawBalances = body.balance_infos;
  if (!Array.isArray(rawBalances)) return null;
  const balances: BalanceInfo[] = rawBalances.map((entry) => {
    const e = (entry ?? {}) as Record<string, unknown>;
    return {
      currency: typeof e.currency === "string" ? e.currency : "USD",
      totalBalance: toNumber(e.total_balance),
      grantedBalance: toNumber(e.granted_balance),
      toppedUpBalance: toNumber(e.topped_up_balance),
    };
  });
  return {
    source: "api",
    available: body.is_available === true,
    balances,
    refreshedAt: new Date().toISOString(),
    stale: false,
  };
}

function getLastGoodSnapshot(context: BabyMenuServerContext): DeepseekQuotaSnapshot | null {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
  const row = context.db.get<{ json: string }>(`SELECT json FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return null;
  try {
    return JSON.parse(row.json) as DeepseekQuotaSnapshot;
  } catch {
    return null;
  }
}

function saveSnapshot(context: BabyMenuServerContext, snapshot: DeepseekQuotaSnapshot) {
  context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
  context.db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json`,
    [JSON.stringify(snapshot)],
  );
}

export const actions = {
  getQuota: async (_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult<DeepseekQuotaSnapshot>> => {
    const sourceTried: string[] = ["opencode-auth"];
    const key = readDeepseekKey();
    if (!key) {
      return { ok: false, error: "DeepSeek key not found (add it in opencode)", sourceTried };
    }

    sourceTried.push("deepseek-balance-api");
    const response = await callBalanceApi(key);
    if (!response) {
      const lastGood = getLastGoodSnapshot(context);
      if (lastGood) return { ok: true, data: { ...lastGood, stale: true } };
      return { ok: false, error: "DeepSeek quota unavailable", sourceTried };
    }
    if (response.status === 401 || response.status === 403) {
      return { ok: false, error: "DeepSeek key rejected", sourceTried };
    }
    if (response.status === 200 && response.body && typeof response.body === "object") {
      const snapshot = normalizeResponse(response.body as Record<string, unknown>);
      if (snapshot) {
        saveSnapshot(context, snapshot);
        return { ok: true, data: snapshot };
      }
    }

    const lastGood = getLastGoodSnapshot(context);
    if (lastGood) return { ok: true, data: { ...lastGood, stale: true } };
    return { ok: false, error: "DeepSeek quota unavailable", sourceTried };
  },
};
