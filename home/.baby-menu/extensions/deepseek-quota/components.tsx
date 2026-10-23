import { QuotaRow, QuotaValue, QuotaWindowRow } from "./shared/quota-components";
import { TEXT_STYLES } from "./shared/ui-styles";
import { useDeepseekQuota } from "./store";

function toneForBalance(amount: number) {
  if (amount <= 0) return "danger" as const;
  if (amount < 5) return "warn" as const;
  return "live" as const;
}

function formatUsd(amount: number, currency: string) {
  return (currency === "USD" ? "$" : currency + " ") + amount.toFixed(2);
}

export function DeepseekQuotaView() {
  const state = useDeepseekQuota();
  if (state.status !== "ready") {
    return (
      <QuotaRow name="deepseek" tone={state.status === "error" ? "danger" : "muted"}>
        <span className={TEXT_STYLES.content}>{state.status === "error" ? state.error : "checking usage..."}</span>
      </QuotaRow>
    );
  }

  const { data } = state;
  const primary = data.balances[0];
  if (!primary) return <QuotaRow name="deepseek" tone="warn"><span className={TEXT_STYLES.content}>no balance reported</span></QuotaRow>;
  const tone = toneForBalance(primary.totalBalance);
  const meter = Math.max(0, Math.min(100, primary.totalBalance / Math.max(primary.totalBalance, primary.toppedUpBalance, 1) * 100));
  const note = primary.grantedBalance > 0 ? "granted " + formatUsd(primary.grantedBalance, primary.currency) : undefined;

  return (
    <QuotaRow name="deepseek" tone={data.stale || !data.available ? "warn" : "live"} hint={data.stale ? "cached" : !data.available ? "unavailable" : undefined}>
      <QuotaWindowRow label="credit balance" reset="no scheduled reset" remaining={meter} tone={tone} note={note}>
        <QuotaValue value={formatUsd(primary.totalBalance, primary.currency)} tone={tone} />
      </QuotaWindowRow>
    </QuotaRow>
  );
}
