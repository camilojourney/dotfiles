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

  # Home Manager's generated configuration man page currently creates an
  # options.json derivation with a context-free nixpkgs store reference.
  # Disable that optional artifact until upstream's generator is corrected.
  manual.manpages.enable = false;

  home.sessionVariables = {
    EDITOR = "nvim";
    # Point chrome-devtools-axi's default headless launches at Chrome Canary
    # instead of stable Chrome, so they never collide with the daily-driver
    # browser (same app bundle = macOS Launch Services treats a headless
    # ghost process as "Chrome is already open" and blocks a real window).
    CHROME_DEVTOOLS_AXI_CHANNEL = "canary";
    # Fixed profile dir so a login (e.g. the first `open` of a login tab)
    # persists across every later invocation instead of starting from a
    # fresh, signed-out profile each time.
    CHROME_DEVTOOLS_AXI_USER_DATA_DIR = "${homeDirectory}/.local/state/chrome-devtools-axi-profile";
  };

  # uv installs user-scoped CLI entry points, including graphify, here.
  home.sessionPath = [ "${homeDirectory}/.local/bin" ];

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
      format = "$username$hostname$directory$git_branch$git_status$cmd_duration$line_break$character";
      username.format = "[$user]($style)@";
      hostname.format = "[$hostname]($style):";
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
      # Matches Kun's alias: explicitly bypasses Claude Code permission prompts.
      cc = "claude --dangerously-skip-permissions";
      # --profile nix layers ~/.codex/nix.config.toml (nix-managed) on top of
      # the base ~/.codex/config.toml, which stays live/unmanaged since it's
      # mostly generated per-project trust and plugin state. A bare `codex`
      # invocation still falls back to the base file's own copies of these
      # same values, kept in sync by hand.
      co = "codex --profile nix";
      # Same persistent profile as chrome-devtools-axi's default, but with a
      # visible window so a running automation can be watched/debugged live.
      axi-watch = "CHROME_DEVTOOLS_AXI_HEADED=1 chrome-devtools-axi";
    };
    initContent = ''
      bindkey '^f' autosuggest-accept
    '';
  };

  # Baby Menu may recreate starter files after its managed links disappear.
  # Preserve those conflicts before Home Manager checks link targets, then let
  # the declarations below restore the authored configuration on every rebuild.
  home.activation.reconcileBabyMenuConfig = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    ${pkgs.bash}/bin/bash "${dotfilesDir}/scripts/reconcile-baby-menu-config.sh" \
      "${dotfilesDir}/files/.baby-menu" "${homeDirectory}/.baby-menu"
  '';

  # Shared authored config is symlinked from the repo on both hosts.
  # App state, credentials, and sessions remain local and unmanaged.
  home.file = {
    # Share only crew dispatch policy; other FirstMate config stays host-local.
    "github/firstmate/config/crew-dispatch.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.firstmate/crew-dispatch.json";
    ".baby-menu/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/extensions";
    ".baby-menu/agents.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/agents.json";
    ".baby-menu/preferences.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.baby-menu/preferences.json";
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/wezterm";
    ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/nvim";
    ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.config/herdr";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.claude/settings.json";
    ".codex/nix.config.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.codex/nix.config.toml";
    # grok's config.toml is small and entirely preferences - unlike Codex's,
    # its live session/trust/marketplace-cache state lives in separate files
    # under ~/.grok/, so this can be a direct full symlink.
    ".grok/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/.grok/config.toml";
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";
    ".codex/AGENTS.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/files/AGENTS.md";

    # GPG uses the Homebrew macOS Pinentry dialog. Keep this config declarative,
    # while leaving ~/.gnupg keys, sockets, and trust data unmanaged.
    ".gnupg/gpg-agent.conf" = {
      text = ''
        pinentry-program /opt/homebrew/bin/pinentry-mac
      '';
    };

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
