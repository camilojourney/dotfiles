# Storage on the remote Mac

Run `bash scripts/storage-report.sh` from the repository, or `storage-report`
after activating the remote profile. Run it weekly and after large installs.
It only measures existing locations. Totals overlap, and access errors mean a
measurement may be incomplete. It does not record private file contents.

Disk space and RAM are different. Removing files frees disk space. To diagnose
RAM pressure, use Activity Monitor's Memory tab and close unused applications,
agent sessions, containers, or model servers.

| Where data grows | What it contains | How to handle it |
| --- | --- | --- |
| `/nix/store` | Packages and retained rebuild generations | Use Nix garbage collection; never manually delete store files. |
| `/opt/homebrew`, `~/Library/Caches/Homebrew` | Installed tools, older versions, downloads | Preview `brew cleanup -n`, then run `brew cleanup` if the listed cleanup is wanted. |
| `~/.cache/uv` (or `UV_CACHE_DIR`) | Python package cache | Between jobs, use `uv cache prune` for unused entries. |
| `~/.npm` | npm cache and logs | Start with `npm cache verify`; inspect size before choosing further cleanup. |
| `~/github` | Repositories, `node_modules`, `.venv`, build output, project data | Inspect one project at a time. Generated dependencies may be recreated from lockfiles; keep source, `.git`, databases, and unpublished work. |
| `~/.cache/huggingface`, `~/.ollama` | Downloaded model weights | Remove individual unused models through their owning tool. Models can be very large. |
| Docker/Colima directories | Images, containers, volumes | If installed, inspect `docker system df`; volumes may contain databases. Do not bulk-delete these directories. |
| `~/.codex`, `~/.claude`, `~/.pi` | Sessions, history, credentials, plugins, tool state | These are not disposable caches. Review specific sessions rather than deleting the whole directory. |
| `~/.local`, `~/Library/pnpm`, `~/.nvm` | Installed tools and runtimes as well as some caches | Uninstall unused versions with the owning package manager. |
| `~/Downloads`, `~/.Trash`, `~/Library/Logs` | Downloads, deleted files, logs | Review old files and retain anything needed before deleting. |
| `~/Library/Developer` | Existing Apple development data, if any | This profile does not install Xcode. Inspect existing contents before removing build data or simulators. |

For Nix, once installed, preview currently collectible paths with
`nix-store --gc --print-dead`. `nix-collect-garbage` collects unused store paths
without explicitly deleting old generations. Those generations retain rollback
options and their packages. `nix-collect-garbage --delete-older-than 30d` also
deletes old profile generations; use it only when those rollback versions are
no longer needed. System profiles may require administrator access. Never add
generation deletion to every rebuild without choosing a retention policy.

The remote profile does not uninstall arbitrary undeclared apps during rebuild.
Cache cleanup and uninstalling applications are separate operations. No automatic
deletion schedule is configured. Package-manager caches can grow again as tools
download dependencies; retained sessions, models, and project data need explicit
review.

References: [Homebrew cleanup](https://docs.brew.sh/Manpage),
[uv cache management](https://docs.astral.sh/uv/concepts/cache/),
[Nix garbage collection](https://nix.dev/manual/nix/stable/command-ref/nix-collect-garbage.html).
