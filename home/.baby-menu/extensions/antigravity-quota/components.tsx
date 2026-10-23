import { QuotaRow, QuotaValue, QuotaWindowRow } from "./shared/quota-components";
import { formatQuotaReset } from "./shared/quota-format";
import { TEXT_STYLES, quotaTone } from "./shared/ui-styles";
import { limitingWindow, useAntigravityQuota, type AntigravityQuotaPool } from "./store";

function PoolRow({ pool }: { pool: AntigravityQuotaPool }) {
  const limit = limitingWindow(pool);
  const other = pool.windows.filter((window) => window !== limit).map((window) => window.kind + " " + Math.round(window.percentRemaining) + "% left");
  return (
    <QuotaWindowRow label={pool.label} reset={formatQuotaReset(limit.resetsAt)} remaining={limit.percentRemaining} note={[limit.kind, ...other].join(" · ")}>
      <QuotaValue value={Math.round(limit.percentRemaining)} unit="%" label={limit.kind + " left"} tone={quotaTone(limit.percentRemaining)} />
    </QuotaWindowRow>
  );
}

export function AntigravityQuotaView() {
  const state = useAntigravityQuota();
  const tone = state.status === "error" ? "danger" : state.status === "loading" ? "muted" : state.stale ? "warn" : "live";
  return (
    <QuotaRow name="antigrav" plan="agy" tone={tone} hint={state.status === "ready" && state.stale ? "cached" : undefined}>
      {state.status === "ready" ? (
        state.data.pools.map((pool) => <PoolRow key={pool.id} pool={pool} />)
      ) : (
        <span className={TEXT_STYLES.content}>{state.status === "error" ? state.error : "checking model quota..."}</span>
      )}
    </QuotaRow>
  );
}
