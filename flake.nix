{
  description = "NixOS tests example";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    {
      nixosModules = {
        phare = import ./module/default.nix;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlay = final: prev: {
          helloNixosTests = self.packages.${system}.helloNixosTests;
        };
        pkgs = nixpkgs.legacyPackages.${system}.extend overlay;
      in
      {
        checks = {
          helloNixosTest = pkgs.callPackage ./phare-boots.nix { inherit self; };
        };
        packages = {
          phareNixDocs = pkgs.callPackage ./docs/doc.nix { inherit self; };
          helloNixosTests = pkgs.writeScriptBin "hello-nixos-tests" ''
            systemctl start create-phare-monitors
          '';
        };
      }
    );
}
