# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- homebrew.onActivation.cleanup = "uninstall" in nix/configuration.nix is intentional, on both machines. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible, while leaving removed apps' user data in place (unlike "zap"). Do not soften it to "none".
- Never commit .no-mistakes/ validation evidence to this public repo. .no-mistakes/ is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.

# Maintaining this file
Keep this file for knowledge useful to almost every future agent session in this project. Do not repeat what the codebase already shows; point to the authoritative file or command instead. Prefer rewriting or pruning existing entries over appending new ones. When updating this file, preserve this bar for all agents and keep entries concise.
