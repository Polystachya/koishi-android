{ pkgs, buildEnv, callPackage, lib, inputs, full ? false }:
with builtins;
with lib;
let
    login = callPackage ./login.nix {};
    env = callPackage ./env.nix { inherit (pkgs) busybox; };
    fonts = callPackage ./fonts.nix {};
    certs = callPackage ./certs.nix {};
    timezone = callPackage ./timezone.nix {};
in buildEnv {
    name = "koishi-env";
    # dns is in login.nix
    paths = with pkgs; [
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
