export const DATA_VOLUME = "/System/Volumes/Data";

export type MachineCapacity = ReturnType<typeof summarizeResources>["capacity"] & {
  cpu: string;
  gpu: string | null;
};

export function summarizeResources(vmStat: string, totalMemory: number, dfOutput: string) {
  const memory = parseMemory(vmStat, totalMemory);
  const storage = parseStorage(dfOutput);
  return {
    memoryPercent: memory?.percent ?? null,
    storagePercent: storage?.percent ?? null,
    capacity: {
      memory: formatBytes(totalMemory),
      memoryUsed: memory ? formatBytes(memory.usedBytes) : "--",
      storage: storage ? formatBytes(storage.totalBytes) : "--",
      storageUsed: storage ? formatBytes(storage.usedBytes) : "--",
      storageFree: storage ? formatBytes(storage.freeBytes) : "--",
    },
  };
}

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return "--";
  const units = ["B", "KiB", "MiB", "GiB", "TiB"] as const;
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const precision = value >= 100 || Number.isInteger(value) ? 0 : 1;
  return `${value.toFixed(precision)} ${units[unitIndex]}`;
}

// APFS shares free space across volumes. Data's used blocks exclude System,
// VM and other siblings, so fullness is container size minus available space.
export function parseStorage(dfOutput: string) {
  const fields = dfOutput.trim().split("\n").find((line) => line.trim().endsWith(` ${DATA_VOLUME}`))?.trim().split(/\s+/);
  if (!fields) return null;
  const [total, used, free] = fields.slice(1, 4).map(Number);
  if (![total, used, free].every(Number.isSafeInteger)) return null;
  if (total <= 0 || used < 0 || free < 0 || used + free > total) return null;
  return {
    totalBytes: total * 1024,
    usedBytes: used * 1024,
    freeBytes: free * 1024,
    percent: ((total - free) / total) * 100,
  };
}

function pageCount(output: string, label: string): number | null {
  const match = output.match(new RegExp(`^${label}:\\s+(\\d+)\\.$`, "m"));
  return match ? Number(match[1]) : null;
}

// Memory used = non-purgeable anonymous + wired + physical compressor pages.
// Inactive is not all free; purgeable pages overlap other VM categories.
// Pressure's free percentage is a different metric, not RAM utilization.
export function parseMemory(vmStatOutput: string, totalBytes: number) {
  if (!Number.isFinite(totalBytes) || totalBytes <= 0) return null;
  const pageSize = Number(vmStatOutput.match(/page size of (\d+) bytes/)?.[1]);
  if (!Number.isSafeInteger(pageSize) || pageSize <= 0) return null;
  const pages = ["Anonymous pages", "Pages purgeable", "Pages wired down", "Pages occupied by compressor"].map((label) => pageCount(vmStatOutput, label));
  if (pages.some((value) => value === null)) return null;
  const [anonymous, purgeable, wired, compressed] = pages as number[];
  const usedBytes = (Math.max(0, anonymous - purgeable) + wired + compressed) * pageSize;
  if (usedBytes > totalBytes) return null;
  return { totalBytes, usedBytes, percent: (usedBytes / totalBytes) * 100 };
}
