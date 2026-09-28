import { useSyncExternalStore } from "react";

export type CursorQuotaWindow = {
  id: "included_usage" | "auto_usage" | "api_usage";
  label: string;
  kind?: "monthly";
  percentUsed: number;
  percentRemaining?: number;
  resetAt?: string;
};

export type CursorQuotaSnapshot = {
  source: "api";
  accountEmail?: string;
  plan?: string;
  windows: CursorQuotaWindow[];
  refreshedAt: string;
  stale: boolean;
  status?: string;
};

type QuotaResult<T> = { ok: true; data: T } | { ok: false; error: string; sourceTried: string[] };

export type CursorQuotaState =
  | { status: "loading"; pending: boolean }
  | { status: "error"; error: string; pending: boolean }
  | { status: "ready"; data: CursorQuotaSnapshot; pending: boolean };

let state: CursorQuotaState = { status: "loading", pending: false };
let inFlight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function setState(next: CursorQuotaState) {
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

export function useCursorQuota() {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export function fetchCursorQuota() {
  if (inFlight) return inFlight;

  setState({ ...state, pending: true });
  inFlight = window
    .babyMenu!.capabilities.invoke<QuotaResult<CursorQuotaSnapshot>>("cursor-quota", "getQuota")
    .then((result) => {
      setState(result.ok ? { status: "ready", data: result.data, pending: false } : { status: "error", error: result.error, pending: false });
    })
    .catch(() => {
      setState({ status: "error", error: "Cursor quota check failed", pending: false });
    })
    .finally(() => {
      inFlight = null;
    });

  return inFlight;
}

export function toneFor(percentUsed: number) {
  if (percentUsed >= 90) return "danger" as const;
  if (percentUsed >= 70) return "warn" as const;
  return "live" as const;
}

export function fillClassName(percentUsed: number) {
  const tone = toneFor(percentUsed);
  if (tone === "danger") return "h-full rounded-[1px] bg-[rgb(255,106,122)] shadow-[0_0_9px_rgba(255,106,122,.32)]";
  if (tone === "warn") return "h-full rounded-[1px] bg-[rgb(255,216,107)] shadow-[0_0_9px_rgba(255,216,107,.30)]";
  return "h-full rounded-[1px] bg-signal-live shadow-[0_0_9px_rgba(106,227,182,.38)]";
}

export function remainingClassName(percentUsed: number) {
  const tone = toneFor(percentUsed);
  if (tone === "danger") return "text-signal-danger";
  if (tone === "warn") return "text-signal-warn";
  return "text-ink-strong";
}

export function percentLeft(window: CursorQuotaWindow | undefined): number | null {
  if (!window) return null;
  return typeof window.percentRemaining === "number" ? window.percentRemaining : Math.max(0, 100 - window.percentUsed);
}

export function formatPercent(value: number): string {
  if (value >= 99.5 && value < 100) return "99.5";
  if (value < 10 && value % 1 !== 0) return value.toFixed(1);
  return String(Math.round(value));
}

export function formatReset(resetAt?: string): string | undefined {
  if (!resetAt) return undefined;
  const date = new Date(resetAt);
  if (Number.isNaN(date.getTime())) return undefined;
  const diffMs = date.getTime() - Date.now();
  const days = Math.floor(diffMs / 86_400_000);
  const hours = Math.floor((diffMs % 86_400_000) / 3_600_000);
  if (diffMs <= 0) return "resets soon";
  if (days > 0) return `resets in ${days}d ${hours}h`;
  if (hours < 1) return "resets in <1h";
  return `resets in ${hours}h`;
}
