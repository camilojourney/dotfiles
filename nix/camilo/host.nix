{ lib, ... }:
{
  # Baby Menu comes from the author's non-official Homebrew tap. Keep this
  # tap local because the remote host does not install Baby Menu.
  homebrew.taps = [
    {
      name = "kunchenguid/tap";
      trusted = true;
    }
    {
      name = "automic-vault/isotopes";
      trusted = true;
    }
  ];

  # Local workstation apps. The remote host receives the shared baseline only.
  homebrew.casks = [
    "automic-vault"
    "baby-menu"
    "camo-studio"
    "deepl"
    "elgato-stream-deck"
    "grammarly-desktop"
    "logi-options+"
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

  # Finder is always leftmost (macOS); Trash is always rightmost.
  # Shared baseline (WezTerm, Google Chrome) comes from shared/host.nix;
  # these are the laptop's personal additions on top of it.
  system.defaults.dock.persistent-apps = lib.mkAfter [
    "/Applications/Calendar.app"
    "/Applications/Notion.app"
    "/Applications/Reminders.app"
    "/Applications/Obsidian.app"
  ];
}
