import { QuotaRow, QuotaValue, QuotaWindowRow } from "./shared/quota-components";
import { TEXT_STYLES, quotaTone } from "./shared/ui-styles";
import type { QuotaFailure, QuotaWindow } from "./store";
import { useGrokQuota } from "./store";

// Reverse of server.ts PRODUCT_NAMES, used only to recover the numeric product
// enum for the data-grok-products observability attribute.
const PRODUCT_IDS: Record<string, number> = { API: 1, "Grok Build": 2, "Grok Plugins": 3, Chat: 4, Imagine: 5, Voice: 6 };

function productIdFromLabel(label: string): number | undefined {
  if (label in PRODUCT_IDS) return PRODUCT_IDS[label];
  const match = label.match(/^product (\d+)$/);
  return match ? Number(match[1]) : undefined;
}

function formatReset(resetAt?: string): { relative: string; absolute: string } | undefined {
  if (!resetAt) return undefined;
  const date = new Date(resetAt);
  if (Number.isNaN(date.getTime())) return undefined;
  const diffMs = date.getTime() - Date.now();
  const days = Math.floor(diffMs / 86_400_000);
  const hours = Math.floor((diffMs % 86_400_000) / 3_600_000);
  let relative: string;
  if (diffMs <= 0) relative = "resets soon";
  else if (days > 0) relative = `resets in ${days}d ${hours}h`;
  else relative = `resets in ${hours}h`;
  const absolute = date.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
  return { relative, absolute };
}

function periodLabel(type: "weekly" | "monthly" | "unspecified"): string {
  if (type === "weekly") return "Weekly";
  if (type === "monthly") return "Monthly";
  return "Credits";
}

// Distinct actionable copy per failure kind. Never suggest browser sign-in for
// official_quota_source_unavailable - that is a provider outage, not an auth gap.
function failureCopy(failure: QuotaFailure): string {
  switch (failure.kind) {
    case "auth_source_missing":
    case "auth_source_incompatible":
    case "credential_rejected":
    case "auth_required":
      return "sign in to Grok to see quota";
    case "auth_expired":
      return "Grok sign-in expired; sign in again";
    case "auth_scope_ambiguous":
      return "multiple Grok sign-ins found; refresh baby menu";
    case "auth_principal_changed":
      return "Grok account changed locally; refresh baby menu";
    case "auth_source_unreadable":
      return "could not read Grok credentials";
    case "auth_source_malformed":
      return "Grok credentials file is malformed";
    case "team_scope_unsupported":
      return "Grok team scope not supported";
    case "cli_not_found":
      return "Grok CLI not found for sign-in refresh";
    case "cli_launch_failed":
      return "Grok CLI refresh failed";
    case "rate_limited":
      return "Grok quota check rate limited";
    case "response_too_large":
      return "Grok quota response was too large";
    case "parse_incompatible":
      return "Grok quota response could not be parsed";
    case "quota_unreported":
      return "Grok did not report quota for this account";
    case "official_quota_source_unavailable":
      return "Grok quota source is temporarily unavailable";
    case "connectivity":
    case "quota_service":
    default:
      return failure.message || "Grok quota unavailable";
  }
}

// One rendered root owns the complete data-grok-* observability contract in
// every state, per recipes/grok-quota.html "Renderer and Refresh Contract".
type E2EAttrs = Record<string, string>;

function waitingAttrs(): E2EAttrs {
  return {
    "data-grok-e2e": "waiting",
    "data-grok-checked-at": "",
    "data-grok-stale": "false",
    "data-grok-warning-kind": "none",
    "data-grok-failure-kind": "none",
    "data-grok-cache-schema": "",
    "data-grok-source": "",
    "data-grok-source-version": "",
    "data-grok-operation": "",
    "data-grok-period": "",
    "data-grok-percent-used": "",
    "data-grok-percent-remaining": "",
    "data-grok-percentage-field": "",
    "data-grok-reset-at": "",
    "data-grok-reset-field": "",
    "data-grok-products": "[]",
    "data-grok-completed-acquisitions": "0",
  };
}

