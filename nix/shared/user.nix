{ config, pkgs, lib, userName, homeDirectory, hostProfile, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
in
{
  home.username = userName;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "23.11";
  home.language.base = "en_US.UTF-8";

  # Lean set (aligned with kunchenguid): only CLIs used constantly + Hack Nerd Font.
  home.packages = with pkgs; [
    ripgrep
    fd
    fzf
    jq
    lazygit
    neovim
    nerd-fonts.hack
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
  # Package comes from Homebrew - nixpkgs starship fails to link on current
  # aarch64-darwin (ld64 crash in mac-notification-sys).
  programs.starship = {
    enable = true;
    package = pkgs.writeShellScriptBin "starship" ''
      exec /opt/homebrew/bin/starship "$@"
    '';
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
      # Same lean set as kunchenguid/home.nix
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
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
    ".config/cursor-launchers/config.sh.example".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/cursor-launchers/config.sh.example";
    "bin/cursor-go".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/cursor-launchers/cursor-go";
    "bin/cursor-go-bg".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/scripts/cursor-launchers/cursor-go-bg";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.claude/settings.json";
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".config/opencode/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";

    # Baby Menu (kunchenguid): authored extensions + prefs only.
    # Runtime (~/.baby-menu/{baby-menu.db*,cache,.cache}) stays unmanaged.
    # Officially supports mkOutOfStoreSymlink for extensions/.
    ".baby-menu/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/extensions";
    ".baby-menu/agents.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/agents.json";
    ".baby-menu/preferences.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/preferences.json";

    # Pi (kunchenguid-aligned): only authored config/theme/extensions.
    # Runtime (auth, sessions, ~/.pi/agent/npm|git) stays unmanaged.
    ".pi/agent/themes".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.pi/agent/themes";
    ".pi/agent/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.pi/agent/extensions";
    ".pi/agent/models.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.pi/agent/models.json";
    ".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.pi/agent/settings.json";
  };

  imports = [ ./agent-tools ];

  agentTools = {
    enable = true;
    inherit hostProfile;
  };
}
