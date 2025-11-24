#!/bin/bash
set -e

# Script to build diff-pdf CLI binary on macOS
# Optional: Set DEVELOPER_ID_APP environment variable to code-sign the binary

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

# Code-sign if DEVELOPER_ID_APP is provided
if [ -n "$DEVELOPER_ID_APP" ]; then
    echo "Code-signing diff-pdf binary with: $DEVELOPER_ID_APP"
    codesign --force --sign "$DEVELOPER_ID_APP" --timestamp --options runtime diff-pdf
    echo "Binary signed successfully."
else
    echo "DEVELOPER_ID_APP not set, binary left unsigned."
fi

echo "Build complete. Binary is at: $PROJECT_ROOT/diff-pdf"