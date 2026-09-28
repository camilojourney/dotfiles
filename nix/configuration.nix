{ config, lib, pkgs, userName, homeDirectory, ... }:

let
  declaredMasAppIds = lib.concatStringsSep " " (map toString (lib.attrValues config.homebrew.masApps));
in
{
  # If you use Determinate Nix Installer (recommended), let it manage Nix itself.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;

  # Both machines stay reachable overnight: the laptop runs agent work while
  # unattended, the remote box is only reachable over Tailscale, which idle
  # sleep would suspend. On battery, macOS still sleeps on its own low-power
  # floor regardless of this setting.
  power.sleep.computer = "never";

  homebrew = {
    enable = true;
    enableZshIntegration = true; # puts /opt/homebrew/bin on PATH for Homebrew CLIs.
    onActivation = {
      # Removes undeclared Homebrew formulae, casks, and taps while preserving
      # their user data, on every machine. Mac App Store apps need the
      # cleanup script below instead - Homebrew Bundle doesn't reach those.
      cleanup = "uninstall";
      upgrade = true; # brew upgrade + brew upgrade --cask on each rebuild
    };
    taps = [
      {
        # Baby Menu comes from this non-official tap; wanted on both machines.
        name = "kunchenguid/tap";
        trusted = true;
      }
    ];
    brews = [
      "espeak-ng" # optional text-to-speech support
      "curl" # downloads pinned external agent releases during activation
      "fswatch" # used by Invoz watch loops
      "gh" # GitHub CLI
      "glab" # GitLab CLI
      "gnupg" # GPG key generation and commit signing
      "herdr" # agent multiplexer for SSH remote machines
      "just" # task runner for Invoz and other projects
      "mas" # Mac App Store CLI and MAS cleanup
      "node" # owns npm; never install a separate global npm
      "pass" # password-store CLI
      "pinentry-mac" # macOS passphrase prompt for gpg-agent
      "starship" # nixpkgs starship currently fails to link on Darwin
      "tmux" # runtime backend for terminal-multiplexed agent sessions
      "uv"
    ];
    casks = [
      "wezterm"
      "antigravity-cli"
      "font-hack-nerd-font" # shared font used by terminal and editor tools
      "gcloud-cli"
      "grok-build"
      "google-chrome"
      # chrome-devtools-axi's CHROME_DEVTOOLS_AXI_CHANNEL is set to "canary"
      # in home.nix so it never collides with the daily-driver google-chrome
      # above; that setting needs this app to actually exist.
      "google-chrome@canary"
      "chatgpt"
      "mullvad-vpn"
      "tailscale-app"
      "claude-code"
      "baby-menu"
      # Replaces Docker Desktop: gives `docker build`/`docker run` and
      # `kubectl` without Docker Desktop's battery/CPU overhead. Needed on
      # both machines to run Invoz.
      "orbstack"
    ];
  };

  # Homebrew Bundle does not remove MAS apps that disappear from masApps.
  # Run the cleanup as the primary user after Bundle has installed declared
  # apps. Gated on masApps actually being declared (only true when
  # nix/camilo-extra.nix is imported, i.e. via ./rebuild-total.sh) - not on
  # which machine this is, so a plain ./rebuild.sh never touches MAS apps.
  system.activationScripts.postActivation.text = lib.mkIf (config.homebrew.masApps != { }) (lib.mkAfter ''
    ${pkgs.bash}/bin/bash ${../scripts/mas-cleanup.sh} /opt/homebrew/bin/mas ${userName} ${declaredMasAppIds}
  '');

  # starship comes from Home Manager (programs.starship in home.nix)
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
      # Keep the menu bar and Dock out of the way on both machines.
      _HIHideMenuBar = true;
    };

    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      FXPreferredViewStyle = "clmv"; # columns view by default
    };

    trackpad = {
      Clicking = true;
    };

    # Identical, minimal Dock on both machines. Finder and Trash are
    # automatic bookends, not part of this list.
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      show-recents = false;
      persistent-apps = [
        "/Applications/WezTerm.app"
        "/Applications/Google Chrome.app"
      ];
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
