import assert from "node:assert/strict";
import test from "node:test";
import register from "../home/.pi/agent/extensions/antigravity-system-prompt.ts";

let beforeAgentStart;
register({ on(event, handler) {
  assert.equal(event, "before_agent_start");
  beforeAgentStart = handler;
} });

function start(provider, overrides = {}) {
  const systemPromptOptions = {
    contextFiles: [{ path: "AGENTS.md", content: "Project instructions" }],
    appendSystemPrompt: "Additional instructions",
    selectedTools: ["bash"],
    skills: [{ name: "example" }],
    ...overrides,
  };
  const before = structuredClone(systemPromptOptions);
  beforeAgentStart({ systemPromptOptions }, { model: provider ? { provider } : undefined });
  return { before, systemPromptOptions };
}

test("Antigravity replaces only the stock prompt configuration", () => {
  const { before, systemPromptOptions } = start("antigravity");
  assert.deepEqual(systemPromptOptions, {
    ...before,
    customPrompt: "You are a helpful assistant. Use available tools when asked.",
  });
});

test("other providers and a missing model keep the stock prompt", () => {
  for (const provider of ["openai-codex", "claude-bridge", undefined]) {
    const { before, systemPromptOptions } = start(provider);
    assert.deepEqual(systemPromptOptions, before);
  }
});

test("Antigravity keeps custom and forced prompts", () => {
  for (const options of [{ customPrompt: "Explicit" }, { customPrompt: "" }, { forceSystemPrompt: "Forced" }]) {
    const { before, systemPromptOptions } = start("antigravity", options);
    assert.deepEqual(systemPromptOptions, before);
  }
});
