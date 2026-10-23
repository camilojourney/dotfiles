import { execFile } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { promisify } from "node:util";
import type { BabyMenuServerContext } from "@babymenu/contracts";
import type { CodexQuotaSnapshot, QuotaResult } from "./types";

const execFileAsync = promisify(execFile);
const SNAPSHOT_TABLE = "codex_quota_snapshot";
const SOURCE = "pi:openai-codex";

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function quotaWindow(value: unknown): CodexQuotaSnapshot["windows"][number] | null {
  if (!isRecord(value) || typeof value.id !== "string" || typeof value.label !== "string") return null;
  if (typeof value.percentUsed !== "number" || !Number.isFinite(value.percentUsed)) return null;
  return {
    id: value.id,
    label: value.label,
    percentUsed: Math.max(0, Math.min(100, value.percentUsed)),
    resetAt: typeof value.resetsAt === "string" ? value.resetsAt : undefined,
  };
}

function findProvider(report: unknown): Record<string, unknown> | null {
  if (!isRecord(report) || report.schemaVersion !== 5 || !Array.isArray(report.providers)) return null;
  const provider = report.providers.find((item: unknown) => isRecord(item) && item.provider === "codex" && item.source === SOURCE);
  return isRecord(provider) ? provider : null;
}

function normalizeReport(report: unknown): CodexQuotaSnapshot | null {
  const provider = findProvider(report);
  if (!provider || !Array.isArray(provider.windows) || !isRecord(provider.state)) return null;
  if (!["fresh", "stale"].includes(provider.state.status as string)) return null;
  const windows = provider.windows.map(quotaWindow).filter((window): window is NonNullable<typeof window> => window !== null);
  if (windows.length === 0 || typeof provider.state.refreshedAt !== "string") return null;
  const account = isRecord(provider.account) ? provider.account : undefined;
  return {
    source: SOURCE,
    accountEmail: typeof account?.email === "string" ? account.email : undefined,
    plan: typeof provider.plan === "string" ? provider.plan : undefined,
    windows,
    refreshedAt: provider.state.refreshedAt,
    stale: provider.state.status === "stale",
  };
}

async function readQuota(): Promise<CodexQuotaSnapshot | null> {
  // Menu-bar apps do not inherit the login shell's Homebrew PATH.
  const executable = ["/opt/homebrew/bin/quota-axi", "/usr/local/bin/quota-axi"].find(existsSync) ?? "quota-axi";
  const { stdout } = await execFileAsync(executable, ["--provider", "codex", "--json", "--full", "--no-credential-refresh"], {
    cwd: homedir(),
    timeout: 30_000,
    maxBuffer: 1024 * 1024,
    env: { ...process.env, PATH: `/opt/homebrew/bin:/usr/local/bin:${process.env.PATH ?? "/usr/bin:/bin"}` },
  });
  return normalizeReport(JSON.parse(stdout));
}

function loadSnapshot(context: BabyMenuServerContext): CodexQuotaSnapshot | null {
  const row = context.db.get<{ json: string }>(`SELECT json FROM ${SNAPSHOT_TABLE} WHERE id = 1`);
  if (!row) return null;
  try {
    const snapshot: CodexQuotaSnapshot = JSON.parse(row.json);
    // Never show an old native Codex account as the requested Pi account.
    return snapshot.source === SOURCE ? snapshot : null;
  } catch {
    return null;
  }
}

function saveSnapshot(context: BabyMenuServerContext, snapshot: CodexQuotaSnapshot) {
  context.db.run(
    `INSERT INTO ${SNAPSHOT_TABLE} (id, json) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET json = excluded.json`,
    [JSON.stringify(snapshot)],
  );
}

export const actions = {
  getQuota: async (_input: unknown, context: BabyMenuServerContext): Promise<QuotaResult<CodexQuotaSnapshot>> => {
    context.db.exec(`CREATE TABLE IF NOT EXISTS ${SNAPSHOT_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), json TEXT NOT NULL)`);
    let snapshot: CodexQuotaSnapshot | null;
    try {
      snapshot = await readQuota();
    } catch (error) {
      // CLI launch, timeout, exit and malformed JSON are unavailable readings,
      // not evidence that the user's Pi sign-in has stopped working.
      if (!(error instanceof Error)) throw error;
      const code = (error as NodeJS.ErrnoException).code;
      if (!(error instanceof SyntaxError) && code === undefined && !("killed" in error)) throw error;
      snapshot = null;
    }
    if (snapshot) {
      saveSnapshot(context, snapshot);
      return { ok: true, data: snapshot };
    }
    const lastGood = loadSnapshot(context);
    if (lastGood) return { ok: true, data: { ...lastGood, stale: true } };
    return { ok: false, error: "Pi Codex quota unavailable", sourceTried: ["quota-axi", SOURCE] };
  },
};
