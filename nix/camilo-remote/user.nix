{ config, ... }:
let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
in
{
  programs.zsh.shellAliases = {
    storage-report = "bash ~/github/dotfiles/scripts/storage-report.sh";
    rebuild = "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles#camilo-remote";
    safe-maintenance = "~/github/dotfiles/scripts/safe-maintenance.sh --profile camilo-remote";
  };

  # Match the laptop's Baby Menu settings and quota widgets.
  home.file = {
    ".baby-menu/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/extensions";
    ".baby-menu/agents.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/agents.json";
    ".baby-menu/preferences.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/preferences.json";
  };
}
