#!/usr/bin/env bash
set -euo pipefail

RELEASE_ENV="${1:-}"

if [ -z "$RELEASE_ENV" ] || [ ! -f "$RELEASE_ENV" ]; then
  echo "Usage: bash src/build/publish-archive-release.sh <release.env>" >&2
  exit 2
fi

source "$RELEASE_ENV"

ASSET_PATH="./release/$ASSET_NAME"
if [ ! -f "$ASSET_PATH" ]; then
  echo "Release asset not found: $ASSET_PATH" >&2
  exit 1
fi

RELEASE_TITLE="${RELEASE_TITLE:-$RELEASE_TAG}"
if [[ "$RELEASE_TAG" =~ ^archive-build-([0-9]+)$ ]]; then
  RELEASE_TITLE="${RELEASE_TITLE:-New Release}"
fi
if [ "$RELEASE_TITLE" = "$RELEASE_TAG" ] && [[ "$RELEASE_TAG" =~ ^archive-build-([0-9]+)$ ]]; then
  RELEASE_TITLE="New Release"
fi

BODY_FILE="$(mktemp)"
# Write a static body without any app list
echo "# Apps in this release" > "$BODY_FILE"

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$ASSET_PATH" --clobber
  gh release edit "$RELEASE_TAG" \
    --title "$RELEASE_TITLE" \
    --notes-file "$BODY_FILE"
else
  gh release create "$RELEASE_TAG" "$ASSET_PATH" \
    --title "$RELEASE_TITLE" \
    --notes-file "$BODY_FILE" || {
      # If creation fails because release already exists, upload and edit
      gh release upload "$RELEASE_TAG" "$ASSET_PATH" --clobber
      gh release edit "$RELEASE_TAG" \
        --title "$RELEASE_TITLE" \
        --notes-file "$BODY_FILE"
    }
fi

rm -f "$BODY_FILE"
