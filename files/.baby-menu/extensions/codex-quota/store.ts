import { useSyncExternalStore } from "react";

type QuotaWindow = {
  id: string;
  label: string;
  percentUsed?: number;
  resetText?: string;
  resetAt?: string;
};

type CodexQuotaSnapshot = {
  source: "oauth" | "cli-rpc";
  accountEmail?: string;
  plan?: string;
  windows: QuotaWindow[];
  credits?: { balance?: number; hasCredits?: boolean; unlimited?: boolean };
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

export type CodexQuotaState =
  | { status: "loading" }
  | { status: "error"; error: string }
  | { status: "ready"; data: CodexQuotaSnapshot };

let state: CodexQuotaState = { status: "loading" };
const listeners = new Set<() => void>();

function setState(next: CodexQuotaState) {
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

export function useCodexQuota() {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function fetchCodexQuota() {
  const result = await window.babyMenu!.capabilities.invoke<QuotaResult<CodexQuotaSnapshot>>("codex-quota", "getQuota");
  if (result.ok) {
    setState({ status: "ready", data: result.data });
  } else {
    setState({ status: "error", error: result.error });
  }
}
