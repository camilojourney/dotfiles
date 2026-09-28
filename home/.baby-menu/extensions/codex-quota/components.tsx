import { Badge, StatusDot } from "@babymenu/ui";
import { useCodexQuota } from "./store";

function toneFor(percentUsed: number) {
  if (percentUsed >= 90) return "danger" as const;
  if (percentUsed >= 70) return "warn" as const;
  return "live" as const;
}

function formatReset(resetAt?: string): string | undefined {
  if (!resetAt) return undefined;
  const date = new Date(resetAt);
  if (Number.isNaN(date.getTime())) return undefined;
  return `resets ${date.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" })}`;
}

function fillClassName(percentUsed: number) {
  const tone = toneFor(percentUsed);
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

export function CodexQuotaView() {
  const state = useCodexQuota();

  if (state.status === "loading") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="text-xs uppercase tracking-caps text-ink-strong">codex</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </article>
    );
  }

  if (state.status === "error") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">codex <StatusDot tone="danger" /></span>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </article>
    );
  }

  const { data } = state;
  const percentWindows = data.windows.filter((w) => typeof w.percentUsed === "number");
  const primary = percentWindows.find((w) => w.id === "weekly") ?? percentWindows.find((w) => w.id === "five_hour") ?? percentWindows[0];
  const remaining = percentWindows.filter((w) => w !== primary);
  const secondary = remaining.find((w) => w.id === "five_hour") ?? remaining.find((w) => w.id === "spark_weekly") ?? remaining[0];
  const hasCredits = Boolean(data.credits && (data.credits.hasCredits || data.credits.unlimited));
  const creditsText = data.credits?.unlimited
    ? "unlimited"
    : typeof data.credits?.balance === "number"
      ? `$${data.credits.balance.toFixed(2)}`
      : undefined;
  const remainingPercent = primary?.percentUsed === undefined ? null : Math.max(0, 100 - primary.percentUsed);

  return (
    <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
      <div className="min-w-0">
        <div className="truncate text-xs uppercase tracking-caps text-ink-strong">codex</div>
        <div className="mt-1 flex items-center gap-1.5 text-xxs text-ink-label">
          {data.plan && <Badge tone="neutral">{data.plan}</Badge>}
          {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
        </div>
      </div>

      <div className="flex min-w-0 flex-col gap-1.5">
        {primary && typeof primary.percentUsed === "number" && (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{primary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{formatReset(primary.resetAt) ?? primary.resetText ?? "active"}</span>
            </div>
            <UsageBar value={primary.percentUsed} />
          </div>
        )}
        {secondary && typeof secondary.percentUsed === "number" && (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{secondary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{formatReset(secondary.resetAt) ?? secondary.resetText ?? "active"}</span>
            </div>
            <UsageBar value={secondary.percentUsed} />
          </div>
        )}
        {!primary && hasCredits && creditsText && <span className="text-xs text-ink-muted">credits {creditsText}</span>}
      </div>

      <div className="min-w-0 text-right">
        {remainingPercent === null ? (
          <strong className="font-mono text-lg font-normal tracking-value text-ink-strong">{creditsText ?? "--"}</strong>
        ) : (
          <strong className={`flex justify-end font-mono text-2xl font-normal leading-none tracking-value ${remainingClassName(primary.percentUsed!)}`}>
            {Math.round(remainingPercent)}
            <span className="ml-0.5 mt-0.5 text-xs opacity-45">%</span>
          </strong>
        )}
        <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-label">left</span>
      </div>
    </article>
  );
}