function failureAttrs(failure: QuotaFailure, checkedAt: string, completedAcquisitions: number): E2EAttrs {
  return {
    ...waitingAttrs(),
    "data-grok-e2e": "failure",
    "data-grok-checked-at": checkedAt,
    "data-grok-failure-kind": failure.kind,
    "data-grok-completed-acquisitions": String(completedAcquisitions),
  };
}

function successAttrs(
  data: {
    stale: boolean;
    source: string;
    sourceVersion: number;
    operation: string;
    period: { type: "weekly" | "monthly" | "unspecified" };
    windows: QuotaWindow[];
  },
  checkedAt: string,
  warning: QuotaFailure | undefined,
  completedAcquisitions: number,
): E2EAttrs {
  const primary = data.windows.find((w) => w.id === "credits");
  const products = data.windows
    .filter((w) => w.id !== "credits")
    .map((w) => ({ id: productIdFromLabel(w.label), percentUsed: w.percentUsed }))
    .filter((p): p is { id: number; percentUsed: number } => p.id !== undefined);

  return {
    "data-grok-e2e": "success",
    "data-grok-checked-at": checkedAt,
    "data-grok-stale": data.stale ? "true" : "false",
    "data-grok-warning-kind": data.stale && warning ? warning.kind : "none",
    "data-grok-failure-kind": "none",
    "data-grok-cache-schema": "2",
    "data-grok-source": data.source,
    "data-grok-source-version": String(data.sourceVersion),
    "data-grok-operation": data.operation,
    "data-grok-period": data.period.type,
    "data-grok-percent-used": primary ? String(primary.percentUsed) : "",
    "data-grok-percent-remaining": primary ? String(primary.percentRemaining) : "",
    "data-grok-percentage-field": primary ? primary.provenance.percentageField : "",
    "data-grok-reset-at": primary?.resetAt ?? "",
    "data-grok-reset-field": primary?.resetAt ? "config.currentPeriod.end" : "",
    "data-grok-products": JSON.stringify(products),
    "data-grok-completed-acquisitions": String(completedAcquisitions),
  };
}

export function GrokQuotaView() {
  const state = useGrokQuota();
  if (state.status === "waiting") {
    return <QuotaRow name="grok" tone="muted" {...waitingAttrs()}><span className={TEXT_STYLES.content}>checking usage...</span></QuotaRow>;
  }
  if (state.status === "failure") {
    return (
      <QuotaRow name="grok" tone="danger" hint={state.pending ? "updating..." : undefined} {...failureAttrs(state.failure, state.checkedAt, state.completedAcquisitions)}>
        <span className={TEXT_STYLES.content}>{failureCopy(state.failure)}</span>
      </QuotaRow>
    );
  }

  const { data } = state;
  const primary = data.windows.find((window) => window.id === "credits") ?? data.windows[0];
  const secondary = data.windows.filter((window) => window !== primary).sort((a, b) => b.percentUsed - a.percentUsed)[0];
  const resetInfo = formatReset(primary?.resetAt);
  const displayed = [primary, secondary].filter((window): window is NonNullable<typeof window> => window !== undefined);
  return (
    <QuotaRow name="grok" plan={periodLabel(data.period.type)} tone={data.stale ? "warn" : "live"} hint={data.stale ? "cached" : undefined} {...successAttrs(data, state.checkedAt, state.warning, state.completedAcquisitions)}>
      {displayed.map((window) => (
        <QuotaWindowRow
          key={window.id}
          label={window.label}
          remaining={window.percentRemaining}
          reset={window === primary ? resetInfo?.relative : window.resetAt ? "same reset" : "active"}
          note={window === primary && data.credits ? "prepaid credits " + data.credits.remaining : undefined}
        >
          {window === primary && <QuotaValue value={Math.round(window.percentRemaining)} unit="%" tone={quotaTone(window.percentRemaining)} label={window.label === "Grok Build" ? "build left" : "left"} />}
        </QuotaWindowRow>
      ))}
      {displayed.length === 0 && <span className={TEXT_STYLES.content}>no metered usage reported</span>}
    </QuotaRow>
  );
}
