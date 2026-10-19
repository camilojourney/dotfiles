# Pi compaction per model

## Current position

Configuration lives in [`home/.pi/agent/settings.json`](../home/.pi/agent/settings.json),
linked as `~/.pi/agent/settings.json`. These are **provisional operating settings,
not measured optimal thresholds**. They control context size, not subscription
quota limits. No summarizer or pruning extension is installed for this
experiment. On 2026-10-19 `pi-anthropic-compat` and
`pi-cache-compact-preserved-messages` were each installed, reviewed and then
removed without being relied on: the first cannot activate because it requires
the direct Claude API rather than the bridge, and the second was published
anonymously with no repository and no provenance. The only compaction package
that remains declared is the pinned OpenAI one described under Maintenance.

| Model/provider | Configured window | `reserveTokens` | Pi threshold | `keepRecentTokens` | Compaction mechanism |
|---|---|---|---|---|---|
| `openai-codex/gpt-6.1-sol` | 500K | 225000 | 275K | Default 20000 | Existing OpenAI server-side compaction extension, with fallback |
| Listed 1M `claude-bridge` models | 1M | 600000 | 400K | 40000 | Pi text-summary compaction using the active model |
| Listed 1M `antigravity` models | 1.0M | 600000 | 400K | 40000 | Pi text-summary compaction using the active model |
| Grok | Not registered as a Pi provider | n/a | n/a | n/a | Its own CLI, outside Pi's compaction entirely |
| Other models | Check current catalog | Default 16384 | Window minus 16384 | Default 20000 | Depends on provider and installed extensions |

The nine Claude overrides cover Fable 5 and 5.1, Haiku 5.5, Opus 4.7, 4.8, 5
and 5.5, and Sonnet 5 and 5.5. They do not apply automatically to future models.
At the default reserve, a 272K model triggers near 256K and a 200K model near
184K. Extension behavior and failures can affect the actual compaction path.

The `keepRecentTokens` values and the `antigravity` rows were added on
2026-10-19. The motivation is that Pi truncates every tool result to 2000
characters and drops thinking blocks before summarizing, so whatever reaches the
summarizer is already lossy; keeping more of the tail verbatim is the only
native lever against that. The specific value 40000 is bounded by measurement
rather than chosen by ratio, and the derivation is in the measured section
below: the first attempt that day used 100000 and was withdrawn the same hour,
because the measured floor arithmetic showed it could place the post-compaction
floor at or above the 400K trigger. Treat 40000 as provisional in exactly the
same way as the thresholds.

The `antigravity` change deliberately departs from recommendation 3 below, which
said to leave Gemini at its defaults until its runs were measured. Before the
change those models reserved only the default 16384 of a 1.0M window, so they
would have carried roughly 984K of context before compacting once. Reverting to
that default is a one-line change if the measured runs disagree.

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
3. **Keep the 400K Claude and 275K GPT settings provisional.** Family names and
   advertised windows do not establish the best threshold.
   *Superseded in part on 2026-10-19:* Gemini through `antigravity` was moved off
   its defaults to the same 400K trigger and 40000 retention, because the
   default reserve left it carrying roughly 984K of a 1.0M window before its
   first compaction. That is a bounded-risk hypothesis, not a measured result,
   and it is listed as an open question below. Grok turned out not to be a
   registered Pi provider at all, so no Pi threshold applies to it.
4. **Test a dedicated summarizer before adopting one.** Compare the active
   model's text summary with a GPT-generated text summary. A stronger or more
   expensive summarizer is not automatically better at preserving task state.
5. **If tool-output clutter remains a problem, test batched pruning.** Preserve
   original outputs for retrieval, and prune at meaningful task boundaries,
   not every turn. Rewriting earlier context can invalidate prompt caches and
   increase total cost despite reducing context size. Test bridge compatibility.

These recommendations apply to Pi, including FirstMate sessions actually using
Pi. They do not configure standalone Claude Code or other harnesses.

## Measured evidence, 2026-10-19

A scan of local Pi history found **808 compaction events across 290 sessions**
that recorded a usable `tokensBefore`. Medians by provider, where "after" is the
context of the first assistant response following the compaction:

| Provider | Events | Median tokens before | Median context after | Retained | Native artifacts |
|---|---|---|---|---|---|
| `openai-codex` | 742 | 261,753 | 33,007 | 13% | 555 |
| `cursor` | 37 | 211,512 | no usage reported | n/a | 0 |
| `claude-bridge` | 21 | 401,161 | 92,844 | 23% | 3 |
| `deepseek` | 6 | 270,329 | 43,869 | 16% | 0 |
| `antigravity` | 1 | 418,419 | 23,925 | 6% | 1 |

