import { Badge, StatusDot } from "@babymenu/ui";
import type { CursorQuotaWindow } from "./store";
import { fillClassName, formatPercent, formatReset, percentLeft, remainingClassName, useCursorQuota } from "./store";

function UsageBar({ value }: { value: number }) {
  const clamped = Math.max(0, Math.min(100, value));
  return (
    <div className="h-[7px] overflow-hidden rounded-[2px] border border-[rgba(255,255,255,.08)] bg-[repeating-linear-gradient(90deg,transparent_0,transparent_9px,rgba(255,255,255,.08)_10px),rgba(255,255,255,.035)] shadow-[inset_0_1px_2px_rgba(0,0,0,.55)]">
      <div className={fillClassName(clamped)} style={{ width: `${clamped}%` }} />
    </div>
  );
}

function UsageWindowRow({ window }: { window: CursorQuotaWindow }) {
  return (
    <div>
      <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
        <span className="truncate">{window.label}</span>
        <span className="whitespace-nowrap text-ink-label">{formatPercent(window.percentUsed)}% used</span>
      </div>
      <UsageBar value={window.percentUsed} />
    </div>
  );
}

export function CursorQuotaView() {
  const state = useCursorQuota();

  if (state.status === "loading") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="text-xs uppercase tracking-caps text-ink-strong">cursor</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </article>
    );
  }

  if (state.status === "error") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">
          cursor <StatusDot tone="danger" />
        </span>
        <span className="text-sm text-ink-muted">{state.error}</span>
        {state.pending && <span className="text-right text-xxs text-ink-muted">updating...</span>}
      </article>
    );
  }

  const { data } = state;
  const includedWindow = data.windows.find((window) => window.id === "included_usage");
  const includedLeft = percentLeft(includedWindow);
  const resetText = formatReset(includedWindow?.resetAt);

  return (
    <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
      <div className="min-w-0">
        <div className="truncate text-xs uppercase tracking-caps text-ink-strong">cursor</div>
        <div className="mt-1 flex flex-wrap items-center gap-1.5 text-xxs text-ink-label">
          {data.plan && <Badge tone="neutral">{data.plan}</Badge>}
          <span className="flex items-center gap-1">
            {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
            {data.stale ? "stale" : "live"}
          </span>
        </div>
      </div>

      <div className="flex min-w-0 flex-col gap-1.5">
        {data.windows.length > 0 ? (
          data.windows.map((window) => <UsageWindowRow key={window.id} window={window} />)
        ) : (
          <span className="text-sm text-ink-muted">no quota windows reported</span>
        )}
        <div className="flex min-w-0 justify-between gap-2 text-xxs text-ink-label">
          <span className="truncate">{data.status ?? "monthly quota"}</span>
          <span className="whitespace-nowrap">{resetText ?? "active"}</span>
        </div>
      </div>

      <div className="min-w-0 text-right">
        <strong className={`flex justify-end font-mono text-2xl font-normal leading-none tracking-value ${includedWindow ? remainingClassName(includedWindow.percentUsed) : "text-ink-strong"}`}>
          {includedLeft === null ? "--" : formatPercent(includedLeft)}
          {includedLeft !== null && <span className="ml-0.5 mt-0.5 text-xs opacity-45">%</span>}
        </strong>
        <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-label">left</span>
        {state.pending && <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-muted">updating</span>}
      </div>
    </article>
  );
}
