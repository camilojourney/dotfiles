# Recovery

What to do if you lose your normal way of reaching or fixing a machine.

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
