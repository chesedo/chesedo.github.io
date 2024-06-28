#!/usr/bin/env sh

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
    exit 0
else
    echo "Some Rust projects failed checks."
    exit 1
fi
