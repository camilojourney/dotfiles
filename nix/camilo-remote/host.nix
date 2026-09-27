{ lib, ... }:
{
  # Keep remote access available after locking the screen. Idle system sleep
  # suspends Tailscale networking; the display may still turn off normally.
  power.sleep.computer = "never";

  # Installing the remote profile must not delete unrelated existing apps.
  homebrew.onActivation.cleanup = lib.mkForce "none";
  homebrew.onActivation.upgrade = lib.mkForce false;

  homebrew.taps = [
    {
      name = "kunchenguid/tap";
      trusted = true;
    }
  ];

  # Explicit allowlist: keep the remote Mac lean, with Baby Menu for agent quotas.
  homebrew.casks = lib.mkForce [
    "wezterm"
    "claude-code"
    "codex"
    "baby-menu"
    "font-hack-nerd-font"
    # NoMachine 9.8.2's upstream download redirects to HTML, failing Brew's
    # checksum and blocking the entire activation. Leave it unmanaged until
    # a working cask is available; cleanup=none preserves existing installs.
    "tailscale-app"
  ];
  homebrew.masApps = lib.mkForce { };

  # Coding and remote access only. IB Gateway is installed
  # manually from IBKR because Homebrew has no maintained Gateway cask; see
  # docs/mini-mac-remote-ib-gateway.md. Do not substitute IBKR Desktop or TWS.
}
