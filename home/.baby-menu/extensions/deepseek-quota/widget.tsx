import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { DeepseekQuotaView } from "./components";
import { fetchDeepseekQuota } from "./store";

export const deepseekQuotaWidget: RefreshableBabyMenuWidget = {
  id: "deepseek-quota",
  title: "DEEPSEEK",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchDeepseekQuota(),
  render: () => <DeepseekQuotaView />,
};
