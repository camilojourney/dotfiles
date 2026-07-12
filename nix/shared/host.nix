{ pkgs, userName, homeDirectory, ... }:

{
  # If you use Determinate Nix Installer (recommended), let it manage Nix itself.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  homebrew = {
    enable = true;
    enableZshIntegration = true; # puts /opt/homebrew/bin on PATH (claude, codex, etc.)
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
      "starship" # brew binary; nixpkgs starship currently fails to link on Darwin
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
      # grammarly-desktop: install from site - brew adopt fails on xattr
      "mullvad-vpn"
      # nomachine: install manually when needed - brew download/pkg often fails mid-switch
      "obsidian"
      "tailscale-app"
    ];
    # App Store apps (not available as Homebrew casks).
    masApps = {
      Xcode = 497799835;
    };
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
