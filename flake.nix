{
  description = "Minimal macOS Nix setup with nix-darwin + Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, nix-darwin, home-manager, ... }:
  let
    lib = nixpkgs.lib;
    # One configuration.nix and one home.nix for every machine - identical
    # except userName/homeDirectory, the real per-account identity nix-darwin
    # needs. hostProfile only reaches home.nix (safe-maintenance.sh's
    # --profile flag); configuration.nix doesn't need it.
    mkDarwin = { hostProfile, userName, homeDirectory, includeExtras ? false }:
      nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit userName homeDirectory;
        };
        modules = [
          ./nix/configuration.nix
        ] ++ lib.optional includeExtras ./nix/camilo-extra.nix ++ [
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              inherit hostProfile userName homeDirectory;
            };
            home-manager.users.${userName}.imports = [ ./nix/home.nix ];
          }
        ];
      };
    camilo = {
      hostProfile = "camilo";
      userName = "camiloslaptop";
      homeDirectory = "/Users/camiloslaptop";
    };
    camiloRemote = {
      hostProfile = "camilo-remote";
      # Match the existing macOS account; activation cannot create its primary user.
      userName = "camilo_mini";
      homeDirectory = "/Users/camilo_mini";
    };
  in {
    # Plain targets: the shared dev baseline only, never the personal extras
    # in camilo-extra.nix. Run via ./rebuild.sh on either machine.
    darwinConfigurations.camilo = mkDarwin camilo;
    darwinConfigurations.camilo-remote = mkDarwin camiloRemote;

    # "Total" targets: the same host, plus camilo-extra.nix. Run via
    # ./rebuild-total.sh, typically only ever needed on the laptop.
    darwinConfigurations.camilo-total = mkDarwin (camilo // { includeExtras = true; });
    darwinConfigurations.camilo-remote-total = mkDarwin (camiloRemote // { includeExtras = true; });
  };
}
