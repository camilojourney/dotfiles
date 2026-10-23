import { QuotaRow, QuotaValue, QuotaWindowRow } from "./shared/quota-components";
import { formatQuotaReset } from "./shared/quota-format";
import { TEXT_STYLES, quotaTone } from "./shared/ui-styles";
import { useCodexQuota } from "./store";

export function CodexQuotaView() {
  const state = useCodexQuota();
  if (state.status !== "ready") {
    return (
      <QuotaRow name="codex" tone={state.status === "error" ? "danger" : "muted"}>
        <span className={TEXT_STYLES.content}>{state.status === "error" ? state.error : "checking usage..."}</span>
      </QuotaRow>
    );
  }

  const { data } = state;
  const primary = data.windows.find((window) => window.id === "weekly") ?? data.windows[0];
  const displayed = primary ? [primary, ...data.windows.filter((window) => window !== primary)].slice(0, 2) : [];
  return (
    <QuotaRow name="codex" plan={data.plan} tone={data.stale ? "warn" : "live"} hint={data.stale ? "cached" : undefined}>
      {displayed.map((window) => {
        const remaining = Math.max(0, 100 - window.percentUsed);
        return (
          <QuotaWindowRow key={window.id} label={window.id === "weekly" ? "weekly" : window.label} reset={formatQuotaReset(window.resetAt)} remaining={remaining}>
            {window === primary && <QuotaValue value={Math.round(remaining)} unit="%" tone={quotaTone(remaining)} />}
          </QuotaWindowRow>
        );
      })}
    </QuotaRow>
  );
}
