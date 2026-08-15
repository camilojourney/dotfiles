{ config, lib, pkgs, userName, homeDirectory, ... }:

let
  declaredMasAppIds = lib.concatStringsSep " " (map toString (lib.attrValues config.homebrew.masApps));
in
{
  # If you use Determinate Nix Installer (recommended), let it manage Nix itself.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  homebrew = {
    enable = true;
    enableZshIntegration = true; # puts /opt/homebrew/bin on PATH (claude, codex, etc.)
    onActivation = {
      # Removes undeclared Homebrew formulae, casks, and taps while preserving
      # their user data. Mac App Store apps need the cleanup script below.
      cleanup = "uninstall";
      upgrade = true; # brew upgrade + brew upgrade --cask on each rebuild
    };
    brews = [
      "espeak-ng" # optional text-to-speech support
      "fswatch" # used by Invoz watch loops
      "gh" # GitHub CLI
      "gnupg" # GPG key generation and commit signing
      "herdr" # agent multiplexer for SSH remote machines
      "just" # task runner for Invoz and other projects
      "mas" # Mac App Store CLI and MAS cleanup
      "node" # owns npm; never install a separate global npm
      "opencode"
      "pass" # password-store CLI
      "pinentry-mac" # macOS passphrase prompt for gpg-agent
      "pipx" # isolated Python CLIs managed by the agent-tool manifest
      "starship" # nixpkgs starship currently fails to link on Darwin
      "tmux" # runtime backend for terminal-multiplexed agent sessions
      "uv"
    ];
    casks = [
      "wezterm"
      "antigravity-cli"
      "claude"
      "claude-code"
      "codex"
      "font-hack-nerd-font" # shared font used by terminal and editor tools
      "gcloud-cli"
      "grok-build"
      "google-chrome"
      "chatgpt"
      "mullvad-vpn"
      "nomachine"
      "tailscale-app"
    ];
    # App Store apps (not available as Homebrew casks).
    masApps = {
      Xcode = 497799835;
    };
  };

  # Homebrew Bundle does not remove MAS apps that disappear from masApps.
  # Run the cleanup as the primary user after Bundle has installed declared apps.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    ${pkgs.bash}/bin/bash ${../../scripts/mas-cleanup.sh} /opt/homebrew/bin/mas ${userName} ${declaredMasAppIds}
  '';

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
      AppleInterfaceStyleSwitchesAutomatically = false;
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
