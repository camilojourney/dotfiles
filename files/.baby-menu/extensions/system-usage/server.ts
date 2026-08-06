import { cpus, totalmem } from "node:os";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { BabyMenuServerContext } from "@babymenu/contracts";

const execFileAsync = promisify(execFile);

const CPU_BASELINE_TABLE = "system_usage_cpu_baseline";

function readCpuTotals() {
  let idle = 0;
  let total = 0;
  for (const core of cpus()) {
    const t = core.times;
    idle += t.idle;
    total += t.user + t.nice + t.sys + t.idle + t.irq;
  }
  return { idle, total };
}

// CPU percent is rate-derived: we persist the previous cumulative core times in
// db and diff against the new reading, so the gap between refreshes is the
// sampling window. The first call (or one after a reset) has no baseline, so it
// stores one and reports null ("warming up") instead of a misleading 0 or 100.
function readCpuPercent(context: BabyMenuServerContext): number | null {
  context.db.exec(
    `CREATE TABLE IF NOT EXISTS ${CPU_BASELINE_TABLE} (id INTEGER PRIMARY KEY CHECK (id = 1), idle INTEGER NOT NULL, total INTEGER NOT NULL)`,
  );
  const { idle, total } = readCpuTotals();
  const prev = context.db.get<{ idle: number; total: number }>(
    `SELECT idle, total FROM ${CPU_BASELINE_TABLE} WHERE id = 1`,
  );
  context.db.run(
    `INSERT INTO ${CPU_BASELINE_TABLE} (id, idle, total) VALUES (1, ?, ?)
     ON CONFLICT(id) DO UPDATE SET idle = excluded.idle, total = excluded.total`,
    [idle, total],
  );
  if (!prev) return null;
  const idleDelta = idle - prev.idle;
  const totalDelta = total - prev.total;
  if (totalDelta <= 0) return null;
  const busyRatio = 1 - idleDelta / totalDelta;
  return Math.min(100, Math.max(0, busyRatio * 100));
}

function parsePageCount(vmStatOutput: string, label: string): number {
  const match = vmStatOutput.match(new RegExp(`${label}:\\s+(\\d+)\\.`));
  return match ? Number(match[1]) : 0;
}

// macOS's os.freemem() only counts literally free pages, which sit near zero on
// a healthy Mac (inactive/purgeable pages are reclaimable but not "free"), so it
// reports a misleading ~100% used. Read vm_stat directly instead and treat free,
// inactive, speculative, and purgeable pages as reclaimable "not used" memory -
// the same accounting macOS itself uses for the memory pressure it reports.
async function readMemoryPercent(): Promise<number> {
  const { stdout } = await execFileAsync("vm_stat");
  const pageSizeMatch = stdout.match(/page size of (\d+) bytes/);
  const pageSize = pageSizeMatch ? Number(pageSizeMatch[1]) : 4096;

  const free = parsePageCount(stdout, "Pages free");
  const inactive = parsePageCount(stdout, "Pages inactive");
  const speculative = parsePageCount(stdout, "Pages speculative");
  const purgeable = parsePageCount(stdout, "Pages purgeable");

  const reclaimableBytes = (free + inactive + speculative + purgeable) * pageSize;
  const total = totalmem();
  const usedBytes = Math.max(0, total - reclaimableBytes);
  return Math.min(100, Math.max(0, (usedBytes / total) * 100));
}

export const actions = {
  sample: async (_input: unknown, context: BabyMenuServerContext) => {
    const [memoryPercent, cpuPercent] = await Promise.all([
      readMemoryPercent(),
      Promise.resolve(readCpuPercent(context)),
    ]);
    return { cpuPercent, memoryPercent };
  },
};
