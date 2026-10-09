# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- homebrew.onActivation.cleanup = "uninstall" in nix/configuration.nix is intentional, on both machines. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible, while leaving removed apps' user data in place (unlike "zap"). Do not soften it to "none".
- Homebrew's python3 is managed the same way: only the libraries in the `python` list of nix/agent-tools.manifest.lock.json stay, every rebuild uninstalls anything else pip put there, and `PIP_REQUIRE_VIRTUALENV=1` blocks ad-hoc global installs. Project libraries belong in the project's own uv environment and Python CLIs in the manifest's `uv` list. Do not remove the cleanup.
- Both machines pull this repo's main and rebuild as root every day at 05:00 (docs/AUTO-UPDATE.md). Anything pushed to main reaches both machines unattended, so only push config you would run a rebuild with.
- For missing Nix, an unmounted store, or daemon connection failures, follow [Nix recovery](docs/RECOVERY.md#nix-is-missing-or-unavailable) before rerunning setup or considering reinstallation.
- Never commit .no-mistakes/ validation evidence to this public repo. .no-mistakes/ is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

# Maintaining this file
Keep this file for knowledge useful to almost every future agent session in this project. Do not repeat what the codebase already shows; point to the authoritative file or command instead. Prefer rewriting or pruning existing entries over appending new ones. When updating this file, preserve this bar for all agents and keep entries concise.
