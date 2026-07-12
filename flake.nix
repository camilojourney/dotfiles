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
    mkDarwin = { hostModule, userModule, userName, homeDirectory }:
      nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = {
          inherit userName homeDirectory;
        };
        modules = [
          ./nix/shared/host.nix
          hostModule
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              inherit userName homeDirectory;
            };
            home-manager.users = {
              ${userName} = {
                imports = [ ./nix/shared/user.nix userModule ];
              };
            };
          }
        ];
      };
  in {
    darwinConfigurations.camilo = mkDarwin {
      hostModule = ./nix/camilo/host.nix;
      userModule = ./nix/camilo/user.nix;
      userName = "camiloslaptop";
      homeDirectory = "/Users/camiloslaptop";
    };
    darwinConfigurations.camilo-mini = mkDarwin {
      hostModule = ./nix/camilo-mini/host.nix;
      userModule = ./nix/camilo-mini/user.nix;
      userName = "mini";
      homeDirectory = "/Users/mini";
    };
  };
}
