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
    in {
      packages.freescout = pkgs.freescout;
      packages.tests = import ./tests.nix {
        inherit pkgs system;
        outputs = self;
      };
      packages.test-vm = (nixpkgs.lib.nixosSystem {
        inherit system pkgs;
        modules = [
          self.nixosModules.freescout
          ./test-vm.nix
        ];
      }).config.system.build.vm;
    })) // {
      nixosModules.freescout = import ./module.nix;
      overlays.default = (final: prev: rec {
        freescout = final.callPackage ./package.nix {};
      });
    };
}
