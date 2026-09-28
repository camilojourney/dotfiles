import { Badge, StatusDot } from "@babymenu/ui";
import { useAntigravityQuota } from "./store";

function toneFor(percentUsed: number) {
  if (percentUsed >= 90) return "danger" as const;
  if (percentUsed >= 70) return "warn" as const;
  return "live" as const;
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

export function AntigravityQuotaView() {
  const state = useAntigravityQuota();

  if (state.status === "loading") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="text-xs uppercase tracking-caps text-ink-strong">antigrav</span>
        <span className="text-sm text-ink-muted">opening model quota...</span>
      </article>
    );
  }

  if (state.status === "error") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">antigrav <StatusDot tone="danger" /></span>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </article>
    );
  }

  const { data } = state;
  const primary = data.buckets.find((bucket) => bucket.id === "gemini") ?? data.buckets[0];
  const secondary = data.buckets.find((bucket) => bucket.id === "claude-gpt");
  const bestRemaining = data.buckets.length > 0 ? Math.max(...data.buckets.map((bucket) => bucket.percentRemaining)) : null;
  const bestBucket = data.buckets.find((bucket) => bucket.percentRemaining === bestRemaining) ?? primary;

  return (
    <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
      <div className="min-w-0">
        <div className="truncate text-xs uppercase tracking-caps text-ink-strong">antigrav</div>
        <div className="mt-1 flex items-center gap-1.5 text-xxs text-ink-label">
          {data.plan && <Badge tone="neutral">{data.plan}</Badge>}
          <StatusDot tone="live" />
        </div>
      </div>

      <div className="flex min-w-0 flex-col gap-1.5">
        {primary && (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{primary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{primary.refreshesIn ? `refreshes in ${primary.refreshesIn}` : "weekly refresh"}</span>
            </div>
            <UsageBar value={primary.percentUsed} />
          </div>
        )}
        {secondary && (
          <div>
            <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
              <span className="truncate">{secondary.label}</span>
              <span className="whitespace-nowrap text-ink-label">{secondary.refreshesIn ? `refreshes in ${secondary.refreshesIn}` : "weekly refresh"}</span>
            </div>
            <UsageBar value={secondary.percentUsed} />
          </div>
        )}
      </div>

      <div className="min-w-0 text-right">
        <strong className={`flex justify-end font-mono text-2xl font-normal leading-none tracking-value ${bestBucket ? remainingClassName(bestBucket.percentUsed) : "text-ink-strong"}`}>
          {bestRemaining === null ? "--" : Math.round(bestRemaining)}
          {bestRemaining !== null && <span className="ml-0.5 mt-0.5 text-xs opacity-45">%</span>}
        </strong>
        <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-label">best left</span>
      </div>
    </article>
  );
}
