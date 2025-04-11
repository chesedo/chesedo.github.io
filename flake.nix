{
  description = "Chesedo's portfolio website and blog";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShell.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            chromium
            kondo
            nodejs
            zola
          ];
        };
      }
    );
}
