# Bootstrap

Run `setup/mac.sh` on a fresh Mac **after** cloning this repo and **after** replacing the placeholder values in the Nix files.

Typical flow:

1. Clone the repo
2. Replace placeholder values such as:
   - `yourname`
   - `/Users/yourname`
   - `Your Name`
   - `you@example.com`
3. Run:

```bash
bash setup/mac.sh
```

On the remote Mac:

```bash
DARWIN_FLAKE_ATTR=camilo-remote bash setup/mac.sh
```

What the script does:

- checks that you replaced the placeholder values first
- reuses an existing Nix daemon profile when Nix is missing from the current PATH
- installs Determinate Nix only when no existing profile or service plist is found
- checks daemon connectivity before installing Homebrew or activating the system
- installs Homebrew if needed
- applies the `nix-darwin` + Home Manager configuration (`#camilo` by default, or `#camilo-remote` when `DARWIN_FLAKE_ATTR=camilo-remote`)
- installs `nvm` and a default Node.js version if needed

This script is meant for the **first bootstrap on a new Mac**. After that, most ongoing changes should happen by editing the Nix config and running `./rebuild.sh` - it detects the account and works the same way on either host. Use `./rebuild-total.sh` instead when you also want the personal apps in `nix/camilo-extra.nix`.

It's designed to complete in a single run: right after installing Nix it sources the daemon profile into the current shell, and the first `nix-darwin` activation resolves `nix` by absolute path with the experimental features it needs, so you should **not** need to run it twice or open a new shell partway through.

If an existing installation is unavailable (for example, `/nix` is unmounted
or the daemon is not running), setup stops and points to
[Nix recovery](../docs/RECOVERY.md#nix-is-missing-or-unavailable). Follow that
guide to check macOS background permission and restore the existing services.
Setup does not change background approvals or reinstall an unhealthy installation.

`NIX_DAEMON_PROFILE`, `NIX_LAUNCH_DAEMONS_DIR`, and `DARWIN_REBUILD_BIN` are overridable only so the regression test can point the script at sandboxed paths.
`DARWIN_FLAKE_ATTR` selects the flake output (`camilo` or `camilo-remote`).
For normal bootstrap usage, leave the three path overrides unset.

## Testing

`setup/mac.sh` installs Nix and activates a real system, so tests never run it against the real machine. Instead:

```bash
bash tests/mac_setup_test.sh
```

This runs the actual script against a PATH-masked sandbox of stub executables
that simulate fresh setup, an existing installation, stale shell initialization,
unavailable installation paths, and a daemon connection failure. It never
touches the network, the real Nix store, Homebrew, sudo, or system state.
The harness also re-homes `NVM_DIR` under the sandboxed `HOME`, unsets inherited `BASH_ENV`/`ENV`, and refuses any harness or stub write path that escapes the temp sandbox.
See `AGENTS.md` for details.
