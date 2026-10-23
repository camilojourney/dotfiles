import { QuotaRow } from "./shared/quota-components";
import { TEXT_STYLES } from "./shared/ui-styles";
import { useMuseQuota } from "./store";

export function MuseQuotaView() {
  const { signedIn, message } = useMuseQuota();
  return (
    <QuotaRow name="muse" tone={signedIn ? "warn" : "muted"} hint={signedIn ? "signed in" : "pi"}>
      <span className={TEXT_STYLES.content}>{message}</span>
    </QuotaRow>
  );
}
