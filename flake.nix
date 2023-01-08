{
  description = "Nix flake to package and modularize the freescout-helpdesk software";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    (flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          self.overlays.default
        ];
      };
    in rec {
      packages.freescout = pkgs.freescout;
      packages.default = packages.freescout;
      packages.nixosTests.freescout = pkgs.nixosTests.freescout;
      packages.dev-vm = (nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        modules = [
          self.nixosModules.freescout
          ./dev-vm.nix
        ];
      }).config.system.build.vm;
    })) // {
      nixosModules.freescout = import ./module.nix;
      overlays.default = (final: prev: rec {
        freescout = final.callPackage ./package.nix {};
        nixosTests.freescout = final.callPackage ./tests.nix {
          outputs = self;
        };
      });
    };
}
