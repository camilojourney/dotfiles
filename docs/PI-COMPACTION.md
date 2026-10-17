# Pi compaction per model

## Current position

Configuration lives in [`home/.pi/agent/settings.json`](../home/.pi/agent/settings.json),
linked as `~/.pi/agent/settings.json`. These are **provisional operating settings,
not measured optimal thresholds**. They control context size, not subscription
quota limits. No new summarizer or pruning extension has been installed for this
experiment.

| Model/provider | Configured window | `reserveTokens` | Pi threshold | Compaction mechanism |
|---|---|---|---|---|
| `openai-codex/gpt-6.1-sol` | 500K | 225000 | 275K | Existing OpenAI server-side compaction extension, with fallback |
| Listed 1M `claude-bridge` models | 1M | 600000 | 400K | Pi text-summary compaction using the active model |
| Gemini and Grok | Check current catalog | Default 16384 | Window minus 16384 | Pi text-summary compaction unless another extension overrides it |
| Other models | Check current catalog | Default 16384 | Window minus 16384 | Depends on provider and installed extensions |

The nine Claude overrides cover Fable 5 and 5.1, Haiku 5.5, Opus 4.7, 4.8, 5
and 5.5, and Sonnet 5 and 5.5. They do not apply automatically to future models.
At the default reserve, a 272K model triggers near 256K and a 200K model near
184K. Extension behavior and failures can affect the actual compaction path.

### When versus how

- **When:** Pi checks whether context exceeds `window - reserveTokens`.
  Therefore `reserveTokens = window - desired threshold`. A large tool result
  or a model switch can put the context past the threshold before the check.
- **How:** the installed `pi-openai-server-compaction` extension handles
  supported OpenAI/Codex models only. Installing it globally does **not** make
  it compact Claude, Gemini or Grok conversations through GPT.
- OpenAI's opaque native compaction artifacts are not portable to other model
  providers. GPT can instead write a **plain-text summary** that other models
  can read, but that is a different mechanism requiring additional integration.
- Pi reads settings at startup or `/reload`. A running process can retain its
  old threshold. Reload or restart before testing new settings.
- The footer shows the full model window, not the threshold. `(auto)` means
  automatic compaction is enabled. With these settings Claude reaches its Pi
  threshold around 40% of `1.0M`, and GPT-6.1 Sol around 55% of `500K`.

## Initial recommendations

1. **Keep the existing compaction mechanisms as the baseline.** Do not route
   every model through GPT or install several compaction extensions at once.
2. **Use FirstMate's existing durable files for continuity.** Keep the current
   goal, user constraints, decisions and rejected approaches, changed file
   paths, test results, blockers and next actions current. Avoid another memory
   system unless the existing files expose a concrete gap.
3. **Keep the 400K Claude and 275K GPT settings provisional.** Leave Gemini and
   Grok at their defaults until their actual runs are measured. Family names and
   advertised windows do not establish the best threshold.
4. **Test a dedicated summarizer before adopting one.** Compare the active
   model's text summary with a GPT-generated text summary. A stronger or more
   expensive summarizer is not automatically better at preserving task state.
5. **If tool-output clutter remains a problem, test batched pruning.** Preserve
   original outputs for retrieval, and prune at meaningful task boundaries,
   not every turn. Rewriting earlier context can invalidate prompt caches and
   increase total cost despite reducing context size. Test bridge compatibility.

These recommendations apply to Pi, including FirstMate sessions actually using
Pi. They do not configure standalone Claude Code or other harnesses.

## Evidence so far and its limits

An inspection of local Pi history found 553 compactions across 1,843 sessions
with recorded usage. Most were GPT runs. One FirstMate session recorded 70
compactions over about 189 hours. That demonstrates repeated continuation, not
that task quality was preserved or that its threshold was optimal.

A FirstMate session switching from GPT-6.1 Sol to Opus 5.5 through claude-bridge
provided these historical observations:

| Observation | GPT-6.1 Sol | Opus 5.5 through claude-bridge |
|---|---|---|
| Context reported around the model switch | ~202K | ~338K |
| Context on the next response after sampled compactions | ~31-35K | ~105-130K |
| Sampled compaction entries | 498828, then 278294 tokens before | 339005, then 275518 tokens before |

The larger first Claude compaction followed a switch into an already-large
conversation. The later 275518 event showed the running process still used the
previous 275K policy. **Neither event verifies the new 400K trigger in a live
run.** Confirm it after a reload with a new compaction entry.

The observed differences combine tokenization, prompt and tool wrapping,
reasoning representation, retained messages, FirstMate context injection and
provider accounting. The measurements do **not** isolate a tokenizer ratio or
prove that Claude intrinsically needs 1.6-1.9 times the context. Nor do they
establish a specific quota multiplier or a universal post-compaction floor.

The OpenAI extension reports better exact recall than Pi's default compactor
in its own benchmark, but also retained more tokens. That is not a controlled
comparison against Opus in FirstMate and does not establish that each Claude
compaction loses more. The choice of 400K was a working hypothesis to reduce
compaction frequency given the observed higher restart context, not a proven
quality improvement.

## Future checks: choose a compactor, then a threshold

