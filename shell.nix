let
  moz_overlay = import (builtins.fetchTarball
    "https://github.com/mozilla/nixpkgs-mozilla/archive/master.tar.gz");
  # Pin to stable from https://status.nixos.org/
  nixpkgs = import (fetchTarball
    "https://github.com/NixOS/nixpkgs/archive/752c634c09ceb50c45e751f8791cb45cb3d46c9e.tar.gz") {
      overlays = [ moz_overlay ];
    };
in with nixpkgs;
stdenv.mkDerivation {
  name = "moz_overlay_shell";
  buildInputs = with nixpkgs; [
    ((rustChannelOf { channel = "1.79.0"; }).rust.override {
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
