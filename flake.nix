{
  description = "Chesedo's portfolio website and blog";

  # Define our external dependencies
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable"; # Latest nixpkgs for up-to-date packages
    flake-utils.url = "github:numtide/flake-utils";      # Utilities for making flakes easier to work with
  };

  # Define the outputs for our flake, which will be created for each default system
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Get the packages for the current system
        pkgs = nixpkgs.legacyPackages.${system};

        # Define all our scripts in a single structured list
        # This makes it easy to add/modify scripts in one place
        scriptDefs = [
          {
            name = "serve";                                   # Command name for apps
            filename = "zola-serve";                          # Actual script filename
            description = "Serve the files using zola and watch for changes";
            script = ''${pkgs.zola}/bin/zola serve'';         # The actual script content
          }
          {
            name = "css-watch";
            filename = "tailwindcss-watch";
            description = "Watch for changes in CSS files and rebuild";
            script = ''${pkgs.nodejs}/bin/node ./node_modules/.bin/tailwindcss -i input.css -o static/css/styles.css --watch'';
          }
          {
            name = "start-kroki";
            filename = "start-kroki";
            description = "Start the Kroki server using podman-compose";
            script = ''podman-compose up -d'';
          }
          {
            name = "build";
            filename = "build";
            description = "Build the website using zola and build the assets";
            script = ''
              cp node_modules/sandy-image/sandy* ./static/
              ${pkgs.nodejs}/bin/node ./node_modules/.bin/tailwindcss -i input.css -o static/css/styles.css --minify
              ${pkgs.zola}/bin/zola build
            '';
          }
          {
            name = "clean";
            filename = "clean";
            description = "Clean up any development files and targets";
            script = ''
              ${pkgs.kondo}/bin/kondo --all content
              podman-compose down
            '';
          }
        ];

        # Create a single derivation containing all our scripts
        # This avoids creating a separate store entry for each script
        scriptUtils = pkgs.runCommand "scripts" {} (
          ''
            mkdir -p $out/bin
          '' +
          (builtins.concatStringsSep "\n" (
            builtins.map (def: ''
              cat > $out/bin/${def.filename} << 'EOF'
              #!/usr/bin/env sh

              ${def.script}
              EOF
              chmod +x $out/bin/${def.filename}
            '') scriptDefs
          ))
        );

        # Fetch npm dependencies ahead of time for reproducible builds
        # This allows offline builds and improves build determinism
        npmDeps = pkgs.fetchNpmDeps {
          src = self;
          hash = "sha256-TotRbj3P3HdWEE3mnx+Llx9nTdND8sw1M6UnEAfUBnM=";
        };

        # The main website derivation that builds the complete site
        website = pkgs.stdenv.mkDerivation {
          name = "chesedo-website";
          src = self;

          buildInputs = with pkgs; [
            nodejs  # Needed for npm and node
            zola    # Static site generator
          ];

          buildPhase = ''
            # Use the pre-fetched npm dependencies
            export npm_config_cache=${npmDeps}

            # Install dependencies from the cache (offline)
            ${pkgs.nodejs}/bin/npm ci --offline

            # Use our build script to build the site
            ${scriptUtils}/bin/build
          '';

          installPhase = ''
            # Copy the built website to the output directory
            mkdir -p $out
            cp -r ./public/* $out/
          '';
        };
      in
      {
        # Define a development shell with all needed tools
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            chromium  # For lighthouse testing
            kondo     # For cleaning up content
            nodejs    # For npm/node
            zola      # For site generation
          ];

          # Show helpful information when entering the shell
          shellHook = ''
            echo -e "\033[1;36m=== Welcome to the Chesedo Website Development Shell ===\033[0m"
            echo ""
            echo -e "\033[1;33mAvailable commands:\033[0m"
            echo ""
            echo -e "\033[1;32m# Development workflow\033[0m"
            echo -e "  \033[1;37mnix run\033[0m - Start the full development environment (Zola + Tailwind + Kroki)"

            ${builtins.concatStringsSep "\n" (
              builtins.map (def: ''
                echo -e "  \033[1;37mnix run .#${def.name}\033[0m - ${def.description}"
              '') scriptDefs
            )}

            echo ""
            echo -e "\033[1;32m# Useful development tips:\033[0m"
            echo -e "  • View your site at \033[4;94mhttp://127.0.0.1:1111\033[0m"
            echo -e "  • Press Ctrl+C to stop the development servers"
            echo -e "  • Run \033[1;37mnix build --no-sandbox\033[0m to build the production version of the site"
            echo -e "  • Run \033[1;37mnix flake check --no-sandbox\033[0m to verify everything builds correctly"
            echo ""
          '';
        };

        # Set the default package to our website
        packages.default = website;

        # Define various checks to ensure the website is valid
        checks = {
          # Check that zola can successfully parse the site
          zola = pkgs.runCommand "zola-check" {
            buildInputs = [ pkgs.zola ];
          } ''
            # Copy source to a temporary directory
            cp -r ${self} ./source
            cd ./source

            # Run Zola's built-in check command
            ${pkgs.zola}/bin/zola check

            touch $out
          '';

          # Run lighthouse performance tests
          lh = pkgs.runCommand "lighthouse-check" {
            buildInputs = with pkgs; [
              nodejs
              chromium

              # Needed to upload results
              cacert
            ];

            # Needed for chromium to start correctly
            CHROME_PATH = "${pkgs.chromium}/bin/chromium";
            XDG_CONFIG_HOME = "/tmp/.config";

            # Needed for upload to work correctly
            LHCI_BUILD_CONTEXT__CURRENT_HASH="nix-build";
          } ''
            # Copy source with writable permissions
            cp -r ${self} ./source
            chmod -R +w ./source
            cd ./source

            # Use the pre-fetched npm dependencies
            export npm_config_cache=${npmDeps}

            # Install dependencies from the cache (offline)
            ${pkgs.nodejs}/bin/npm ci --offline

            # Copy website to public directory
            cp -r ${website} ./public

            ${pkgs.nodejs}/bin/node ./node_modules/.bin/lhci autorun

            cp -r ./.lighthouseci $out
          '';

          # Check that all Rust code examples in content compile
          content = pkgs.runCommand "check-content" {
            buildInputs = [ pkgs.cargo ];
          } ''
            # Copy source to a temporary directory
            cp -r ${self} ./source
            cd ./source

            # Set the content directory
            CONTENT_DIR="content"

            # Initialize a flag to track overall success
            all_passed=true

            # Function to run cargo check in a directory
            check_directory() {
                local dir=$1
                (
                    cd "$dir" || return 1
                    if cargo clippy --quiet -- -D warnings; then
                        echo "✓ Project in $dir passed"
                        return 0
                    else
                        echo "✗ Project in $dir failed"
                        return 1
                    fi
                )
            }

            # Find all directories containing a Cargo.toml file and check them
            find "$CONTENT_DIR" -name "Cargo.toml" | while IFS= read -r cargo_file
            do
                dir=$(dirname "$cargo_file")
                if ! check_directory "$dir"; then
                    all_passed=false
                fi
            done

            echo ""

            if $all_passed; then
                echo "All Rust projects passed checks!"
            else
                echo "Some Rust projects failed checks."
                exit 1
            fi

            touch $out
          '';
        };

        # Define runnable apps for our website development tasks
        apps = rec {
          # Special combined app that runs multiple scripts in parallel
          dev = flake-utils.lib.mkApp {
            drv = pkgs.writeShellScriptBin "dev" ''
              ${scriptUtils}/bin/start-kroki

              # Function to cleanup on exit
              cleanup() {
                kill $ZOLA_PID 2>/dev/null
                echo "Development servers stopped."
              }
              trap cleanup EXIT

              # Start Zola in the background with colored output
              echo -e "\033[0;32m[ZOLA]\033[0m Starting Zola server..."
              ${scriptUtils}/bin/zola-serve 2>&1 | ${pkgs.gawk}/bin/awk '{ print "\033[0;32m[ZOLA]\033[0m " $0 }' &
              ZOLA_PID=$!

              # Prefix Tailwind output with colored tag
              echo -e "\033[0;34m[TAILWIND]\033[0m Starting Tailwind CSS watcher..."
              exec ${scriptUtils}/bin/tailwindcss-watch 2>&1 | ${pkgs.gawk}/bin/awk '{ print "\033[0;34m[TAILWIND]\033[0m " $0 }'
            '';
          };
          default = dev;
        } //
        # Automatically generate apps from our script definitions
        builtins.listToAttrs (
          builtins.map (def: {
            name = def.name;
            value = flake-utils.lib.mkApp {
              drv = pkgs.writeShellScriptBin def.filename ''
                ${scriptUtils}/bin/${def.filename}
              '';
            };
          }) scriptDefs
        );
      }
    );
}
