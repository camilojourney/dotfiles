import { useSystemUsage } from "./store";

const RADIUS = 15.9155;
const CIRCUMFERENCE = 2 * Math.PI * RADIUS;

function toneFor(value: number | null, warnAt: number, dangerAt: number) {
  if (value === null) return "live" as const;
  if (value >= dangerAt) return "danger" as const;
  if (value >= warnAt) return "warn" as const;
  return "live" as const;
}

function toneClass(tone: "live" | "warn" | "danger") {
  if (tone === "danger") return "text-signal-danger";
  if (tone === "warn") return "text-signal-warn";
  return "text-signal-live";
}

function RadialGauge({ value, tone, size = 88 }: { value: number | null; tone: "live" | "warn" | "danger"; size?: number }) {
  const clamped = value === null ? 0 : Math.max(0, Math.min(100, value));
  const dash = (clamped / 100) * CIRCUMFERENCE;

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
        <span className="text-lg font-light tracking-value text-ink-strong">{value === null ? "--" : Math.round(value)}</span>
        {value !== null && <span className="ml-0.5 mt-2 text-xs text-ink-soft">%</span>}
      </div>
    </div>
  );
}

function Metric({ label, value, warnAt, dangerAt }: { label: string; value: number | null; warnAt: number; dangerAt: number }) {
  const tone = toneFor(value, warnAt, dangerAt);
  return (
    <div className="flex flex-1 flex-col items-center gap-2">
      <RadialGauge value={value} tone={tone} />
      <span className="text-xxs uppercase tracking-caps text-ink-label">{label}</span>
    </div>
  );
}

export function SystemUsageView() {
  const { cpuPercent, memoryPercent } = useSystemUsage();

  return (
    <div className="flex flex-col gap-3">
      <span className="text-xxs uppercase tracking-caps text-ink-label">system</span>
      <div className="flex items-start justify-around gap-3">
        <Metric label="cpu" value={cpuPercent} warnAt={60} dangerAt={85} />
        <Metric label="memory" value={memoryPercent} warnAt={75} dangerAt={90} />
      </div>
    </div>
  );
}
