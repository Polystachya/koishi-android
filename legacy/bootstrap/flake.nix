{
    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    inputs.flake-utils.url = "github:numtide/flake-utils";
    inputs.nix-on-droid = {
        url = "github:t184256/nix-on-droid";
        inputs.nixpkgs.follows = "nixpkgs";
    };
    outputs = inputs@{ self, nixpkgs, flake-utils, nix-on-droid }:
        with flake-utils.lib;
    eachDefaultSystem (system: let
        pkgs = import nixpkgs {
            inherit system;
            overlays = [
                (oself: osuper: {
                    inherit inputs;
                } // (nix-on-droid.packages.${system} or {}))
            ];
        };
        aarch64-pkgs = import nixpkgs {
            system = "aarch64-linux";
        };
    in {
        packages = {
            bootstrap       = pkgs.callPackage ./bootstrap.nix {};
            bootstrap-extra = pkgs.callPackage ./bootstrap.nix { full = true; };
        };
        apps = let
            app = bootstrap: mkApp {
                drv = pkgs.writeScriptBin "copy" ''
                    FOLDER=../app/src/main/assets/bootstrap
                    mkdir -p $FOLDER
                    cp -f ${bootstrap}/* $FOLDER
                '';
            };
        in {
            copy       = app self.packages.${system}.bootstrap;
            copy-extra = app self.packages.${system}.bootstrap-extra;
        };
    });
}