# One allowlist owns both the Home Manager links and legacy-state relocation.
# adoptAppChanges: for apps that replace a config symlink with a real file on every
# save (OBS). Their newer file is taken into the repository, both versions are kept.
{ name, source, target, files, adoptAppChanges ? false }:
{ config, lib, pkgs, ... }:
let
  dotfilesDir = "${config.home.homeDirectory}/github/dotfiles";
  sourceDir = "${dotfilesDir}/${source}";
  targetDir = "${config.home.homeDirectory}/${target}";
in
{
  home.file = lib.listToAttrs (map (file: {
    name = "${target}/${file}";
    value.source = config.lib.file.mkOutOfStoreSymlink "${sourceDir}/${file}";
  }) files);

  # Old generations linked the entire app directory into the checkout. Detach
  # that parent before Home Manager checks children, retaining host-local state.
  home.activation."separateConfigState-${name}" = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    run ${pkgs.python3}/bin/python3 "${dotfilesDir}/scripts/separate-config-state.py" \
      ${lib.optionalString adoptAppChanges "--adopt-app-changes "}${lib.escapeShellArg sourceDir} ${lib.escapeShellArg targetDir} \
      ${lib.escapeShellArgs files}
  '';
}
