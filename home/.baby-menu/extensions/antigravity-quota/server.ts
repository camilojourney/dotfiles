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
  id: string;
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

function parseWindow(bucket: RawBucket): QuotaWindow | null {
  if (bucket.disabled || typeof bucket.remaining_fraction !== "number" || !Number.isFinite(bucket.remaining_fraction)) return null;
  if (bucket.window !== "5h" && bucket.window !== "weekly") return null;
  return {
    kind: bucket.window,
    percentRemaining: Math.max(0, Math.min(100, bucket.remaining_fraction * 100)),
    resetsAt: bucket.reset_time,
  };
}

function parsePool(group: RawGroup): QuotaPool | null {
  if (typeof group.name !== "string" || !group.name.trim() || !Array.isArray(group.buckets)) return null;
  const windows = group.buckets.map(parseWindow).filter((window): window is QuotaWindow => window !== null);
  if (windows.length === 0) return null;
  // Provider group names are distinct: Gemini Models and Gemini 4 Argon
  // must never share a label, React key, or aggregate percentage.
  return { id: group.name, label: group.name, windows };
}

function parseQuota(stdout: string): QuotaPool[] {
  const payload = JSON.parse(stdout) as { status?: string; command?: { data?: { groups?: RawGroup[] } } };
  if (payload.status !== "SUCCESS") return [];
  return (payload.command?.data?.groups ?? []).map(parsePool).filter((pool): pool is QuotaPool => pool !== null);
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
