# Recovery

What to do if you lose your normal way of reaching or fixing a machine.

## Nix is missing or unavailable

Both machines use Determinate Nix. The `nix.enable = false` setting is
intentional: nix-darwin must not take over management of that installation.
A missing command can mean an unmounted store or a stale shell; a working
Nix executable does not prove its daemon is available.

In the October 2026 incident, the installation was intact, but macOS
background task management marked both the store-mount and daemon jobs as
disallowed. Manually registering the existing jobs restored that session;
background permission and a successful reboot are separate checks.

### Check macOS background permission

Open **System Settings > General > Login Items & Extensions > App Background
Activity** (called **Allow in the Background** on older macOS versions).
Allow **Determinate Systems, Inc.**; use the information button to identify
the item associated with `/usr/local/bin/determinate-nixd` and its store
and daemon plists. This is a local user setting: do not reset the background
task database or attempt to bypass approval through scripts or Nix config.

```sh
sudo /usr/bin/sfltool dumpbtm |
  /usr/bin/grep -B 8 -A 6 -E 'Identifier:.*systems[.]determinate[.]nix-(store|daemon)'
```

Check the actual legacy-daemon records for
`systems.determinate.nix-store` and `systems.determinate.nix-daemon`, not
just the developer grouping. Each must be **allowed**; **enabled** alone
does not establish approval. Notification flags can differ. If the toggle
appears on but either entry remains disallowed, resolve that discrepancy
before treating the repair as persistent. An empty filtered result is
inconclusive, not proof of approval.

### Restore the installed services when they are unregistered

Check the mount job first:

```sh
sudo /bin/launchctl print system/systems.determinate.nix-store
```

Only if launchctl reports that it cannot find this service, validate and
register its existing plist:

```sh
/usr/bin/plutil -lint /Library/LaunchDaemons/systems.determinate.nix-store.plist &&
sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/systems.determinate.nix-store.plist
```

Confirm the store is mounted and its installed executable works:

```sh
/sbin/mount | /usr/bin/grep ' on /nix '
/nix/var/nix/profiles/default/bin/nix --version
```

If the mount job is already registered but the store remains unmounted,
inspect `/var/log/determinate-nix-init.log` locally before changing service
registration. A completed mount job with no running PID and exit status
zero is normal. If a plist or executable is missing, investigate the
existing installation; do not manufacture a replacement plist.

Next check the daemon job:

```sh
sudo /bin/launchctl print system/systems.determinate.nix-daemon
```

Again, only if this service is unregistered:

```sh
/usr/bin/plutil -lint /Library/LaunchDaemons/systems.determinate.nix-daemon.plist &&
sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/systems.determinate.nix-daemon.plist
```

The installed plist manages daemon startup and sockets. Do not create a
socket manually or restart a healthy job. A bootstrap failure needs its
actual error investigated, not repeated installation attempts.

### Refresh a stale shell and verify recovery

If the absolute executable works but the current zsh session still cannot
find Nix, reload its existing profile in that session:

```sh
unset __ETC_PROFILE_NIX_SOURCED
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
rehash
```

Test a fresh login shell with inherited Nix initialization guards removed,
including an actual connection to the daemon:

```sh
/usr/bin/env -u __ETC_PROFILE_NIX_SOURCED \
  -u __NIX_DARWIN_SET_ENVIRONMENT_DONE PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /bin/zsh -lic '
    command -v nix &&
    nix --version &&
    nix --extra-experimental-features nix-command store info --store daemon &&
    printf "%s\n" "Nix shell and daemon OK"
  '
```

Require successful command completion; a store URL or partial JSON printed
before an error is not success. A restricted-setting warning can coexist
with a successful connection and does not justify granting trusted-user
privileges. Save work, plan a normal reboot when you can reach the machine
again, then repeat the mount check and fresh-shell test. Success before
reboot alone does not establish that startup is repaired.

Do not erase the Nix volume, extract or share its unlock password, reinstall
Nix, or rerun setup merely because the command or daemon is unavailable.
Recover the existing installation first.

References: [Determinate's nix-darwin integration](https://docs.determinate.systems/guides/nix-darwin/),
Apple's [Login Items & Extensions guide](https://support.apple.com/guide/mac-help/change-login-items-extensions-settings-mtusr003/mac),
[background task management documentation](https://support.apple.com/en-gb/guide/deployment/depdca572563/1/web/1.0),
and the Nix [store connectivity command](https://nix.dev/manual/nix/2.35/command-ref/new-cli/nix3-store-info.html).

## Locked out of `camilo-remote` (the mac-mini) because Tailscale is down

Tailscale is currently the *only* configured way to reach the mac-mini
remotely (`nix/configuration.nix` keeps it awake specifically so it stays
reachable over Tailscale). If Tailscale itself is what broke, you've lost
that path - anything that also depends on Tailscale to reach the box (an
agent session, ChatGPT, etc.) is blocked the same way you are. Recovery has
to use something that does not depend on Tailscale's own health:

1. **Retry first.** Tailscale usually reconnects on its own after a network
   blip. If you still have any session alive on the box, `sudo tailscale up`
   or quitting/reopening Tailscale.app is often enough.
2. **Tailscale's admin console**
   (<https://login.tailscale.com/admin/machines>) shows the device's last-seen
   status and lets you expire or re-approve its key. It cannot run a command
   on the machine - it only manages the tailnet registration, not the box's
   running state.
3. **NoMachine, if it actually works.** It's declared in
   `nix/camilo-extra.nix` (only installed via `./rebuild-total.sh`), meant as
   a second access channel independent of Tailscale. As of this writing its
   cask has a known issue: upstream's 9.8.2 download redirects to HTML and
   fails Homebrew's checksum (see the comment next to `"nomachine"` in that
   file). Treat it as unverified until you've confirmed on the actual
   machine that it installs and connects - don't rely on it blind.
4. **Physical access is the real last resort.** If you're at the mac-mini,
   plug in a keyboard/monitor, or use Screen Sharing/SSH if you're on the
   same LAN, and run `sudo tailscale up` directly. If the daemon itself looks
   corrupted, `brew reinstall tailscale-app` and re-authenticate.

There is no automated watchdog that restarts Tailscale on the mac-mini if it
silently dies - that's a real gap, not a documented safety net. Confirming
`tailscale status` shows the mac-mini online is on you.

## A rebuild left a machine in a broken state

`darwin-rebuild` keeps prior system generations by default, so a bad rebuild
is reversible without reconstructing anything by hand:

```sh
sudo /run/current-system/sw/bin/darwin-rebuild --rollback
```

This restores the previous generation's system and Home Manager state. It
does not undo Homebrew's own cleanup pass from the bad rebuild (removed
casks/formulae stay removed) - re-running `./rebuild.sh` after the rollback
re-applies whatever the config declares.

See [`docs/STORAGE.md`](STORAGE.md) for how Nix generations relate to disk
usage, and when it's safe to garbage-collect old ones.
