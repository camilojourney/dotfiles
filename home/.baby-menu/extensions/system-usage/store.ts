import { useSyncExternalStore } from "react";
import type { MachineCapacity } from "./metrics";

export type RebuildStatus = {
  state: "ok" | "failed" | "running" | "unfinished" | "never" | "unknown";
  target: string | null;
  atMs: number | null;
};

export type SystemUsageSample = {
  cpuPercent: number | null;
  memoryPercent: number | null;
  storagePercent: number | null;
  capacity: MachineCapacity;
  rebuild: RebuildStatus;
  miniMac: {
    status: "online" | "offline";
    rebuild: RebuildStatus;
    cpuPercent: number | null;
    memoryPercent: number | null;
    storagePercent: number | null;
    capacity: MachineCapacity;
    gpuSummary: string | null;
  };
  githubContributions: {
    status: "live" | "stale" | "unavailable";
    login: string;
    weeks: number;
    cells: Array<
      Array<{
        date: string;
        level: 0 | 1 | 2 | 3 | 4;
        count: number | null;
      }>
    >;
    weeklyTotals: Array<{
      start: string;
      end: string;
      total: number;
    }>;
    todayCount: number | null;
    currentWeekTotal: number | null;
    totalContributions: number | null;
    rangeStart: string | null;
    rangeEnd: string | null;
    fetchedAt: number | null;
    error: string | null;
  };
};

type SampleResponse = SystemUsageSample;

let state: SystemUsageSample = {
  cpuPercent: null,
  memoryPercent: null,
  storagePercent: null,
  capacity: { cpu: "--", memory: "--", storage: "--", memoryUsed: "--", storageUsed: "--", storageFree: "--", gpu: null },
  rebuild: { state: "unknown", target: null, atMs: null },
  miniMac: {
    status: "offline",
    rebuild: { state: "unknown", target: null, atMs: null },
    cpuPercent: null,
    memoryPercent: null,
    storagePercent: null,
    capacity: { cpu: "--", memory: "--", storage: "--", memoryUsed: "--", storageUsed: "--", storageFree: "--", gpu: null },
    gpuSummary: null,
  },
  githubContributions: {
    status: "unavailable",
    login: "camilojourney",
    weeks: 26,
    cells: Array.from({ length: 7 }, () => []),
    weeklyTotals: [],
    todayCount: null,
    currentWeekTotal: null,
    totalContributions: null,
    rangeStart: null,
    rangeEnd: null,
    fetchedAt: null,
    error: null,
  },
};
const listeners = new Set<() => void>();

function setState(next: SystemUsageSample) {
  state = next;
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function getSnapshot() {
  return state;
}

export function useSystemUsage() {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function fetchSystemUsage() {
  const result = await window.babyMenu!.capabilities.invoke<SampleResponse>("system-usage", "sample");
  setState(result);
}
