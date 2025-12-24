{ pkgs, buildEnv, callPackage, lib, inputs, full ? false }:
with builtins;
with lib;
let
    # 修复：使用当前系统架构的包，避免交叉编译
    # aarch64-pkgs = import inputs.nixpkgs { system = "aarch64-linux"; };
    login = callPackage ./login.nix {};
    env = callPackage ./env.nix { inherit (pkgs) busybox; };
    fonts = callPackage ./fonts.nix {};
    certs = callPackage ./certs.nix {};
    timezone = callPackage ./timezone.nix {};
in buildEnv {
    name = "koishi-env";
    # dns is in login.nix
    paths = with pkgs; [  # ✅ 使用当前系统架构 (x86_64)
        login env
        certs
        busybox zip
        nodejs_20
    ] ++ (optionals full [
        fonts
        chromium
        timezone
    ]);
}