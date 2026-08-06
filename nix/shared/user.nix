{ config, pkgs, lib, userName, homeDirectory, ... }:

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

  # Pi CLI itself is npm-global (same as Kun), not Homebrew. Needs brew `node`.
  home.activation.installPi = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/opt/homebrew/bin:$PATH"
    if command -v npm >/dev/null 2>&1; then
      npm install -g --ignore-scripts @earendil-works/pi-coding-agent
    else
      echo "installPi: npm not found (install brew node first); skipping"
    fi
  '';

  # graphify: skill for the harnesses you use most. CLI via pipx (not brew Python).
  # Platforms: claude, codex, pi, opencode. There is no "grok" target - Grok runs
  # through Pi (default) and OpenCode, so those two cover it.
  home.activation.installGraphify = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="/opt/homebrew/bin:$PATH"
    if command -v pipx >/dev/null 2>&1; then
      pipx install --quiet graphifyy 2>/dev/null || pipx upgrade --quiet graphifyy 2>/dev/null || true
    else
      echo "installGraphify: pipx not found (brew install pipx); skipping CLI install"
    fi
    if command -v graphify >/dev/null 2>&1; then
      graphify install --platform claude >/dev/null 2>&1 || true
      graphify install --platform codex >/dev/null 2>&1 || true
      graphify install --platform pi >/dev/null 2>&1 || true
      graphify install --platform opencode >/dev/null 2>&1 || true
    else
      echo "installGraphify: graphify CLI not on PATH; skipping skill registration"
    fi
  '';
}
