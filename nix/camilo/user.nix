{ config, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
in
{
  programs.zsh.shellAliases = {
    rebuild = "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles#camilo";
  };

  home.file = {
    # Baby Menu is local-only. Runtime data remains unmanaged.
    ".baby-menu/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/extensions";
    ".baby-menu/agents.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/agents.json";
    ".baby-menu/preferences.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/preferences.json";
  };
}
