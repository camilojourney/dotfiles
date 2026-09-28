# Personal apps - not required for coding or agent work. Never imported by
# the plain camilo/camilo-remote flake targets; only the camilo-total and
# camilo-remote-total targets (run via ./rebuild-total.sh) pull this in.
{ ... }:
{
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
