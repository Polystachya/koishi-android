{
    inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    inputs.flake-utils.url = "github:numtide/flake-utils";
    inputs.anillc.url = "github:Anillc/flakes";
    inputs.nix-on-droid = {
        url = "github:Anillc/nix-on-droid";
        inputs.nixpkgs.follows = "nixpkgs";
    };
    outputs = inputs@{ self, nixpkgs, flake-utils, anillc, nix-on-droid }:
        with flake-utils.lib;
    eachDefaultSystem (system: let
        # 原生构建主机的包（用于 copy 脚本等构建时工具）
        nativePkgs = import nixpkgs {
            inherit system;
        };
        
        # 目标平台的包（用于 bootstrap，包含 Android/ARM64 相关的包）
        # 注意：bootstrap 中的内容最终要在 Android ARM64 设备上运行
        targetSystem = "aarch64-linux";
        pkgs = import nixpkgs {
            system = targetSystem;
            overlays = [
                (oself: osuper: 
                    (anillc.packages.${targetSystem} or {})
                    // (nix-on-droid.packages.${targetSystem} or {})
                    // {
                        inherit inputs;
                    })
            ];
        };
    in {
        packages = {
            bootstrap       = pkgs.callPackage ./bootstrap.nix {};
            bootstrap-extra = pkgs.callPackage ./bootstrap.nix { full = true; };
        };
        apps = let
            # 使用 nativePkgs 来创建 copy 脚本，确保它能在构建主机上运行
            app = bootstrap: mkApp {
                drv = nativePkgs.writeScriptBin "copy" ''
                    #!${nativePkgs.bash}/bin/bash
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
