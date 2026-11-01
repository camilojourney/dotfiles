# Pin policy lives here rather than changing the user's actively edited home.nix.
{ config, lib, pkgs, homeDirectory, ... }:
let
  dotfilesDir = "${homeDirectory}/github/dotfiles";
  effectiveSettings = "${homeDirectory}/.local/state/agent-tools/pi-settings.json";
in {
  home.sessionVariables.PI_SKIP_VERSION_CHECK = "1";

  # Preserve authored settings (and uncommitted preferences). Pi operates on a
  # writable effective copy with the manifest's npm pins applied. Pi preference
  # writes cannot mutate the git source through this link.
  home.file.".pi/agent/settings.json".source = lib.mkForce
    (config.lib.file.mkOutOfStoreSymlink effectiveSettings);
  home.activation.preparePinnedPiSettings = lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
    PATH="$PATH:/opt/homebrew/bin:/usr/bin:/bin" ${pkgs.python3}/bin/python3 \
      "${dotfilesDir}/scripts/agent-tools/toolchain.py" render \
      --manifest "${./agent-tools.manifest.lock.json}" --output "${effectiveSettings}"
  '';

  # reconcile.sh owns extension installation too. Never run an independent
  # unbounded Pi updater or the former local quota-axi reinstall after pins.
  home.activation.updatePiPackages = lib.mkForce
    (lib.hm.dag.entryAfter [ "installAgentTools" ] "");
  home.activation.quotaAxiAgyFix = lib.mkForce
    (lib.hm.dag.entryAfter [ "installAgentTools" ] "");
}
