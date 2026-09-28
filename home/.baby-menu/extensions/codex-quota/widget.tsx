import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { CodexQuotaView } from "./components";
import { fetchCodexQuota } from "./store";

export const codexQuotaWidget: RefreshableBabyMenuWidget = {
  id: "codex-quota",
  title: "CODEX",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchCodexQuota(),
  render: () => <CodexQuotaView />,
};
