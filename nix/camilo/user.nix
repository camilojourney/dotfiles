{ config, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
  vaultPath =
    "${config.home.homeDirectory}/Library/Mobile Documents/iCloud~md~obsidian/Documents/My Vault";
in
{
  programs.zsh.shellAliases = {
    rebuild = "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles#camilo";
    safe-maintenance = "~/github/dotfiles/scripts/safe-maintenance.sh --profile camilo";
  };

  home.file = {
    # Obsidian vault lives in iCloud; stable path for Pi and other agents.
    "github/vault".source = config.lib.file.mkOutOfStoreSymlink vaultPath;
  };
}
