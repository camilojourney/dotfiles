{
  # Laptop-only peripherals / desk gear (not on the Mini).
  homebrew.casks = [
    "camo-studio"
    "logi-options+"
    "elgato-stream-deck"
    "obs"
    "wispr-flow"
    "whatsapp"
    "deepl"
  ];

  homebrew.masApps = {
    Dato = 1470584107;
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
