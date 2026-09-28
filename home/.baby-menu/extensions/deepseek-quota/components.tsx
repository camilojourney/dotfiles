import { Badge, StatusDot } from "@babymenu/ui";
import { useDeepseekQuota } from "./store";

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

function CreditBar({ totalBalance, toppedUpBalance }: { totalBalance: number; toppedUpBalance: number }) {
  const denominator = Math.max(totalBalance, toppedUpBalance, 1);
  const percent = Math.max(0, Math.min(100, (totalBalance / denominator) * 100));
  return (
    <div className="h-[7px] overflow-hidden rounded-[2px] border border-[rgba(255,255,255,.08)] bg-[repeating-linear-gradient(90deg,transparent_0,transparent_9px,rgba(255,255,255,.08)_10px),rgba(255,255,255,.035)] shadow-[inset_0_1px_2px_rgba(0,0,0,.55)]">
      <div className="h-full rounded-[1px] bg-signal-live shadow-[0_0_9px_rgba(106,227,182,.38)]" style={{ width: `${percent}%` }} />
    </div>
  );
}

export function DeepseekQuotaView() {
  const state = useDeepseekQuota();

  if (state.status === "loading") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="text-xs uppercase tracking-caps text-ink-strong">deepseek</span>
        <span className="text-sm text-ink-muted">checking usage...</span>
      </article>
    );
  }

  if (state.status === "error") {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">deepseek <StatusDot tone="danger" /></span>
        <span className="text-sm text-ink-muted">{state.error}</span>
      </article>
    );
  }

  const { data } = state;
  const primary = data.balances[0];

  if (!primary) {
    return (
      <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
        <span className="flex items-center gap-1.5 text-xs uppercase tracking-caps text-ink-strong">deepseek <StatusDot tone="warn" /></span>
        <span className="text-sm text-ink-muted">no balance reported</span>
      </article>
    );
  }

  const totalTone = toneForBalance(primary.totalBalance);

  return (
    <article className="grid grid-cols-[86px_minmax(0,1fr)_72px] items-center gap-3 py-3">
      <div className="min-w-0">
        <div className="truncate text-xs uppercase tracking-caps text-ink-strong">deepseek</div>
        <div className="mt-1 flex items-center gap-1.5 text-xxs text-ink-label">
          {!data.available && <Badge tone="danger">unavailable</Badge>}
          {data.stale ? <StatusDot tone="warn" /> : <StatusDot tone="live" />}
        </div>
      </div>

      <div className="flex min-w-0 flex-col gap-1.5">
        <div>
          <div className="mb-1 flex justify-between gap-2 text-xxs text-ink-soft">
            <span className="truncate">credit balance</span>
            <span className="whitespace-nowrap text-ink-label">no scheduled reset</span>
          </div>
          <CreditBar totalBalance={primary.totalBalance} toppedUpBalance={primary.toppedUpBalance} />
        </div>
        {primary.grantedBalance > 0 && (
          <span className="text-xxs text-ink-muted">granted {formatUsd(primary.grantedBalance, primary.currency)}</span>
        )}
      </div>

      <div className="min-w-0 text-right">
        <strong className={`font-mono text-xl font-normal leading-none tracking-value ${toneClass(totalTone)}`}>
          {formatUsd(primary.totalBalance, primary.currency)}
        </strong>
        <span className="mt-1 block text-[9px] uppercase tracking-caps text-ink-label">left</span>
      </div>
    </article>
  );
}
