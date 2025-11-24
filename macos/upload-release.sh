#!/bin/bash
set -e

# Script to upload the diff-pdf .pkg to GitHub as a release
# Required environment variables:
#   GITHUB_TOKEN - GitHub personal access token with repo scope
# Optional environment variables:
#   PKG_VERSION - Version number (defaults to latest git tag)
#   RELEASE_NOTES - Release notes text (defaults to "Release $PKG_VERSION")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# Check for required GitHub token
if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN environment variable is required"
    echo "Create a token at https://github.com/settings/tokens with 'repo' scope"
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

# Get repository info from git remote
REMOTE_URL=$(git remote get-url origin)
# Extract owner/repo from various URL formats
if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    REPO_OWNER="${BASH_REMATCH[1]}"
    REPO_NAME="${BASH_REMATCH[2]}"
else
    echo "Error: Could not parse GitHub repository from remote URL: $REMOTE_URL"
    exit 1
fi

echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Tag: $TAG_NAME"
echo "Package: $PKG_FILE"

# Check if release already exists
RELEASE_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$TAG_NAME"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Accept: application/vnd.github.v3+json" \
    "$RELEASE_URL")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Release for tag $TAG_NAME already exists, fetching release ID..."
    RELEASE_ID=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$RELEASE_URL" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
else
    echo "Creating new release for tag $TAG_NAME..."
    RELEASE_NOTES="${RELEASE_NOTES:-Release $PKG_VERSION}"
    
    RELEASE_RESPONSE=$(curl -s \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -X POST \
        -d "{\"tag_name\":\"$TAG_NAME\",\"name\":\"$PKG_VERSION\",\"body\":\"$RELEASE_NOTES\",\"draft\":false,\"prerelease\":false}" \
        "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases")
    
    RELEASE_ID=$(echo "$RELEASE_RESPONSE" | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')
    
    if [ -z "$RELEASE_ID" ]; then
        echo "Error: Failed to create release"
        echo "$RELEASE_RESPONSE"
        exit 1
    fi
    echo "Created release with ID: $RELEASE_ID"
fi

# Upload the .pkg as a release asset
PKG_FILENAME=$(basename "$PKG_FILE")
UPLOAD_URL="https://uploads.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/$RELEASE_ID/assets?name=$PKG_FILENAME"

echo "Uploading $PKG_FILENAME to release..."
UPLOAD_RESPONSE=$(curl -s \
    -H "Authorization: token $GITHUB_TOKEN" \
    -H "Content-Type: application/octet-stream" \
    -X POST \
    --data-binary "@$PKG_FILE" \
    "$UPLOAD_URL")

# Check if upload was successful
if echo "$UPLOAD_RESPONSE" | grep -q '"state": "uploaded"'; then
    DOWNLOAD_URL=$(echo "$UPLOAD_RESPONSE" | grep -o '"browser_download_url": "[^"]*"' | cut -d'"' -f4)
    echo "Upload successful!"
    echo "Download URL: $DOWNLOAD_URL"
else
    echo "Error: Upload may have failed"
    echo "$UPLOAD_RESPONSE"
    exit 1
fi

echo "Release complete: https://github.com/$REPO_OWNER/$REPO_NAME/releases/tag/$TAG_NAME"
