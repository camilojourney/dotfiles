{
  # Baby Menu comes from the author's non-official Homebrew tap. Keep this
  # tap local because the remote host does not install Baby Menu.
  homebrew.taps = [
    {
      name = "kunchenguid/tap";
      trusted = true;
    }
  ];

  # Local workstation apps. The remote host receives the shared baseline only.
  homebrew.casks = [
    "baby-menu"
    "camo-studio"
    "cursor"
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
    Dato = 1470584107;
    Goodnotes = 1444383602;
    WhatsApp = 310633997;
  };

  # Finder is always leftmost (macOS); Trash is always rightmost.
  system.defaults.dock = {
    persistent-apps = [
      "/Applications/WezTerm.app"
      "/Applications/Cursor.app"
      "/Applications/ChatGPT.app"
      "/Applications/Obsidian.app"
      "/Applications/Safari.app"
    ];
    show-recents = false;
  };
}
