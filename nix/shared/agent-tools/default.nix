{ config, lib, homeDirectory, hostProfile, ... }:

let
  repoRoot = "${homeDirectory}/github/dotfiles";
  reconcileScript = "${repoRoot}/scripts/agent-tools/reconcile.sh";
in
{
  options.agentTools = {
    enable = lib.mkEnableOption "declarative agent/developer CLI inventory";
    hostProfile = lib.mkOption {
      type = lib.types.enum [ "camilo" "camilo-mini" ];
      description = "Host overlay profile controlling host-specific inventory slices.";
    };
    manifestPath = lib.mkOption {
      type = lib.types.path;
      default = ./manifest.lock.json;
      description = "Pinned agent tool manifest (versions + external sha256).";
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
      "${reconcileScript}" "${config.agentTools.hostProfile}"
    '';
  };
}
