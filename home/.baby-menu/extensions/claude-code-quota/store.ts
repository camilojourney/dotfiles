import { useSyncExternalStore } from "react";

type QuotaWindow = {
  id: string;
  label: string;
  percentUsed?: number;
  resetText?: string;
  resetAt?: string;
  spentUsd?: number;
  limitUsd?: number;
};

type ClaudeQuotaSnapshot = {
  source: "oauth" | "cli";
  accountEmail?: string;
  plan?: string;
  windows: QuotaWindow[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

export type ClaudeQuotaState =
  | { status: "loading" }
  | { status: "error"; error: string }
  | { status: "ready"; data: ClaudeQuotaSnapshot };

let state: ClaudeQuotaState = { status: "loading" };
const listeners = new Set<() => void>();

function setState(next: ClaudeQuotaState) {
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

export function useClaudeQuota() {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function fetchClaudeQuota() {
  const result = await window.babyMenu!.capabilities.invoke<QuotaResult<ClaudeQuotaSnapshot>>(
    "claude-code-quota",
    "getQuota",
  );
  if (result.ok) {
    setState({ status: "ready", data: result.data });
  } else {
    setState({ status: "error", error: result.error });
  }
}
