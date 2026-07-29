# graphify reference: GitHub clone and cross-repo merge

Load this when the user passed one or more `https://github.com/...` URLs, or named several local subfolders to merge into one graph. Run Step 1 with `INPUT_PATH` set to `.` before these commands so `graphify-out/.graphify_python` points to the pinned runtime.

### Step 0 - Clone GitHub repo(s) (only if a GitHub URL was given)

**Single repo:**
```bash
LOCAL_PATH=$("$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py clone <github-url> [--branch <branch>])
# Use LOCAL_PATH as the target for all subsequent steps
```

**Multiple repos (cross-repo graph):**
```bash
# Clone each repo, run the full pipeline on each, then merge
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py clone <url1>   # → ~/.graphify/repos/<owner1>/<repo1>
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py clone <url2>   # → ~/.graphify/repos/<owner2>/<repo2>
# Run /graphify on each local path to produce their graph.json files
# Then merge:
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py merge-graphs \
  ~/.graphify/repos/<owner1>/<repo1>/graphify-out/graph.json \
  ~/.graphify/repos/<owner2>/<repo2>/graphify-out/graph.json \
  --out graphify-out/cross-repo-graph.json
```

Graphify clones into `~/.graphify/repos/<owner>/<repo>` and reuses existing clones on repeat runs. Each node in the merged graph carries a `repo` attribute so you can filter by origin.

**Multiple local subfolders (monorepo or multi-service layout):**

The skill pipeline writes all intermediate and final outputs to `graphify-out/` in the current working directory. Running the skill on each subfolder separately will clobber the same output dir. Instead, use the CLI directly for each subfolder — it places `graphify-out/` *inside* the scanned path:

```bash
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py extract ./core/     # → ./core/graphify-out/graph.json
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py extract ./service/  # → ./service/graphify-out/graph.json
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py extract ./platform/ # → ./platform/graphify-out/graph.json
# Add --backend gemini|kimi|openai|deepseek|claude-cli depending on which API key you have set

# Then merge at the project root:
"$(cat graphify-out/.graphify_python)" graphify-out/.graphify_cli.py merge-graphs \
  ./core/graphify-out/graph.json \
  ./service/graphify-out/graph.json \
  ./platform/graphify-out/graph.json \
  --out graphify-out/graph.json
```

Once `graphify-out/graph.json` exists, the fast path above takes over: any codebase question runs the pinned Graphify query command directly on the merged graph - no re-extraction, no size gate.
