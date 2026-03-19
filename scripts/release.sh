#!/bin/bash
set -euo pipefail

# Usage: scripts/release.sh <patch|minor|major> [--dry-run]
# Environment: NOTES_FILE=path (optional, for annotated tag with release notes)
BUMP="${1:-}"

# Validate BUMP argument first
if [[ "$BUMP" != "patch" && "$BUMP" != "minor" && "$BUMP" != "major" ]]; then
    echo "Error: BUMP must be one of: patch, minor, major"
    echo "Usage: scripts/release.sh <patch|minor|major> [--dry-run]"
    exit 1
fi

DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Must be on main branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$BRANCH" != "main" ]]; then
    echo "Error: must be on main branch (currently on '$BRANCH')"
    exit 1
fi

# No uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: uncommitted changes detected. Commit or stash first."
    exit 1
fi

# No untracked files that matter
if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "Warning: untracked files present. Continuing anyway..."
fi

# Run tests
echo "Running tests..."
if ! swift test 2>&1; then
    echo "Error: tests failed"
    exit 1
fi

# Read current version from Info.plist
PLIST="Resources/Info.plist"
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
echo "Current version: $CURRENT"

# Parse semver
IFS='.' read -r MAJOR MINOR PATCH_V <<< "$CURRENT"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH_V="${PATCH_V:-0}"

# Increment
case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH_V=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH_V=0 ;;
    patch) PATCH_V=$((PATCH_V + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH_V}"
TAG="v${NEW_VERSION}"
echo "New version: $NEW_VERSION ($TAG)"

if $DRY_RUN; then
    echo "[dry-run] Would update $PLIST"
    echo "[dry-run] Would commit: Release $TAG"
    echo "[dry-run] Would tag: $TAG"
    echo "[dry-run] Would push to origin"
    exit 0
fi

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
BUILD_NUMBER=$(git rev-list --count HEAD)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

# Commit
git add "$PLIST"
git commit -m "Release $TAG"

# Tag (annotated if NOTES_FILE is set)
if [[ -n "${NOTES_FILE:-}" && -f "${NOTES_FILE:-}" ]]; then
    git tag -a "$TAG" -F "$NOTES_FILE"
else
    git tag "$TAG"
fi

# Push
git push origin main
git push origin "$TAG"

echo "Released $TAG"
echo "CI will now build, sign, and publish the release."
