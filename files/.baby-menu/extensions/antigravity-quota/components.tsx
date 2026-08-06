import { Badge, StatusDot } from "@babymenu/ui";
import { useAntigravityQuota } from "./store";

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

export function AntigravityQuotaView() {
  const state = useAntigravityQuota();

  if (state.status === "loading") {
    return (
      <div className="flex flex-col gap-2">
        <span className="text-xxs uppercase tracking-caps text-ink-label">antigravity</span>
        <span className="text-sm text-ink-muted">opening model quota...</span>
      </div>
    );
  }

  if (state.status === "error") {
    return (
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
          <span>antigravity</span>
          <StatusDot tone="danger" />
        </div>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </div>
    );
  }

  const { data } = state;
  const primary = data.buckets.find((bucket) => bucket.id === "gemini") ?? data.buckets[0];
  const secondary = data.buckets.find((bucket) => bucket.id === "claude-gpt");

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
        <span>antigravity</span>
        <span className="flex items-center gap-1.5">
          {data.plan && <Badge tone="neutral">{data.plan}</Badge>}
          <StatusDot tone="live" />
        </span>
      </div>

      <div className="flex items-center gap-4">
        {primary && <RadialGauge value={primary.percentUsed} size={88} />}
        {primary && (
          <div className="flex min-w-0 flex-col gap-1">
            <span className="text-xxs uppercase tracking-caps text-ink-label">{primary.label}</span>
            <span className="text-xs uppercase tracking-caps text-ink-strong">weekly limit used</span>
            <span className="text-xs tracking-value text-ink-strong">{Math.round(primary.percentRemaining)}% left</span>
            <span className="text-xs text-ink-muted">{primary.refreshesIn ? `refreshes in ${primary.refreshesIn}` : "refresh time not shown"}</span>
          </div>
        )}
        {secondary && (
          <div className="ml-auto flex flex-col items-center gap-1.5">
            <RadialGauge value={secondary.percentUsed} size={56} />
            <span className="text-xxs uppercase tracking-caps text-ink-label">claude + gpt</span>
            <span className="text-xxs uppercase tracking-caps text-ink-strong">weekly limit</span>
            <span className="text-xxs tracking-value text-ink-muted">{Math.round(secondary.percentRemaining)}% left</span>
          </div>
        )}
      </div>

      <div className="flex items-center justify-between border-t border-line-faint pt-2 text-xs text-ink-muted">
        <span>tab completions</span>
        <Badge tone="neutral">unlimited</Badge>
      </div>
    </div>
  );
}
