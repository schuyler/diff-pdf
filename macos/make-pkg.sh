#!/bin/bash
set -e

# Script to create a macOS installer package (.pkg) for diff-pdf
# Required environment variables:
#   PKG_VERSION - Version number for the package (e.g., "1.0.0")
#   PKG_ID - Package identifier (e.g., "com.example.diff-pdf")
# Optional environment variables:
#   DEVELOPER_ID_APP - For code-signing the binary
#   DEVELOPER_ID_INSTALLER - For signing the .pkg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check required environment variables
if [ -z "$PKG_VERSION" ]; then
    echo "Error: PKG_VERSION environment variable is required"
    exit 1
fi

if [ -z "$PKG_ID" ]; then
    echo "Error: PKG_ID environment variable is required"
    exit 1
fi

cd "$PROJECT_ROOT"

# Build the binary first
echo "Building diff-pdf binary..."
"$SCRIPT_DIR/build-cli.sh"

# Create build directory structure
BUILD_DIR="$PROJECT_ROOT/build"
PKG_ROOT="$BUILD_DIR/pkgroot"
INSTALL_DIR="$PKG_ROOT/usr/local/bin"

echo "Creating package structure..."
rm -rf "$BUILD_DIR"
mkdir -p "$INSTALL_DIR"

# Copy the binary to the package root
cp diff-pdf "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/diff-pdf"

# Build the package
PKG_FILE="$BUILD_DIR/diff-pdf-${PKG_VERSION}.pkg"
echo "Creating package: $PKG_FILE"

pkgbuild --root "$PKG_ROOT" \
         --identifier "$PKG_ID" \
         --version "$PKG_VERSION" \
         --install-location "/" \
         "$PKG_FILE"

# Sign the package if DEVELOPER_ID_INSTALLER is provided
if [ -n "$DEVELOPER_ID_INSTALLER" ]; then
    echo "Signing package with: $DEVELOPER_ID_INSTALLER"
    SIGNED_PKG="$BUILD_DIR/diff-pdf-${PKG_VERSION}-signed.pkg"
    productsign --sign "$DEVELOPER_ID_INSTALLER" "$PKG_FILE" "$SIGNED_PKG"
    mv "$SIGNED_PKG" "$PKG_FILE"
    echo "Package signed successfully."
else
    echo "DEVELOPER_ID_INSTALLER not set, package left unsigned."
fi

echo "Package created successfully: $PKG_FILE"