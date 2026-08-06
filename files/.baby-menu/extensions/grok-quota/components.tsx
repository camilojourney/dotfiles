import { Badge, StatusDot } from "@babymenu/ui";
import type { QuotaFailure, QuotaWindow } from "./store";
import { useGrokQuota } from "./store";

const RADIUS = 15.9155;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

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

function toneClass(tone: "live" | "warn" | "danger") {
  if (tone === "danger") return "text-signal-danger";
  if (tone === "warn") return "text-signal-warn";
  return "text-signal-live";
}

function bgToneClass(tone: "live" | "warn" | "danger") {
  if (tone === "danger") return "bg-signal-danger";
  if (tone === "warn") return "bg-signal-warn";
  return "bg-signal-live";
}

function UsageBar({ label, percentUsed }: { label: string; percentUsed: number }) {
  const clamped = Math.max(0, Math.min(100, percentUsed));
  const tone = toneFor(clamped);
  return (
    <div className="flex flex-col gap-0.5">
      <div className="flex items-center justify-between text-xs">
        <span className="text-ink-muted">{label}</span>
        <span className="tracking-value text-ink-strong">{Math.round(clamped)}%</span>
      </div>
      <div className="relative h-1 w-full overflow-hidden rounded-full bg-ink-soft/20">
        <div className={`absolute inset-y-0 left-0 rounded-full ${bgToneClass(tone)}`} style={{ width: `${clamped}%` }} />
      </div>
    </div>
  );
}

function RadialGauge({ value, size }: { value: number; size: number }) {
  const clamped = Math.max(0, Math.min(100, value));
  const dash = (clamped / 100) * CIRCUMFERENCE;
  const tone = toneFor(clamped);
  const fontSize = size >= 80 ? "text-xl" : "text-sm";

  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 36 36" className="-rotate-90" style={{ width: size, height: size }}>
        <circle cx="18" cy="18" r={RADIUS} fill="none" stroke="currentColor" strokeWidth="3" className="text-ink-soft opacity-20" />
        <circle
          cx="18"
          cy="18"
          r={RADIUS}
          fill="none"
          stroke="currentColor"
          strokeWidth="3"
          strokeLinecap="round"
          strokeDasharray={`${dash} ${CIRCUMFERENCE - dash}`}
          className={toneClass(tone)}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">
        <span className={`${fontSize} font-light tracking-value text-ink-strong`}>{Math.round(clamped)}</span>
      </div>
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
      <div className="flex flex-col gap-2" {...waitingAttrs()}>
        <span className="text-xxs uppercase tracking-caps text-ink-label">grok</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </div>
    );
  }

  if (state.status === "failure") {
    return (
      <div className="flex flex-col gap-2" {...failureAttrs(state.failure, state.checkedAt, state.completedAcquisitions)}>
        <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
          <span>grok</span>
          <span className="flex items-center gap-1.5">
            {state.pending && <span className="normal-case text-ink-muted">updating…</span>}
            <StatusDot tone="danger" />
          </span>
        </div>
        <span className="text-sm text-ink-muted">{failureCopy(state.failure)}</span>
      </div>
    );
  }

  const { data } = state;
  const creditsWindow = data.windows.find((w) => w.id === "credits");
  const displayPrimary = creditsWindow ?? data.windows[0];
  const productWindows = data.windows.filter((w) => w !== displayPrimary).sort((a, b) => b.percentUsed - a.percentUsed);
  const resetInfo = formatReset(displayPrimary?.resetAt);

  return (
    <div className="flex flex-col gap-3" {...successAttrs(data, state.checkedAt, state.warning, state.completedAcquisitions)}>
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
        <span>grok</span>
        <span className="flex items-center gap-1.5">
          {state.pending && <span className="normal-case text-ink-muted">updating…</span>}
          <Badge tone="neutral">{periodLabel(data.period.type)}</Badge>
          {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
        </span>
      </div>

      {displayPrimary ? (
        <div className="flex items-center gap-4">
          <RadialGauge value={displayPrimary.percentUsed} size={88} />
          <div className="flex min-w-0 flex-col gap-1">
            <span className="text-xxs uppercase tracking-caps text-ink-label">{displayPrimary.label} used</span>
            <span className="text-xs tracking-value text-ink-strong">{Math.round(displayPrimary.percentRemaining)}% remaining</span>
            {resetInfo && (
              <span className="text-xs text-ink-muted">
                {resetInfo.relative} <span className="text-ink-label">· {resetInfo.absolute}</span>
              </span>
            )}
          </div>
        </div>
      ) : (
        <span className="text-sm text-ink-muted">no metered usage reported for this account</span>
      )}

      {productWindows.length > 0 && (
        <div className="flex flex-col gap-2 border-t border-line-faint pt-2">
          <span className="text-xxs uppercase tracking-caps text-ink-label">product usage</span>
          {productWindows.map((w) => (
            <UsageBar key={w.id} label={w.label} percentUsed={w.percentUsed} />
          ))}
        </div>
      )}

      {data.credits && (
        <div className="flex items-center justify-between border-t border-line-faint pt-2 text-xs text-ink-muted">
          <span>prepaid credits</span>
          <span className="tracking-value text-ink-strong">{data.credits.remaining}</span>
        </div>
      )}
    </div>
  );
}
