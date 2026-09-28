import { Badge, StatusDot } from "@babymenu/ui";
import { useClaudeQuota } from "./store";

function toneFor(percentUsed: number) {
  if (percentUsed >= 90) return "danger" as const;
  if (percentUsed >= 70) return "warn" as const;
  return "live" as const;
}

function formatReset(resetAt?: string, resetText?: string): string | undefined {
  if (resetText) return resetText;
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

export function ClaudeQuotaView() {
  const state = useClaudeQuota();

  if (state.status === "loading") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="text-xs uppercase tracking-caps text-ink-strong">claude</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </article>
    );
  }

  if (state.status === "error") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">claude <StatusDot tone="danger" /></span>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </article>
    );
  }

  const { data } = state;
  const percentWindows = data.windows.filter((w) => typeof w.percentUsed === "number");
  const primary = percentWindows.find((w) => w.id === "seven_day") ?? percentWindows.find((w) => w.id === "five_hour") ?? percentWindows[0];
  const remaining = percentWindows.filter((w) => w !== primary);
  const secondary = remaining.find((w) => w.id === "five_hour") ?? remaining[0];
  const extra = data.windows.find((w) => w.id === "extra_usage");
  const remainingPercent = primary?.percentUsed === undefined ? null : Math.max(0, 100 - primary.percentUsed);

  return (
    <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
      <div className="min-w-0">
        <div className="truncate text-xs uppercase tracking-caps text-ink-strong">claude</div>
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
              <span className="whitespace-nowrap text-ink-label">{formatReset(primary.resetAt, primary.resetText) ?? "active"}</span>
            </div>
            <UsageBar value={primary.percentUsed} />
          </div>
        )}
        {secondary && typeof secondary.percentUsed === "number" && (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{secondary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{formatReset(secondary.resetAt, secondary.resetText) ?? "active"}</span>
            </div>
            <UsageBar value={secondary.percentUsed} />
          </div>
        )}
        {!primary && extra && <span className="text-xs text-ink-muted">extra usage ${extra.spentUsd?.toFixed(2)} / ${extra.limitUsd?.toFixed(2)}</span>}
      </div>

      <div className="min-w-0 text-right">
        <strong className={`flex justify-end font-mono text-2xl font-normal leading-none tracking-value ${primary ? remainingClassName(primary.percentUsed ?? 0) : "text-ink-strong"}`}>
          {remainingPercent === null ? "--" : Math.round(remainingPercent)}
          {remainingPercent !== null && <span className="ml-0.5 mt-0.5 text-xs opacity-45">%</span>}
        </strong>
        <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-label">{primary?.id === "seven_day" ? "weekly left" : "left"}</span>
      </div>
    </article>
  );
}
