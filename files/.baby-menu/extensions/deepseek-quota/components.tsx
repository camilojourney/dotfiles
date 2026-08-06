import { Badge, StatusDot } from "@babymenu/ui";
import { useDeepseekQuota } from "./store";

const RADIUS = 15.9155;

function toneClass(tone: "live" | "warn" | "danger") {
  if (tone === "danger") return "text-signal-danger";
  if (tone === "warn") return "text-signal-warn";
  return "text-signal-live";
}

function toneForBalance(amount: number) {
  if (amount <= 0) return "danger" as const;
  if (amount < 5) return "warn" as const;
  return "live" as const;
}

function formatUsd(amount: number, currency: string) {
  const symbol = currency === "USD" ? "$" : `${currency} `;
  return `${symbol}${amount.toFixed(2)}`;
}

function ValueRing({ text, size, tone }: { text: string; size: number; tone: "live" | "warn" | "danger" }) {
  const fontSize = size >= 80 ? "text-lg" : "text-xs";
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg viewBox="0 0 36 36" style={{ width: size, height: size }}>
        <circle cx="18" cy="18" r={RADIUS} fill="none" stroke="currentColor" strokeWidth="3" className={`${toneClass(tone)} opacity-70`} />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center px-1">
        <span className={`${fontSize} font-light tracking-value text-ink-strong text-center leading-none`}>{text}</span>
      </div>
    </div>
  );
}

export function DeepseekQuotaView() {
  const state = useDeepseekQuota();

  if (state.status === "loading") {
    return (
      <div className="flex flex-col gap-2">
        <span className="text-xxs uppercase tracking-caps text-ink-label">deepseek</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </div>
    );
  }

  if (state.status === "error") {
    return (
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
          <span>deepseek</span>
          <StatusDot tone="danger" />
        </div>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </div>
    );
  }

  const { data } = state;
  const primary = data.balances[0];

  if (!primary) {
    return (
      <div className="flex flex-col gap-2">
        <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
          <span>deepseek</span>
          <StatusDot tone="warn" />
        </div>
        <span className="text-sm text-ink-muted">no balance reported</span>
      </div>
    );
  }

  const totalTone = toneForBalance(primary.totalBalance);

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between text-xxs uppercase tracking-caps text-ink-label">
        <span>deepseek</span>
        <span className="flex items-center gap-1.5">
          {!data.available && <Badge tone="danger">unavailable</Badge>}
          {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
        </span>
      </div>

      <div className="flex items-center gap-4">
        <ValueRing text={formatUsd(primary.totalBalance, primary.currency)} size={88} tone={totalTone} />
        <div className="flex flex-col gap-1">
          <span className="text-xxs uppercase tracking-caps text-ink-label">balance</span>
          <span className="text-xs text-ink-muted">available to spend</span>
        </div>
        <div className="ml-auto flex flex-col items-center gap-1.5">
          <ValueRing text={formatUsd(primary.toppedUpBalance, primary.currency)} size={56} tone="live" />
          <span className="text-xxs uppercase tracking-caps text-ink-label">topped up</span>
        </div>
      </div>

      {primary.grantedBalance > 0 && (
        <div className="flex items-center justify-between text-xs text-ink-muted">
          <span>granted (free)</span>
          <span className="tracking-value text-ink-strong">{formatUsd(primary.grantedBalance, primary.currency)}</span>
        </div>
      )}
    </div>
  );
}
