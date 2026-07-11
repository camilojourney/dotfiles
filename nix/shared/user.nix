{ config, pkgs, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
in
{
  home.username = "camiloslaptop";
  home.homeDirectory = "/Users/camiloslaptop";
  home.stateVersion = "23.11";
  home.language.base = "en_US.UTF-8";

  home.packages = with pkgs; [
    neovim
    git
    curl
    wget
    jq
    fd
    fzf
    fastfetch
    ripgrep
    killall
    lazygit
    tree
    bun
    rustup
    zip
    unzip
    nerd-fonts.hack
    roboto
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    font-awesome
  ];

  fonts.fontconfig.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
  };

  programs.git = {
    enable = true;
    lfs.enable = true;
    signing.format = null;
    settings = {
      user = {
        name = "Camilo Martinez";
        email = "juancamilomabe@gmail.com";
      };
      core.editor = "nvim";
      color.ui = true;
      push.autoSetupRemote = true;
      pull.rebase = true;
      rebase.updateRefs = true;
    };
  };

  # Lean prompt (aligned with kunchenguid): directory + git + duration + ❯
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases = {
      ".." = "cd ..";
      m = "git switch main";
      mst = "git switch master";
      pull = "git pull";
      push = "git push";
      pushf = "git push --force";
      add = "git add .";
      amend = "git commit --amend";
      reset = "git reset --soft HEAD^";
      rebasem = "git rebase -i main";
      rebasemst = "git rebase -i master";
      # High-agency agent shortcuts (same idea as Kun's home.nix)
      cc = "claude --dangerously-skip-permissions";
      co = "codex --full-auto";
    };
    initContent = ''
      bindkey '^f' autosuggest-accept
    '';
  };

  # Edit-in-place: repo files stay canonical; home paths are symlinks.
  home.file = {
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";
    ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/nvim";
    ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/herdr";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.claude/settings.json";
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".config/opencode/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
  };
}
