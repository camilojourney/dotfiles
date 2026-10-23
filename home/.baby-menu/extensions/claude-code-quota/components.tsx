import { QuotaRow, QuotaValue, QuotaWindowRow } from "./shared/quota-components";
import { formatQuotaReset } from "./shared/quota-format";
import { TEXT_STYLES, quotaTone } from "./shared/ui-styles";
import { useClaudeQuota } from "./store";

export function ClaudeQuotaView() {
  const state = useClaudeQuota();
  if (state.status !== "ready") {
    return (
      <QuotaRow name="claude" tone={state.status === "error" ? "danger" : "muted"}>
        <span className={TEXT_STYLES.content}>{state.status === "error" ? state.error : "checking usage..."}</span>
      </QuotaRow>
    );
  }

  const { data } = state;
  const windows = data.windows.filter((window) => typeof window.percentUsed === "number");
  const primary = windows.find((window) => window.id === "seven_day") ?? windows.find((window) => window.id === "five_hour") ?? windows[0];
  const rest = windows.filter((window) => window !== primary);
  const secondary = rest.find((window) => window.id === "five_hour") ?? rest[0];
  const displayed = [primary, secondary].filter((window): window is NonNullable<typeof window> => window !== undefined);
  const extra = data.windows.find((window) => window.id === "extra_usage");

  return (
    <QuotaRow name="claude" plan={data.plan} tone={data.stale ? "warn" : "live"} hint={data.stale ? "cached" : undefined}>
      {displayed.map((window) => {
        const remaining = Math.max(0, 100 - window.percentUsed!);
        return (
          <QuotaWindowRow key={window.id} label={window.label} reset={formatQuotaReset(window.resetAt, window.resetText)} remaining={remaining}>
            {window === primary && <QuotaValue value={Math.round(remaining)} unit="%" tone={quotaTone(remaining)} label={primary.id === "seven_day" ? "weekly left" : "left"} />}
          </QuotaWindowRow>
        );
      })}
      {!primary && extra && <span className={TEXT_STYLES.content}>extra usage {typeof extra.spentUsd === "number" ? "$" + extra.spentUsd.toFixed(2) : "reported"}</span>}
    </QuotaRow>
  );
}
