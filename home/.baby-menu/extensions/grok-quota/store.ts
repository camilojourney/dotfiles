import { useSyncExternalStore } from "react";

// Mirrors the normalized shapes in recipes/grok-quota.html - keep in sync with
// grok-quota/server.ts.

export type Provenance = {
  percentageField: "config.creditUsagePercent" | `config.productUsage[${number}].usagePercent`;
  resetField?: "config.currentPeriod.end";
  omittedProto3Default?: true;
};

export type QuotaWindow = {
  id: "credits" | `product:${string}`;
  label: string;
  percentUsed: number;
  percentRemaining: number;
  resetAt?: string;
  provenance: Provenance;
};

export type GrokQuotaSnapshot = {
  schemaVersion: 2;
  source: "grok-credits-grpc-web";
  sourceVersion: 1;
  operation: "grok_api_v2.GrokBuildBilling.GetGrokCreditsConfig";
  period: { type: "weekly" | "monthly" | "unspecified"; startAt?: string; endAt?: string; provenance: "config.currentPeriod" };
  windows: QuotaWindow[];
  credits?: { remaining: number; unit: "credits"; sourceField: "config.prepaidBalance.val" };
  refreshedAt: string;
  stale: boolean;
};

export type FailureKind =
  | "auth_required"
  | "auth_expired"
  | "auth_scope_ambiguous"
  | "auth_principal_changed"
  | "auth_source_missing"
  | "auth_source_unreadable"
  | "auth_source_malformed"
  | "auth_source_incompatible"
  | "credential_rejected"
  | "cli_not_found"
  | "cli_launch_failed"
  | "connectivity"
  | "rate_limited"
  | "quota_service"
  | "official_quota_source_unavailable"
  | "team_scope_unsupported"
  | "response_too_large"
  | "quota_unreported"
  | "parse_incompatible";

export type QuotaFailure = {
  kind: FailureKind;
  message: string;
  sourcesTried: Array<"local-auth" | "consumer-quota-api" | "grok-cli-refresh" | "cache">;
  httpStatus?: number;
  grpcStatus?: number;
  retryAt?: string;
  diagnostic?: string;
};

type GrokQuotaResult =
  | { ok: true; checkedAt: string; data: GrokQuotaSnapshot; warning?: QuotaFailure }
  | { ok: false; checkedAt: string; failure: QuotaFailure };

// While a later refresh is pending, a completed success/failure root keeps its
// terminal state and values - only `pending` flips - per the renderer contract.
export type GrokQuotaState =
  | { status: "waiting"; pending: boolean; completedAcquisitions: 0 }
  | { status: "success"; data: GrokQuotaSnapshot; checkedAt: string; warning?: QuotaFailure; pending: boolean; completedAcquisitions: number }
  | { status: "failure"; failure: QuotaFailure; checkedAt: string; pending: boolean; completedAcquisitions: number };

let state: GrokQuotaState = { status: "waiting", pending: false, completedAcquisitions: 0 };
let completedAcquisitions = 0;
let inFlight: Promise<void> | null = null;
const listeners = new Set<() => void>();

function setState(next: GrokQuotaState) {
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

export function useGrokQuota() {
  return useSyncExternalStore(subscribe, getSnapshot);
}

export function fetchGrokQuota() {
  if (inFlight) return inFlight;

  setState({ ...state, pending: true });

  inFlight = window
    .babyMenu!.capabilities.invoke<GrokQuotaResult>("grok-quota", "getQuota")
    .then((result) => {
      completedAcquisitions += 1;
      if (result.ok) {
        setState({
          status: "success",
          data: result.data,
          checkedAt: result.checkedAt,
          warning: result.warning,
          pending: false,
          completedAcquisitions,
        });
      } else {
        setState({ status: "failure", failure: result.failure, checkedAt: result.checkedAt, pending: false, completedAcquisitions });
      }
    })
    .catch(() => {
      completedAcquisitions += 1;
      setState({
        status: "failure",
        failure: { kind: "connectivity", message: "Grok quota check failed", sourcesTried: [] },
        checkedAt: new Date().toISOString(),
        pending: false,
        completedAcquisitions,
      });
    })
    .finally(() => {
      inFlight = null;
    });

  return inFlight;
}
