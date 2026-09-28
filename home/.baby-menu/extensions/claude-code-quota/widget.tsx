import type { RefreshableBabyMenuWidget } from "@babymenu/contracts";
import { ClaudeQuotaView } from "./components";
import { fetchClaudeQuota } from "./store";

export const claudeCodeQuotaWidget: RefreshableBabyMenuWidget = {
  id: "claude-code-quota",
  title: "CLAUDE CODE",
  viewRefreshIntervalMs: 300_000,
  refreshView: () => fetchClaudeQuota(),
  render: () => <ClaudeQuotaView />,
};
