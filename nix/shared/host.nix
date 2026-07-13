{ pkgs, userName, homeDirectory, ... }:

{
  # If you use Determinate Nix Installer (recommended), let it manage Nix itself.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  homebrew = {
    enable = true;
    enableZshIntegration = true; # puts /opt/homebrew/bin on PATH (claude, codex, etc.)
    # Keep activation focused on declared installs. This machine has existing
    # third-party taps; cleanup can fail on Homebrew tap trust before core tools
    # like herdr/starship get installed.
    onActivation.cleanup = "none";
    taps = [ ];
    brews = [
      "herdr"
      "espeak-ng"
      "fswatch" # used by invoz justfile watch loops
      "gh"
      "just" # invoz (and other) Justfiles
      "opencode"
      "mas" # Mac App Store CLI (Dato, etc.)
      "starship" # brew binary; nixpkgs starship currently fails to link on Darwin
    ];
    casks = [
      "wezterm"
      "claude"
      # claude-code and codex CLIs are already installed globally under
      # /opt/homebrew/lib/node_modules; their Brew casks conflict on
      # /opt/homebrew/bin/{claude,codex}.
      "font-hack-nerd-font"
      "gcloud-cli"
      "google-chrome"
      "chatgpt"
      "cursor"
      # grammarly-desktop: install from site - brew adopt fails on xattr
      "mullvad-vpn"
      # nomachine: install manually when needed - brew download/pkg often fails mid-switch
      "obsidian"
      # tailscale-app: installed/running manually; Brew pkg adoption currently
      # fails during upgrade scripts, so do not block system activation on it.
    ];
    # App Store apps are intentionally host-specific. Xcode is already present
    # on the Mini, and `mas` currently cannot detect indexed App Store apps
    # there, so managing it here blocks activation.
    masApps = { };
  };

  # starship comes from Home Manager (programs.starship in shared/user.nix)
  environment.systemPackages = [ ];

  system.primaryUser = userName;
  users.users = {
    ${userName} = {
      home = homeDirectory;
      shell = pkgs.zsh;
    };
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
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/run/current-system/sw/bin"
    "/etc/profiles/per-user/${userName}/bin"
  ];

  system.stateVersion = 6;
}