Three things follow, and only the first is conclusive.

**The 400K Claude trigger is now verified live.** The open item below asked for a
post-reload confirmation; a median of 401,161 tokens before compaction across 21
bridge events supplies it. The 275K GPT trigger is likewise consistent with its
261,753 median, allowing for overshoot between checks.

**Claude restarts about 2.8 times heavier than GPT**, 92,844 against 33,007. The
earlier sample suggested 1.6 to 1.9 times. The larger figure still does not
isolate a cause: retained messages, tool and prompt wrapping, reasoning
representation, FirstMate context injection and provider accounting all differ.
It does bound the practical consequence: every bridge turn after a compaction
carries roughly three times the floor of a GPT turn.

**Cursor appears to compact past its own window.** A 200K model shows a median
of 211,512 tokens before compaction, above the window and well above the 183.6K
default trigger, which points at overflow recovery rather than a threshold
check. A `keepRecentTokens` value was briefly given to `cursor/default` on
2026-10-19 and then removed, because retention cannot help a model that is
already overflowing and would raise the floor on a window it is already
exceeding. Cursor reports no usage, so the retained figure cannot be computed
from history. It needs a reserve investigation, not a retention value.
The same reasoning removed the brief `antigravity/gpt-oss-120b` override: a
131.1K window implies a trigger near 53K, which is close to the measured fixed
overhead alone, so that model is left at Pi's defaults.

Comparing the two configured thresholds as raw numbers is a category error: 400K
is 40% of a 1M window summarized by a text model, and 275K is 55% of a 500K
window compacted by a provider-native mechanism that this history shows was used
555 times. Per cycle, bridge buys about 307K of headroom against GPT's 242K,
while paying a floor three times higher on every turn in between. Which is
"better" depends on whether the scarce resource is subscription utilization or
billed tokens, and on continuation quality, which none of these counts measure.

### Decomposing the floor, and why retention is 40000

The 10 bridge compactions recorded in this project's own sessions allow the
post-compaction floor to be separated into its parts, where kept is the residual
`floor - overhead - summary`:

| Tokens before | Floor | Fixed overhead | Summary | Implied kept |
|---|---|---|---|---|
| 339,005 | 105,144 | 35,514 | 5,884 | 63,746 |
| 275,518 | 128,538 | 35,514 | 7,486 | 85,538 |
| 275,675 | 128,784 | 35,514 | 7,383 | 85,887 |
| 401,161 | 122,310 | 70,948 | 3,187 | 48,175 |
| 402,487 | 123,967 | 41,412 | 5,822 | 76,733 |
| 401,210 | 78,067 | 41,412 | 8,479 | 28,176 |
| 401,135 | 137,353 | 41,412 | 9,291 | 86,650 |
| 400,923 | 139,449 | 41,412 | 9,102 | 88,935 |
| 402,175 | 29,530 | 39,997 | 1,532 | -11,999 |
| 400,258 | 110,233 | 40,938 | 4,408 | 64,887 |

Median fixed overhead 41,175, median summary 6,633, median implied kept 76,733,
against a configured `keepRecentTokens` of 20000 throughout. Two consequences
matter more than the medians.

**Fixed overhead dominates the floor.** About 41,000 tokens of system prompt,
tool declarations and injected project context ride on every single turn and
survive every compaction. That is roughly a third of a typical floor, and no
compaction setting touches it. Reducing it would lower the cost of every turn in
every session, which no threshold change can do.

**The configured retention is not the retention delivered.** The implied kept
value exceeds the 20000 budget in every usable row, with a median ratio near
3.8x. The residual absorbs several distinct effects - Pi's cut point stops at a
message boundary and can overshoot, Pi's own token estimate differs from the
provider's count, overhead grows within a session, and the last row is an
OpenAI-native event attributed here by active model - so 3.8x is an upper bound
on the real overshoot, not a calibrated multiplier. It is still the operative
number, because a setting must be safe across the whole plausible range.

That is what rules out 100000. At the measured upper bound the floor becomes
41,175 + about 5,000 + 100,000 x 3.8, or roughly 431,000, which is **above the
400K trigger**: compaction would no longer free enough context to clear the
condition that caused it. Even with no overshoot at all it lands near 147,000,
leaving only 252K of headroom. The upper case is not merely expensive, it is a
malfunction, so 100000 was withdrawn within the hour it was set.

