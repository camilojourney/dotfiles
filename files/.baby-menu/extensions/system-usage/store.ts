import { useSyncExternalStore } from "react";

export type SystemUsageSample = {
  cpuPercent: number | null;
  memoryPercent: number | null;
};

type SampleResponse = { cpuPercent: number | null; memoryPercent: number | null };

let state: SystemUsageSample = { cpuPercent: null, memoryPercent: null };
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
  setState({ cpuPercent: result.cpuPercent, memoryPercent: result.memoryPercent });
}
