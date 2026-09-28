import { Badge, StatusDot } from "@babymenu/ui";
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

function toneFor(percentUsed: number) {
  if (percentUsed >= 90) return "danger" as const;
  if (percentUsed >= 70) return "warn" as const;
  return "live" as const;
}

function fillClassName(percentUsed: number) {
  const clamped = Math.max(0, Math.min(100, percentUsed));
  const tone = toneFor(clamped);
  if (tone === "danger") return "h-full rounded-[1px] bg-[rgb(255,106,122)] shadow-[0_0_9px_rgba(255,106,122,.32)]";
  if (tone === "warn") return "h-full rounded-[1px] bg-[rgb(255,216,107)] shadow-[0_0_9px_rgba(255,216,107,.30)]";
  return "h-full rounded-[1px] bg-signal-live shadow-[0_0_9px_rgba(106,227,182,.38)]";
}

function remainingClassName(percentUsed: number) {
  const tone = toneFor(percentUsed);
  if (tone === "danger") return "text-signal-danger";
  if (tone === "warn") return "text-signal-warn";
  return "text-ink-strong";
}

function UsageBar({ value }: { value: number }) {
  const clamped = Math.max(0, Math.min(100, value));
  return (
    <div className="h-[7px] overflow-hidden rounded-[2px] border border-[rgba(255,255,255,.08)] bg-[repeating-linear-gradient(90deg,transparent_0,transparent_9px,rgba(255,255,255,.08)_10px),rgba(255,255,255,.035)] shadow-[inset_0_1px_2px_rgba(0,0,0,.55)]">
      <div className={fillClassName(clamped)} style={{ width: `${clamped}%` }} />
    </div>
  );
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
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3" {...waitingAttrs()}>
        <span className="text-xs uppercase tracking-caps text-ink-strong">grok</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </article>
    );
  }

  if (state.status === "failure") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3" {...failureAttrs(state.failure, state.checkedAt, state.completedAcquisitions)}>
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">
          grok <StatusDot tone="danger" />
        </span>
        <span className="text-sm text-ink-muted">{failureCopy(state.failure)}</span>
        {state.pending && <span className="text-right text-xxs text-ink-muted">updating...</span>}
      </article>
    );
  }

  const { data } = state;
  const creditsWindow = data.windows.find((w) => w.id === "credits");
  const displayPrimary = creditsWindow ?? data.windows[0];
  const productWindows = data.windows.filter((w) => w !== displayPrimary).sort((a, b) => b.percentUsed - a.percentUsed);
  const secondary = productWindows[0];
  const resetInfo = formatReset(displayPrimary?.resetAt);

  return (
    <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3" {...successAttrs(data, state.checkedAt, state.warning, state.completedAcquisitions)}>
      <div className="min-w-0">
        <div className="truncate text-xs uppercase tracking-caps text-ink-strong">grok</div>
        <div className="mt-1 flex items-center gap-1.5 text-xxs text-ink-label">
          <Badge tone="neutral">{periodLabel(data.period.type)}</Badge>
          {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
        </div>
      </div>

      <div className="flex min-w-0 flex-col gap-1.5">
        {displayPrimary ? (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{displayPrimary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{resetInfo ? resetInfo.relative : "active"}</span>
            </div>
            <UsageBar value={displayPrimary.percentUsed} />
          </div>
        ) : (
          <span className="text-sm text-ink-muted">no metered usage reported</span>
        )}
        {secondary && (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{secondary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{secondary.resetAt ? "same reset" : "active"}</span>
            </div>
            <UsageBar value={secondary.percentUsed} />
          </div>
        )}
        {data.credits && <span className="text-xxs text-ink-muted">prepaid credits {data.credits.remaining}</span>}
      </div>

      <div className="min-w-0 text-right">
        <strong className={`flex justify-end font-mono text-2xl font-normal leading-none tracking-value ${displayPrimary ? remainingClassName(displayPrimary.percentUsed) : "text-ink-strong"}`}>
          {displayPrimary ? Math.round(displayPrimary.percentRemaining) : "--"}
          {displayPrimary && <span className="ml-0.5 mt-0.5 text-xs opacity-45">%</span>}
        </strong>
        <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-label">{displayPrimary?.label === "Grok Build" ? "build left" : "left"}</span>
      </div>
    </article>
  );
}
