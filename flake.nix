{
  description = "A Flake for Mickael Kerjean's Filestash";
  nixConfig = {
    extra-substituters = [ "https://matthewcroughan.cachix.org" ];
    extra-trusted-public-keys = [ "matthewcroughan.cachix.org-1:fON2C9BdzJlp1qPan4t5AF0xlnx8sB0ghZf8VDo7+e8=" ];
  };
  inputs = {
    filestash-src = {
      url = "github:mickael-kerjean/filestash";
      flake = false;
    };
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    dream2nix.url = "github:nix-community/dream2nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = { self, nixpkgs, flake-parts, dream2nix, filestash-src }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      flake = {
        herculesCI.ciSystems = [ "x86_64-linux" ];
        overlay = final: prev: {
          filestash = self.packages.${prev.stdenv.hostPlatform.system}.filestash;
        };
        nixosModule = { pkgs, lib, config, ... }: {
          imports = [ ./nix/filestash-module.nix ];
          nixpkgs.overlays = [ self.overlay ];
        };
        overlays = rec {
          default = filestash;
          filestash = final: prev:
            {
              filestash = final.callPackage ./pkgs/filestash {
                inherit dream2nix filestash-src self;
                pkgs = prev;
              };
            };
        };
      };
      perSystem = { config, self', inputs', pkgs, system, ... }: {
        checks = {
          filestash = pkgs.callPackage ./nix/filestash-vmtest.nix { nixosModule = self.nixosModule; };
        };
        packages = rec {
          default = filestash;
          filestash = pkgs.callPackage ./pkgs/filestash {
            inherit dream2nix pkgs filestash-src self;
          };
        };
      };
    };
}
