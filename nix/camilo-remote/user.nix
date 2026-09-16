{
  programs.zsh.shellAliases = {
    rebuild = "sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/github/dotfiles#camilo-remote";
    safe-maintenance = "~/github/dotfiles/scripts/safe-maintenance.sh --profile camilo-remote";
  };
}
