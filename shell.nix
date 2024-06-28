{ pkgs ? import <nixpkgs> {} }:

with pkgs;

mkShell {
  buildInputs = [
    cargo
    chromium
    clippy
    kondo
    nodejs
    zola
  ];
}
