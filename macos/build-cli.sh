#!/bin/bash
set -e

# Script to build diff-pdf CLI binary on macOS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Bootstrap if needed (only required when building from git)
if [ ! -f configure ]; then
    echo "Running bootstrap..."
    ./bootstrap
fi

# Configure the build
echo "Configuring..."
./configure

# Build the binary
echo "Building diff-pdf..."
make

echo "Build complete. Binary is at: $PROJECT_ROOT/diff-pdf"