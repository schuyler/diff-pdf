#!/bin/bash
set -e

# Script to create a macOS installer package (.pkg) for diff-pdf
# Optional environment variables:
#   PKG_VERSION - Version number for the package (defaults to latest git tag)
#   PKG_ID - Package identifier (e.g., "com.example.diff-pdf")
#   DEVELOPER_ID_APP - For code-signing the binary and bundled libraries
#   DEVELOPER_ID_INSTALLER - For signing the .pkg
#   APPLE_ID - Apple ID email for notarization
#   APPLE_ID_PASSWORD - App-specific password for notarization
#   APPLE_TEAM_ID - Apple Developer Team ID for notarization

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Function to recursively collect all dependencies of a dylib/binary
collect_dependencies() {
    local file="$1"
    local collected_file="$2"

    # Get all dependencies (skip system libraries)
    otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
        # Skip system libraries and already processed files
        if [[ "$dep" == /System/* ]] || [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == @* ]]; then
            continue
        fi

        # Check if we've already collected this dependency
        if grep -q "^${dep}$" "$collected_file" 2>/dev/null; then
            continue
        fi

        # Also check if we've collected the resolved symlink target
        if [ -L "$dep" ]; then
            local resolved_dep=$(readlink -f "$dep" 2>/dev/null || readlink "$dep" 2>/dev/null || echo "$dep")
            if grep -q "^${resolved_dep}$" "$collected_file" 2>/dev/null; then
                continue
            fi
        fi

        # Add to collected list
        echo "$dep" >> "$collected_file"

        # Track if dependency doesn't exist
        if [ ! -f "$dep" ]; then
            echo "WARNING: Dependency not found: $dep" >&2
            echo "$dep" >> "${collected_file}.missing"
            continue
        fi

        # Recursively collect dependencies of this library
        collect_dependencies "$dep" "$collected_file"
    done
}

# Function to rewrite library paths in a binary/dylib
rewrite_paths() {
    local file="$1"
    local lib_dir="$2"

    # Only update install name for dylibs, not executables
    if [[ "$file" == *.dylib ]]; then
        local install_name=$(otool -D "$file" 2>/dev/null | sed -n '2p')
        if [[ -n "$install_name" ]] && [[ "$install_name" != "$file" ]]; then
            local lib_name=$(basename "$install_name")
            install_name_tool -id "@executable_path/../lib/diff-pdf/$lib_name" "$file"
        fi
    fi

    # Collect all dependencies into array first to avoid race condition
    local deps=()
    while IFS= read -r dep; do
        # Skip system libraries and already rewritten paths
        if [[ "$dep" == /System/* ]] || [[ "$dep" == /usr/lib/* ]] || [[ "$dep" == @* ]]; then
            continue
        fi
        deps+=("$dep")
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}')

    # Now rewrite paths
    for dep in "${deps[@]}"; do
        local dep_name=$(basename "$dep")
        local new_path="@executable_path/../lib/diff-pdf/$dep_name"

        # Check if the dependency exists in our lib directory
        if [ -f "$lib_dir/$dep_name" ]; then
            install_name_tool -change "$dep" "$new_path" "$file"
        fi
    done
}

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
LIB_DIR="$PKG_ROOT/usr/local/lib/diff-pdf"

echo "Creating package structure..."
# Safety check before rm -rf
if [ -n "$BUILD_DIR" ] && [ "$BUILD_DIR" != "/" ] && [ "$BUILD_DIR" != "$HOME" ] && [[ "$BUILD_DIR" == */build ]]; then
    rm -rf "$BUILD_DIR"
else
    echo "Error: BUILD_DIR path appears unsafe: $BUILD_DIR"
    exit 1
fi
mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR"

# Copy the binary to the package root
echo "Copying binary..."
cp "$PROJECT_ROOT/diff-pdf" "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/diff-pdf"

# Collect all dependencies
echo "Collecting dependencies..."
DEPS_FILE="$BUILD_DIR/dependencies.txt"
collect_dependencies "$PROJECT_ROOT/diff-pdf" "$DEPS_FILE"

# Check for missing dependencies
if [ -f "${DEPS_FILE}.missing" ]; then
    echo "ERROR: Missing dependencies detected:"
    cat "${DEPS_FILE}.missing"
    exit 1
fi

# Copy all dependencies to lib directory, preserving symlinks
if [ -f "$DEPS_FILE" ]; then
    echo "Bundling dependencies..."
    while read -r dep; do
        if [ -f "$dep" ] || [ -L "$dep" ]; then
            local dep_name=$(basename "$dep")

            # Copy with -P to preserve symlinks
            cp -P "$dep" "$LIB_DIR/"

            # If it's a symlink, also copy the target
            if [ -L "$dep" ]; then
                local target=$(readlink "$dep")
                # Handle both absolute and relative symlink targets
                if [[ "$target" = /* ]]; then
                    # Absolute path
                    if [ -f "$target" ]; then
                        cp "$target" "$LIB_DIR/" 2>/dev/null || true
                    fi
                else
                    # Relative path
                    local target_path="$(dirname "$dep")/$target"
                    if [ -f "$target_path" ]; then
                        cp "$target_path" "$LIB_DIR/" 2>/dev/null || true
                    fi
                fi
            fi

            chmod 644 "$LIB_DIR/$dep_name" 2>/dev/null || true
        fi
    done < "$DEPS_FILE"
fi

# Make libraries writable for install_name_tool
chmod -R u+w "$LIB_DIR"

# Rewrite paths in the main binary
echo "Rewriting library paths in binary..."
rewrite_paths "$INSTALL_DIR/diff-pdf" "$LIB_DIR"

# Rewrite paths in all bundled libraries
echo "Rewriting library paths in bundled libraries..."
for lib in "$LIB_DIR"/*.dylib; do
    if [ -f "$lib" ] && [ ! -L "$lib" ]; then
        rewrite_paths "$lib" "$LIB_DIR"
    fi
done

# Verify all paths were rewritten correctly
echo "Verifying library paths..."
for binary in "$INSTALL_DIR/diff-pdf" "$LIB_DIR"/*.dylib; do
    if [ -f "$binary" ] && [ ! -L "$binary" ]; then
        if otool -L "$binary" | grep -E '/(opt/homebrew|usr/local/Cellar)/' >/dev/null; then
            echo "ERROR: Found unrewritten Homebrew paths in $(basename "$binary")"
            otool -L "$binary" | grep -E '/(opt/homebrew|usr/local/Cellar)/'
            exit 1
        fi
    fi
done
echo "All library paths verified successfully."

# Set final permissions on libraries before signing
chmod -R u-w,go-w "$LIB_DIR"

# Code-sign all bundled libraries and the binary
if [ -n "$DEVELOPER_ID_APP" ]; then
    echo "Code-signing bundled libraries..."
    for lib in "$LIB_DIR"/*.dylib; do
        if [ -f "$lib" ] && [ ! -L "$lib" ]; then
            codesign --force --sign "$DEVELOPER_ID_APP" --timestamp --options runtime "$lib"
        fi
    done

    echo "Code-signing binary..."
    codesign --force --sign "$DEVELOPER_ID_APP" --timestamp --options runtime "$INSTALL_DIR/diff-pdf"
    echo "All binaries signed successfully."
else
    echo "DEVELOPER_ID_APP not set, binaries left unsigned."
fi

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