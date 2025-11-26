#!/bin/bash
set -e

# Script to upload the diff-pdf .pkg to GitHub as a release
# Requires: gh CLI (https://cli.github.com/)
# Optional environment variables:
#   PKG_VERSION - Version number (defaults to latest git tag)
#   RELEASE_NOTES - Release notes text (defaults to "Release $PKG_VERSION")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Check for gh CLI
if ! command -v gh &> /dev/null; then
    echo "Error: gh CLI is not installed"
    echo "Install it from https://cli.github.com/"
    exit 1
fi

# Check gh authentication
if ! gh auth status &> /dev/null; then
    echo "Error: gh CLI is not authenticated"
    echo "Run 'gh auth login' to authenticate"
    exit 1
fi

# Auto-detect PKG_VERSION from latest git tag if not set
if [ -z "$PKG_VERSION" ]; then
    PKG_VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")
    if [ -z "$PKG_VERSION" ]; then
        echo "Error: PKG_VERSION not set and no git tags found"
        exit 1
    fi
    echo "Auto-detected PKG_VERSION from git tag: $PKG_VERSION"
fi

# Determine tag name (add 'v' prefix if not present in original tag)
TAG_NAME=$(git describe --tags --abbrev=0 2>/dev/null || echo "v$PKG_VERSION")

# Check for the .pkg file
BUILD_DIR="$PROJECT_ROOT/build"
PKG_FILE="$BUILD_DIR/diff-pdf-${PKG_VERSION}.pkg"

if [ ! -f "$PKG_FILE" ]; then
    echo "Error: Package file not found: $PKG_FILE"
    echo "Run make-pkg.sh first to create the package."
    exit 1
fi

echo "Tag: $TAG_NAME"
echo "Package: $PKG_FILE"

# Check if release already exists
if gh release view "$TAG_NAME" &> /dev/null; then
    echo "Release for tag $TAG_NAME already exists, uploading asset..."
    gh release upload "$TAG_NAME" "$PKG_FILE" --clobber
else
    echo "Creating new release for tag $TAG_NAME..."
    RELEASE_NOTES="${RELEASE_NOTES:-Release $PKG_VERSION}"
    gh release create "$TAG_NAME" "$PKG_FILE" \
        --title "$PKG_VERSION" \
        --notes "$RELEASE_NOTES"
fi

echo "Release complete!"
gh release view "$TAG_NAME" --web || echo "View release at: $(gh release view "$TAG_NAME" --json url -q .url)"
