import { useSyncExternalStore } from "react";

type BalanceInfo = {
  currency: string;
  totalBalance: number;
  grantedBalance: number;
  toppedUpBalance: number;
};

type DeepseekQuotaSnapshot = {
  source: "api";
  available: boolean;
  balances: BalanceInfo[];
  refreshedAt: string;
  stale: boolean;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

export type DeepseekQuotaState =
  | { status: "loading" }
  | { status: "error"; error: string }
  | { status: "ready"; data: DeepseekQuotaSnapshot };

let state: DeepseekQuotaState = { status: "loading" };
const listeners = new Set<() => void>();

function setState(next: DeepseekQuotaState) {
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

export function useDeepseekQuota() {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export async function fetchDeepseekQuota() {
  const result = await window.babyMenu!.capabilities.invoke<QuotaResult<DeepseekQuotaSnapshot>>(
    "deepseek-quota",
    "getQuota",
  );
  if (result.ok) {
    setState({ status: "ready", data: result.data });
  } else {
    setState({ status: "error", error: result.error });
  }
}
