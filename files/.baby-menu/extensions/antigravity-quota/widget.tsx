import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { AntigravityQuotaView } from "./components";
import { fetchAntigravityQuota } from "./store";

export const antigravityQuotaWidget: RefreshableBabyMenuWidget = {
  id: "antigravity-quota",
  title: "ANTIGRAVITY",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchAntigravityQuota(),
  render: () => <AntigravityQuotaView />,
};
