#!/bin/bash
set -e

# Script to create a macOS installer package (.pkg) for diff-pdf
# Optional environment variables:
#   PKG_VERSION - Version number for the package (defaults to latest git tag)
#   PKG_ID - Package identifier (e.g., "com.example.diff-pdf")
#   DEVELOPER_ID_APP - For code-signing the binary
#   DEVELOPER_ID_INSTALLER - For signing the .pkg
#   APPLE_ID - Apple ID email for notarization
#   APPLE_ID_PASSWORD - App-specific password for notarization
#   APPLE_TEAM_ID - Apple Developer Team ID for notarization

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Auto-detect PKG_VERSION from latest git tag if not set
if [ -z "$PKG_VERSION" ]; then
    PKG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")
    if [ -z "$PKG_VERSION" ]; then
        echo "Error: PKG_VERSION not set and no git tags found"
        exit 1
    fi
    echo "Auto-detected PKG_VERSION from git tag: $PKG_VERSION"
fi

if [ -z "$PKG_ID" ]; then
    echo "Error: PKG_ID environment variable is required"
    exit 1
fi

# Build the binary first
echo "Building diff-pdf binary..."
"$SCRIPT_DIR/build-cli.sh"

# Verify the binary exists
if [ ! -f "$PROJECT_ROOT/diff-pdf" ]; then
    echo "Error: diff-pdf binary not found after build"
    exit 1
fi

# Create build directory structure
BUILD_DIR="$PROJECT_ROOT/build"
PKG_ROOT="$BUILD_DIR/pkgroot"
INSTALL_DIR="$PKG_ROOT/usr/local/bin"

echo "Creating package structure..."
# Safety check before rm -rf
if [ -n "$BUILD_DIR" ] && [ "$BUILD_DIR" != "/" ] && [ "$BUILD_DIR" != "$HOME" ] && [[ "$BUILD_DIR" == */build ]]; then
    rm -rf "$BUILD_DIR"
else
    echo "Error: BUILD_DIR path appears unsafe: $BUILD_DIR"
    exit 1
fi
mkdir -p "$INSTALL_DIR"

# Copy the binary to the package root
cp "$PROJECT_ROOT/diff-pdf" "$INSTALL_DIR/"
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

# Notarize the package if Apple credentials are provided
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_ID_PASSWORD" ] && [ -n "$APPLE_TEAM_ID" ]; then
    echo "Submitting package for notarization..."
    xcrun notarytool submit "$PKG_FILE" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    echo "Stapling notarization ticket to package..."
    xcrun stapler staple "$PKG_FILE"
    echo "Package notarized and stapled successfully."
else
    echo "Apple notarization credentials not set, package left unnotarized."
    echo "To notarize, set APPLE_ID, APPLE_ID_PASSWORD, and APPLE_TEAM_ID."
fi

echo "Package created successfully: $PKG_FILE"