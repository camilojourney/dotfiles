import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { GrokQuotaView } from "./components";
import { fetchGrokQuota } from "./store";

export const grokQuotaWidget: RefreshableBabyMenuWidget = {
  id: "grok-quota",
  title: "GROK",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchGrokQuota(),
  render: () => <GrokQuotaView />,
};
