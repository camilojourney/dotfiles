import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function antigravitySystemPrompt(pi: ExtensionAPI) {
  pi.on("before_agent_start", (event, ctx) => {
    if (ctx.model?.provider !== "antigravity") return;
    const options = event.systemPromptOptions;
    if (options.customPrompt !== undefined || options.forceSystemPrompt !== undefined) return;

    // Work around pi-antigravity #148. Let Pi render project context and skills normally.
    options.customPrompt = "You are a helpful assistant. Use available tools when asked.";
  });
}
