import { Badge, StatusDot } from "@babymenu/ui";
import { useClaudeQuota } from "./store";

const RADIUS = 15.9155;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

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

function formatReset(resetAt?: string, resetText?: string): string | undefined {
  if (resetText) return resetText;
  if (!resetAt) return undefined;
  const date = new Date(resetAt);
  if (Number.isNaN(date.getTime())) return undefined;
  return `resets ${date.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" })}`;
}

export function ClaudeQuotaView() {
  const state = useClaudeQuota();

  if (state.status === "loading") {
    return (
      <div className="flex flex-col gap-2">
        <span className="text-xxs uppercase tracking-caps text-ink-label">claude code</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </div>
    );
  }

  if (state.status === "error") {
    return (
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
          <span>claude code</span>
          <StatusDot tone="danger" />
        </div>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </div>
    );
  }

  const { data } = state;
  const percentWindows = data.windows.filter((w) => typeof w.percentUsed === "number");
  const primary = percentWindows.find((w) => w.id === "seven_day") ?? percentWindows.find((w) => w.id === "five_hour") ?? percentWindows[0];
  const remaining = percentWindows.filter((w) => w !== primary);
  const secondary = remaining.find((w) => w.id === "five_hour") ?? remaining[0];
  const rest = remaining.filter((w) => w !== secondary);
  const extra = data.windows.find((w) => w.id === "extra_usage");

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
        <span>claude code</span>
        <span className="flex items-center gap-1.5">
          {data.plan && <Badge tone="neutral">{data.plan}</Badge>}
          {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
        </span>
      </div>

      <div className="flex items-center gap-4">
        {primary && typeof primary.percentUsed === "number" && (
          <RadialGauge value={primary.percentUsed} size={88} />
        )}
        {primary && (
          <div className="flex flex-col gap-1">
            <span className="text-xxs uppercase tracking-caps text-ink-label">{primary.label} used</span>
            {formatReset(primary.resetAt, primary.resetText) && (
              <span className="text-xs text-ink-muted">{formatReset(primary.resetAt, primary.resetText)}</span>
            )}
          </div>
        )}
        {secondary && typeof secondary.percentUsed === "number" && (
          <div className="ml-auto flex flex-col items-center gap-1.5">
            <RadialGauge value={secondary.percentUsed} size={56} />
            <span className="text-xxs uppercase tracking-caps text-ink-label">{secondary.label}</span>
          </div>
        )}
      </div>

      {rest.length > 0 && (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-line-faint pt-2 text-xs text-ink-muted">
          {rest.map((w) => (
            <span key={w.id}>
              {w.label} <span className="tracking-value text-ink-strong">{Math.round(w.percentUsed ?? 0)}%</span>
            </span>
          ))}
        </div>
      )}

      {extra && (
        <div className="flex items-center justify-between text-xs text-ink-muted">
          <span>extra usage</span>
          <span className="tracking-value text-ink-strong">
            ${extra.spentUsd?.toFixed(2)} / ${extra.limitUsd?.toFixed(2)}
          </span>
        </div>
      )}
    </div>
  );
}
