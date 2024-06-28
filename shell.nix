{ pkgs ? import <nixpkgs> {} }:

with pkgs;

mkShell {
  buildInputs = [
    cargo
    clippy
    kondo
    nodejs
    zola
  ];
}