Use copied sessions and disposable worktrees, not live FirstMate jobs. Start
with a few representative tasks: multi-file implementation, debugging with
rejected hypotheses, and a long run with changing requirements. Include several
successive compactions to detect accumulated loss.

### 1. Verify the baseline

- Record the exact working model, provider, Pi version, extension versions,
  project overrides, effective window, threshold and recent-message retention.
- Reload settings and inspect the next real compaction. Record tokens before,
  the actual handler used, failures/fallbacks, summary size and next-response
  context. Check that Claude's configured 400K threshold is actually active.
- Separate fixed prompt/tool overhead from conversation growth and avoid
  comparing providers' raw token counts as if they represented identical text.
- Check whether the current model's compaction request can fit in a proposed
  summarizer's input window, including its instructions and output headroom.

### 2. Compare mechanisms without changing thresholds

Replay the same saved conversation and unfinished task for each candidate.
Keep recent-message retention and comparable downstream context budgets fixed;
report unequal budgets rather than attributing their benefit to the mechanism.

| Working model | Candidates |
|---|---|
| GPT | Existing OpenAI native compaction versus Pi text summary |
| Claude | Active Claude text summary versus GPT-generated text summary |
| Gemini | Active Gemini text summary versus GPT-generated text summary |
| Grok | Active Grok text summary versus GPT-generated text summary |

Use the same working model to continue after each candidate summary. Keep the
summary format and instructions fixed when comparing text summarizer models.
Repeat cases because summaries and subsequent actions vary between runs.

A candidate integration is
[`pi-compaction-model`](https://github.com/JMHSV/pi-compaction-model), which
routes Pi's compaction algorithm through a dedicated model and falls back to
the active model on failure. Before adopting it, test authentication, context
capacity, cancellation and fallback. Its hook can conflict with the existing
OpenAI extension: ensure only one handler owns each compaction path.

### 3. Test thresholds separately

After selecting a mechanism, compare the current threshold with one lower and
one higher setting, within the verified model window. For Claude 1M models,
350K / 400K / 450K are candidate trials, not recommendations established by
research. Establish Gemini/Grok baselines before selecting their trial values.
Do not change summarizer, trigger and pruning policy in the same comparison.

### 4. Score continuation, not just compression

- Required constraints, facts, decisions and file changes retained.
- Correct task completion, tests passed and instruction adherence.
- Forgotten fixes, repeated investigation and incorrect claims of completion.
- Total tokens across summary generation, continuation and recovery work;
  cache hits/writes, latency, compaction frequency and observed quota use.
- Errors, silent fallbacks and reliability across multiple compaction cycles.

Where possible use checkable requirements and tests rather than only an LLM
judge. Prefer the lowest-overhead candidate that preserves task quality across
representative cases; do not pick the smallest summary. If results are mixed,
keep the baseline. Record the exact model/provider and workload tested, not a
blanket claim that GPT, Claude, Gemini or Grok is best at compaction.

## Inspecting actual sessions

Pi appends history under `~/.pi/agent/sessions/<project-dir>/<session>.jsonl`.
These records can contain private prompts and tool output; keep evaluations
local or redact examples before sharing.

List compaction events:

```sh
jq -r 'select(.type == "compaction") | [.timestamp, .tokensBefore] | @tsv' \
  "$SESSION_FILE"
```

List assistant responses with provider-reported input context, excluding output
and `totalTokens` so output is not counted as input:

```sh
jq -r 'select(.type == "message" and .message.role == "assistant") |
  [.timestamp, .message.provider, .message.model,
   ((.message.usage.input // 0) + (.message.usage.cacheRead // 0) +
    (.message.usage.cacheWrite // 0))] | @tsv' "$SESSION_FILE"
```

Correlate the compaction entry with the preceding active model and following
response. Missing usage is not proof of zero context. `fromHook` alone does not
prove an automatic trigger or identify the summarizer; inspect extension
metadata/logs for the actual handler and reason.

## Maintenance

- Overrides match exact `provider/modelId` values; there are no wildcards. New
  models without an override use Pi defaults, not the family's trial policy.
- Check `pi --list-models <provider>` when a model or entitlement changes and
  recompute the reserve from the actual window.
- Never apply a 600000 reserve to a 200K model: the threshold becomes negative.
  Remove/recompute the override before using the bridge's `forceTwoHundredK`.
- A window change can silently move the threshold. Recheck settings when
  upgrading Pi, model catalogs or provider extensions.

## Sources and candidate tools

- [Pi compaction reference](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/compaction.md): mechanism, settings and extension hooks.
- [Anthropic: effective context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents): compaction and structured notes.
- [Anthropic: effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents): durable progress and incremental coding work.
- [JetBrains: The Complexity Trap](https://arxiv.org/abs/2508.21433): observation masking competed with summarization in its tested coding-agent setups; not a validation of current Opus in Pi.
- [Factory: evaluating context compression](https://factory.ai/news/evaluating-compression): vendor-authored evidence for structured summaries and continuation/artifact evaluation, not a universal provider ranking.
- [pi-context-prune](https://github.com/championswimmer/pi-context-prune): candidate tool-output summarization/pruning with retrieval; its README warns about cache invalidation. Not installed or validated here.
- [Existing OpenAI compaction extension](https://github.com/algal/pi-openai-server-compaction): supported providers, fallback behavior and benchmark qualifications.
