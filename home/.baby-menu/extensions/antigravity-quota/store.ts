import { useSyncExternalStore } from "react";

export type AntigravityQuotaSnapshot = {
  source: "agy /usage";
  plan?: string;
  checkedAt: string;
  buckets: Array<{
    id: "gemini" | "claude-gpt";
    label: string;
    percentUsed: number;
    percentRemaining: number;
    windowLabel: "weekly";
    refreshesIn?: string;
  }>;
};

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
