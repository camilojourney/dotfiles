{ config, lib, homeDirectory, hostProfile, ... }:

let
  repoRoot = "${homeDirectory}/github/dotfiles";
  reconcileScript = "${repoRoot}/scripts/agent-tools/reconcile.sh";
in
{
  options.agentTools = {
    enable = lib.mkEnableOption "declarative agent/developer CLI inventory";
    hostProfile = lib.mkOption {
      type = lib.types.enum [ "camilo" "camilo-remote" ];
      description = "Host overlay profile controlling host-specific inventory slices.";
    };
    manifestPath = lib.mkOption {
      type = lib.types.path;
      default = ./manifest.lock.json;
      description = "Agent tool manifest (latest npm channels, pinned pipx and external bootstraps, and external self-updaters).";
    };
  };

  config = lib.mkIf config.agentTools.enable {
    home.sessionPath = [
      "${homeDirectory}/.local/bin"
      "${homeDirectory}/.no-mistakes/bin"
    ];

    home.activation.installAgentTools = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      export PATH="/opt/homebrew/bin:$PATH"
      if [ ! -x "${reconcileScript}" ]; then
        echo "installAgentTools: reconcile script missing at ${reconcileScript}" >&2
        exit 1
      fi
      AGENT_TOOLS_MANIFEST="${config.agentTools.manifestPath}" "${reconcileScript}" "${config.agentTools.hostProfile}"
    '';

    home.activation.updatePiPackages = lib.hm.dag.entryAfter [ "installAgentTools" ] ''
      export PATH="/opt/homebrew/bin:$PATH"
      pi update --extensions
    '';
  };
}
