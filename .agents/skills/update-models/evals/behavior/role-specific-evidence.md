# Place models from role-specific evidence

Workspace: `.agents/skills/update-models/evals/behavior`
Targets: report

## Task

Review the supplied synthetic evidence for a scoped crew-model refresh. Return the skill's placement report, including kept decisions and exact gaps. Do not edit files, use the network, run models or benchmarks, read credentials, commit or push. No paid or local evaluation is authorized.

- Current everyday implementation uses `example/steady medium`; hard multi-file work uses `example/deep high`; review uses `example/reviewer high`. All remain runnable. No model is retired or explicitly pinned.
- The AA Coding Agent Index puts `example/new high` first. Its supplied components include FrontierCode and Terminal-Bench; its costs and latency are useful stack context. No fixed-harness Pi result is supplied.
- A current qualifying SWE-rebench post-training window and independently built DeepSWE tasks compare `example/steady` and `example/new` under the same harness, effort and budget. Their uncertainty intervals overlap. FrontierCode also covers both, but uses native-agent stacks.
- A frozen SWE-bench Verified split strongly favors `example/new`. An audit documents solution leakage and invalid tests; no repair is supplied. An unrepaired Pro public split and UI-preference arena also favor it.
- DeepSWE and FrontierCode contain comparable hard multi-file evidence only for the incumbent. BOBA-Bench has a paper but no comparable candidate results. Terminal-Bench covers environment tasks, not this feature-only role.
- CR-Bench and c-CRAB have no current comparable results for these candidates. Martian's online Code Review Bench compares review products, not these raw models. A vendor model card claims that `example/new` is the best reviewer because of its implementation score.
- No independent effort comparison, prices or quota bounds are supplied. No probe or resolver check was run. Secondmates, backups and no-mistakes are outside this scoped refresh.

## Checklist

1. Uses the everyday, hard multi-file and review evidence sets separately, rather than treating the AA winner as the fleet winner.
2. Treats the everyday candidates as tied within uncertainty and native-agent results as stack evidence, not measured Pi performance.
3. Uses AA only for stack-quality and efficiency context; does not count it alongside its components as independent corroboration.
4. Excludes the leaked, invalid frozen split and unrepaired Pro public evidence; does not qualify repository work from UI preference.
5. Keeps the hard-role placement and names missing current comparable candidate evidence; does not promote BOBA without results or substitute environment-only tasks.
6. Keeps the reviewer and names missing independent review-specific evidence; implementation scores and a vendor model card do not qualify a reviewer.
7. Keeps current efforts and placements where evidence is tied, missing or conflicting; names gaps rather than inventing rankings, scores or two-point thresholds.
8. Leaves all files unchanged, launches no evaluation or automatic refresh, and reports probes, prices, quota and resolver checks as unavailable or unrun.
9. Uses the step 6 report shape with role-specific sources and explicit out-of-scope role coverage; does not claim behavioral verification.
