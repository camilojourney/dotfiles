{ pkgs, ... }:

{
  # If you use Determinate Nix Installer (recommended), let it manage Nix itself.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";  # was "zap": remove unlisted apps but keep their user data
    taps = [ ];
    brews = [
      "herdr"
      "espeak-ng"
      "fswatch" # used by invoz justfile watch loops
      "gh"
      "just" # invoz (and other) Justfiles
      "opencode"
      "mas" # Mac App Store CLI (Dato, etc.)
    ];
    casks = [
      "wezterm"
      "claude-code"
      "claude"
      "codex"
      "font-hack-nerd-font"
      "gcloud-cli"
      "google-chrome"
      "chatgpt"
      "cursor"
      "deepl"
      "grammarly-desktop"
      "mullvad-vpn"
      "nomachine"
      "obsidian"
      "tailscale-app"
      "whatsapp"
    ];
    # App Store apps (not available as Homebrew casks).
    masApps = {
      Dato = 1470584107;
    };
  };

  # starship comes from Home Manager (programs.starship in shared/user.nix)
  environment.systemPackages = [ ];

  system.primaryUser = "camiloslaptop";
  users.users.camiloslaptop = {
    home = "/Users/camiloslaptop";
    shell = pkgs.zsh;
  };

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      "com.apple.swipescrolldirection" = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSNavPanelExpandedStateForSaveMode = true;
      NSNavPanelExpandedStateForSaveMode2 = true;
      AppleShowAllExtensions = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      FXPreferredViewStyle = "clmv"; # columns view by default
    };

    trackpad = {
      Clicking = true;
    };
  };

  environment.systemPath = [
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/camiloslaptop/bin"
  ];

  system.stateVersion = 6;
}
