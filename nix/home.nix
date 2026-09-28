{ config, pkgs, lib, userName, homeDirectory, hostProfile, ... }:

let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
  # Obsidian vault lives in iCloud; stable path for Pi and other agents.
  # Declared on every machine - harmless where Obsidian/iCloud sync for this
  # vault isn't present yet (nix/camilo-extra.nix, via ./rebuild-total.sh),
  # it just sits as an unused symlink until they are.
  vaultPath =
    "${config.home.homeDirectory}/Library/Mobile Documents/iCloud~md~obsidian/Documents/My Vault";
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
  home.sessionPath = [
    "${homeDirectory}/.local/bin"
    "${homeDirectory}/.no-mistakes/bin"
  ];

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
      # One script for both hosts: rebuild.sh detects the account and picks
      # the right flake attr, so this alias never needs a host override.
      rebuild = "~/github/dotfiles/rebuild.sh";
      # Same persistent profile as chrome-devtools-axi's default, but with a
      # visible window so a running automation can be watched/debugged live.
      axi-watch = "CHROME_DEVTOOLS_AXI_HEADED=1 chrome-devtools-axi";
      storage-report = "bash ~/github/dotfiles/scripts/storage-report.sh";
      # hostProfile picks the safe-maintenance profile for this account.
      safe-maintenance = "~/github/dotfiles/scripts/safe-maintenance.sh --profile ${hostProfile}";
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
      "${dotfilesDir}/home/.baby-menu" "${homeDirectory}/.baby-menu"
  '';

  # Identical authored config symlinked from the repo on every machine.
  # App state, credentials, and sessions remain local and unmanaged.
  home.file = {
    # Share only crew dispatch policy; other FirstMate config stays host-local.
    "github/firstmate/config/crew-dispatch.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.firstmate/crew-dispatch.json";
    ".baby-menu/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.baby-menu/extensions";
    ".baby-menu/agents.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.baby-menu/agents.json";
    ".baby-menu/preferences.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.baby-menu/preferences.json";
    ".config/wezterm".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.config/wezterm";
    ".config/nvim".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.config/nvim";
    ".config/herdr".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.config/herdr";
    ".claude/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.claude/settings.json";
    ".claude/CLAUDE.md".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/AGENTS.md";

    # GPG uses the Homebrew macOS Pinentry dialog. Keep this config declarative,
    # while leaving ~/.gnupg keys, sockets, and trust data unmanaged.
    ".gnupg/gpg-agent.conf" = {
      text = ''
        pinentry-program /opt/homebrew/bin/pinentry-mac
      '';
    };

    # Pi (kunchenguid-aligned): only authored config/theme/extensions.
    # Runtime (auth, sessions, ~/.pi/agent/npm|git) stays unmanaged.
    ".pi/agent/themes".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/agent/themes";
    ".pi/agent/extensions".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/agent/extensions";
    ".pi/agent/models.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/agent/models.json";
    ".pi/agent/settings.json".source = config.lib.file.mkOutOfStoreSymlink "${dotfilesDir}/home/.pi/agent/settings.json";

    "github/vault".source = config.lib.file.mkOutOfStoreSymlink vaultPath;
  };

  # Required agent/developer CLIs (npm globals, uv tool apps, pinned external
  # release archives): declared in nix/agent-tools.manifest.lock.json,
  # reconciled by this script on every rebuild. One manifest, every machine.
  #
  # Runs after linkGeneration (not just writeBoundary): some tools' setup
  # hooks read ~/.claude/settings.json, which linkGeneration is what actually
  # creates/updates. Running before it meant those hooks read a symlink still
  # pointing at the previous generation - stale or, after a source file
  # rename, outright missing.
  # Appends (not prepends) /usr/bin and /opt/homebrew/bin: this activation
  # block runs in the same shell as later stock home-manager steps (e.g.
  # setupLaunchAgents), which depend on Nix's GNU coreutils (already earlier
  # in $PATH) for flags like `readlink -m` that BSD's /usr/bin/readlink
  # doesn't support. Prepending shadowed those and broke setupLaunchAgents.
  home.activation.installAgentTools = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    export PATH="$PATH:/opt/homebrew/bin:/usr/bin:/bin"
    reconcileScript="${dotfilesDir}/scripts/agent-tools/reconcile.sh"
    if [ ! -x "$reconcileScript" ]; then
      echo "installAgentTools: reconcile script missing at $reconcileScript" >&2
      exit 1
    fi
    AGENT_TOOLS_MANIFEST="${./agent-tools.manifest.lock.json}" "$reconcileScript"
  '';

  home.activation.updatePiPackages = lib.hm.dag.entryAfter [ "installAgentTools" ] ''
    export PATH="$PATH:/opt/homebrew/bin:/usr/bin:/bin"
    pi update --extensions
  '';
}
