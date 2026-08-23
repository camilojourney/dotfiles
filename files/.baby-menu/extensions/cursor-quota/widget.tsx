import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { CursorQuotaView } from "./components";
import { fetchCursorQuota } from "./store";

export const cursorQuotaWidget: RefreshableBabyMenuWidget = {
  id: "cursor-quota",
  title: "CURSOR",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchCursorQuota(),
  render: () => <CursorQuotaView />,
};
