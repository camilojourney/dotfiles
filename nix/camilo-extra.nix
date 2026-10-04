# Personal apps - not required for coding or agent work. Never imported by
# the plain camilo/camilo-remote flake targets; only the camilo-total and
# camilo-remote-total targets (run via ./rebuild-total.sh) pull this in.
{ lib, userName, homeDirectory, ... }:
{
  # Laptop only: rebuild-total every day at 05:00 (or at the next wake if the
  # Mac slept through it) and fast-forward Firstmate first. Runs as root so it
  # needs no sudo password; whatever is committed to this repo is applied
  # unattended. scripts/auto-rebuild.sh holds the logic and explains why the
  # plist points at it by path rather than through the Nix store.
  launchd.daemons.auto-rebuild = lib.mkIf (userName == "camiloslaptop") {
    serviceConfig = {
      Label = "org.dotfiles.auto-rebuild";
      ProgramArguments = [ "/bin/bash" "${homeDirectory}/github/dotfiles/scripts/auto-rebuild.sh" ];
      StartCalendarInterval = [ { Hour = 5; Minute = 0; } ];
      StandardOutPath = "/var/log/auto-rebuild.log";
      StandardErrorPath = "/var/log/auto-rebuild.log";
      # Keep the rebuild alive if launchd reloads this job mid-run.
      AbandonProcessGroup = true;
    };
  };

  homebrew.taps = [
    {
      name = "automic-vault/isotopes";
      trusted = true;
    }
  ];

  homebrew.casks = [
    "automic-vault"
    "camo-studio"
    "deepl"
    "elgato-stream-deck"
    "grammarly-desktop"
    "logi-options+"
    # NoMachine 9.8.2's upstream download redirects to HTML, failing Brew's
    # checksum. It's here, not in the shared baseline, so a broken cask can
    # never block a plain ./rebuild.sh on either machine.
    "nomachine"
    "notion"
    "obs"
    "obsidian"
    "wispr-flow"
  ];

  homebrew.masApps = {
    Xcode = 497799835;
    Dato = 1470584107;
    Goodnotes = 1444383602;
    WhatsApp = 310633997;
  };
}
