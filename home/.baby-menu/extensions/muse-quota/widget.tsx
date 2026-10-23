import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { MuseQuotaView } from "./components";
import { fetchMuseQuota } from "./store";

export const museQuotaWidget: RefreshableBabyMenuWidget = {
  id: "muse-quota",
  title: "MUSE",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchMuseQuota(),
  render: () => <MuseQuotaView />,
};
