import { execFile } from "node:child_process";

const QUOTA_TIMEOUT_MS = 20_000;
const MAX_OUTPUT_BYTES = 256 * 1024;
// Baby Menu launches without the login shell PATH, so try known install paths.
const AGY_BIN_CANDIDATES = [process.env.AGY_BIN, "/opt/homebrew/bin/agy", "/usr/local/bin/agy", "agy"].filter(Boolean) as string[];

type QuotaWindow = {
  kind: "5h" | "weekly";
  percentRemaining: number;
  resetsAt?: string;
};

type QuotaPool = {
  id: "gemini" | "claude-gpt";
  label: string;
  windows: QuotaWindow[];
};

type RawBucket = {
  window?: string;
  remaining_fraction?: number;
  reset_time?: string;
  disabled?: boolean | null;
};

type RawGroup = { name?: string; buckets?: RawBucket[] };

function runQuotaCommand(bin: string): Promise<string> {
  return new Promise((resolve, reject) => {
    // `agy -p "/quota"` is the CLI's noninteractive, read-only usage command;
    // it does not start an agent session or spend quota.
    execFile(
      bin,
      ["-p", "/quota", "--output-format", "json"],
      { timeout: QUOTA_TIMEOUT_MS, maxBuffer: MAX_OUTPUT_BYTES },
      (error, stdout) => (error ? reject(error) : resolve(stdout)),
    );
  });
}

async function readQuota(): Promise<string> {
  let lastError: unknown;
  for (const bin of AGY_BIN_CANDIDATES) {
    try {
      return await runQuotaCommand(bin);
    } catch (error) {
      lastError = error;
      if ((error as { code?: string }).code !== "ENOENT") break;
    }
  }
  const code = (lastError as { code?: string } | undefined)?.code;
  throw new Error(code === "ENOENT" ? "Antigravity CLI (agy) is not installed" : "Antigravity quota read failed");
}

function poolFor(name: string): Pick<QuotaPool, "id" | "label"> | undefined {
  const lower = name.toLowerCase();
  if (lower.includes("gemini")) return { id: "gemini", label: "Gemini models" };
  if (lower.includes("claude") || lower.includes("gpt")) return { id: "claude-gpt", label: "Claude + GPT models" };
  return undefined;
}

function parseQuota(stdout: string): QuotaPool[] {
  const payload = JSON.parse(stdout) as { status?: string; command?: { data?: { groups?: RawGroup[] } } };
  const pools: QuotaPool[] = [];
  for (const group of payload.command?.data?.groups ?? []) {
    const pool = poolFor(group.name ?? "");
    if (!pool) continue;
    const windows: QuotaWindow[] = [];
    for (const bucket of group.buckets ?? []) {
      if (bucket.disabled || typeof bucket.remaining_fraction !== "number") continue;
      const kind = bucket.window === "5h" ? "5h" : bucket.window === "weekly" ? "weekly" : undefined;
      if (!kind) continue;
      windows.push({
        kind,
        percentRemaining: Math.max(0, Math.min(100, bucket.remaining_fraction * 100)),
        resetsAt: bucket.reset_time,
      });
    }
    if (windows.length > 0) pools.push({ ...pool, windows });
  }
  return pools;
}

export const actions = {
  getQuota: async () => {
    let stdout: string;
    try {
      stdout = await readQuota();
    } catch (error) {
      return { ok: false as const, error: (error as Error).message };
    }

    let pools: QuotaPool[];
    try {
      pools = parseQuota(stdout);
    } catch {
      return { ok: false as const, error: "Antigravity quota response could not be read" };
    }
    if (pools.length === 0) {
      return { ok: false as const, error: "Antigravity reported no model quota (signed out?)" };
    }

    return {
      ok: true as const,
      data: {
        source: "agy /quota" as const,
        pools,
        checkedAt: new Date().toISOString(),
      },
    };
  },
};
