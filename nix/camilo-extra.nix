# Personal apps - not required for coding or agent work. Never imported by
# the plain camilo/camilo-remote flake targets; only the camilo-total and
# camilo-remote-total targets (run via ./rebuild-total.sh) pull this in.
{ userName, ... }:
{
  # Share OBS scenes/profile settings, not its runtime folders and backups.
  home-manager.users.${userName} = { config, pkgs, lib, ... }:
    let
      dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
    in
    {
      # Sony camera control over USB (scripts/sony-camera.sh).
      home.packages = [ pkgs.gphoto2 ];
      imports = [
        (import ./config-directory.nix {
          name = "obs-studio";
          source = "home/.config/obs-studio/basic";
          target = "Library/Application Support/obs-studio/basic";
          files = [
            "profiles/Streaming/basic.ini"
            "profiles/Streaming/streamEncoder.json"
            "profiles/Streaming/recordEncoder.json"
            "profiles/Streaming/aitum.json"
            "scenes/Streaming.json"
          ];
        })
      ];

      # The repo is public: .gitattributes routes OBS files with stream keys
      # through this filter so commits carry blank keys. Git skips a filter it
      # has no config for, so register it on every rebuild.
      home.activation.obsKeysGitFilter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -d "${dotfilesDir}/.git" ]; then
          ${pkgs.git}/bin/git -C "${dotfilesDir}" config filter.obs-keys.clean "bash ${dotfilesDir}/scripts/obs-strip-keys.sh"
          ${pkgs.git}/bin/git -C "${dotfilesDir}" config filter.obs-keys.required true
        fi
      '';
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
