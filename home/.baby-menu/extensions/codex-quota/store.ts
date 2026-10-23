import { useSyncExternalStore } from "react";

import type { CodexQuotaSnapshot, QuotaResult } from "./types";

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
