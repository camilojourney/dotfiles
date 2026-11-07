# One allowlist owns both the Home Manager links and legacy-state relocation.
{ name, source, target, files }:
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
      ${lib.escapeShellArg sourceDir} ${lib.escapeShellArg targetDir} \
      ${lib.escapeShellArgs files}
  '';
}
