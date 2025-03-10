let
  moz_overlay = import (builtins.fetchTarball
    "https://github.com/mozilla/nixpkgs-mozilla/archive/master.tar.gz");
  # Pin to stable from https://status.nixos.org/
  nixpkgs = import (fetchTarball
    "https://github.com/NixOS/nixpkgs/archive/52e3095f6d812b91b22fb7ad0bfc1ab416453634.tar.gz") {
      overlays = [ moz_overlay ];
    };
in with nixpkgs;
stdenv.mkDerivation {
  name = "moz_overlay_shell";
  buildInputs = with nixpkgs; [
    ((rustChannelOf { channel = "1.85.0"; }).rust.override {
      extensions = [ "rust-src" ];
    })
    cargo-watch
    chromium
    clippy
    kondo
    nodejs
    zola
  ];
}