40000 is the largest round value that stays safe across the full range: about
198,000 at the 3.8x upper bound, which keeps the floor under half the trigger,
and about 87,000 with no overshoot, close to today's observed behavior. It is
double the previous effective setting rather than five times it. Raise it only
after the next real compactions show which end of that range is true.

## Evidence so far and its limits

An earlier inspection of local Pi history found 553 compactions across 1,843
sessions with recorded usage. Most were GPT runs. One FirstMate session recorded
70 compactions over about 189 hours. That demonstrates repeated continuation,
not that task quality was preserved or that its threshold was optimal.

A FirstMate session switching from GPT-6.1 Sol to Opus 5.5 through claude-bridge
provided these historical observations:

| Observation | GPT-6.1 Sol | Opus 5.5 through claude-bridge |
|---|---|---|
| Context reported around the model switch | ~202K | ~338K |
| Context on the next response after sampled compactions | ~31-35K | ~105-130K |
| Sampled compaction entries | 498828, then 278294 tokens before | 339005, then 275518 tokens before |

The larger first Claude compaction followed a switch into an already-large
conversation. The later 275518 event showed the running process still used the
previous 275K policy. Neither event verified the 400K trigger in a live run.
**Resolved on 2026-10-19:** the measured section above records a 401,161-token
median across 21 bridge compactions, so the 400K trigger is active in practice.

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
research. Establish the Gemini baseline before selecting its trial values.
Do not change summarizer, trigger and pruning policy in the same comparison.

### 3b. Test retention separately from the threshold

`keepRecentTokens` is a second, independent knob and the 2026-10-19 values were
set by ratio, not by measurement. Hold the trigger fixed and compare retention
at 20000, 40000 and one higher value per 1M model. Retention trades fidelity
for a permanently higher per-turn floor and more frequent compactions, so score
both sides: what the summary preserved, and the measured cost of carrying the
larger floor across the turns between compactions. A retention value close to
the trigger leaves too little headroom and must be rejected on that ground
alone, independently of quality.

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

### Open questions as of 2026-10-19

1. Is 400K the right Claude trigger, or does 350K or 450K continue better at
   equal or lower total cost? Verified active, never compared.
2. What is the true cut-point overshoot? The decomposition bounds it at about
   3.8x and cannot rule out 1x. Measuring it directly sets the ceiling for any
   retention value, so it is the highest-value single measurement here.
3. Is 40000 the right retention, and is there room to raise it once the
   overshoot is known? Deliberately conservative, untested.
4. Can the roughly 41,000 tokens of fixed per-turn overhead be reduced? It is
   the largest component of the floor, and no compaction setting touches it.
5. Does the Gemini `antigravity` move off defaults help or hurt? It has exactly
   one historical compaction event, which is not a baseline.
6. Why does `cursor` compact above its 200K window, and does it need a reserve
   rather than only retention?
7. Does the GPT native mechanism actually preserve continuation better than the
   Claude text summary on the same task, as its vendor benchmark claims? The
   555 native events here prove usage, not quality.

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

### Temporary upstream message-preservation fix

The package declaration pins the public PR author's revision
`kunchenguid/pi-openai-server-compaction@cf30a9fee30312ef33d03fd1d99ad511e81e2b95`,
from [upstream PR #18](https://github.com/algal/pi-openai-server-compaction/pull/18).
It is not a private patch or a merged upstream release. The author's repository
exposes the commit on a branch, so fresh Pi installs can clone and check it out.
Only one compaction package is declared.

The fix preserves extension-injected context and unanswered trailing messages
in remote replacement history. On Pi 1.3.0, an isolated real CLI/RPC regression
reproduced their loss before the change and their presence afterward, including
a fresh-process resume. The test used fabricated credentials and local Responses
fixtures, not a live OpenAI quality evaluation. Upstream typecheck/smoke tests
also passed; smoke assertions passed against the installed Pi 1.3.0 SDK.
The package still declares a Pi 0.80.x peer range, so these checks are not a
blanket compatibility guarantee.

**Known separate limitation:** this PR does not fix failed summary and native
checkpoint requests producing a placeholder-only compaction. Missing
`details.remoteCompaction` plus success-sounding placeholder text is not proof
that useful context was retained. Do not treat this pin as resolving that failure
or repairing historical session entries.

Pinned revisions do not advance during daily updates. Once upstream incorporates
the fix, verify that revision with Firstmate before replacing this temporary
source with the upstream repository. Update the authored declaration and its
regression in `tests/pi_settings_test.sh` together, then reconcile with
`pi update <exact-package-source>`. New sessions load it; live sessions require
an explicit reload or coordinated restart. Never patch the managed cache.

### Model thresholds

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
