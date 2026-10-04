import { useSyncExternalStore } from "react";

export type AntigravityQuotaWindow = {
  kind: "5h" | "weekly";
  percentRemaining: number;
  resetsAt?: string;
};

export type AntigravityQuotaPool = {
  id: "gemini" | "claude-gpt";
  label: string;
  windows: AntigravityQuotaWindow[];
};

export type AntigravityQuotaSnapshot = {
  source: "agy /quota";
  checkedAt: string;
  pools: AntigravityQuotaPool[];
};

// A pool is only as available as its tightest window (5-hour or weekly).
export function limitingWindow(pool: AntigravityQuotaPool): AntigravityQuotaWindow {
  return pool.windows.reduce((tightest, window) => (window.percentRemaining < tightest.percentRemaining ? window : tightest));
}

type Result = { ok: true; data: AntigravityQuotaSnapshot } | { ok: false; error: string };
type State =
  | { status: "loading" }
  | { status: "error"; error: string }
  | { status: "ready"; data: AntigravityQuotaSnapshot };

let state: State = { status: "loading" };
let inFlight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function setState(next: State) {
  state = next;
  for (const listener of listeners) listener();
}

export function useAntigravityQuota() {
  return useSyncExternalStore(
    (listener) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    () => state,
  );
}

export function fetchAntigravityQuota() {
  if (inFlight) return inFlight;
  inFlight = window.babyMenu!.capabilities
    .invoke<Result>("antigravity-quota", "getQuota")
    .then((result) => {
      setState(result.ok ? { status: "ready", data: result.data } : { status: "error", error: result.error });
    })
    .catch(() => setState({ status: "error", error: "Antigravity quota check failed" }))
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}
