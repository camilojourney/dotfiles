import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { SystemUsageView } from "./components";
import { fetchSystemUsage } from "./store";

export const systemUsageWidget: RefreshableBabyMenuWidget = {
  id: "system-usage",
  title: "SYSTEM",
  viewRefreshIntervalMs: 2000,
  refreshView: () => fetchSystemUsage(),
  render: () => <SystemUsageView />,
};
