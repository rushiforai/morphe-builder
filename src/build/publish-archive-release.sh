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

BODY_FILE="$(mktemp)"
cat > "$BODY_FILE" <<EOF
# Morphe Archive build

This release contains successful APKs from one archive workflow run.

Latest uploaded asset:
- App: $APP_NAME
- Package: $PACKAGE_NAME
- Patch source: $SOURCE_WEB_URL
- APK source: ${PATCHED_FROM_SOURCE:-unknown}
- Build id: $ARCHIVE_BUILD_ID
EOF

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  gh release upload "$RELEASE_TAG" "$ASSET_PATH" --clobber
  gh release edit "$RELEASE_TAG" \
    --title "$RELEASE_TAG" \
    --notes-file "$BODY_FILE"
else
  gh release create "$RELEASE_TAG" "$ASSET_PATH" \
    --title "$RELEASE_TAG" \
    --notes-file "$BODY_FILE" || {
      gh release upload "$RELEASE_TAG" "$ASSET_PATH" --clobber
      gh release edit "$RELEASE_TAG" \
        --title "$RELEASE_TAG" \
        --notes-file "$BODY_FILE"
    }
fi

rm -f "$BODY_FILE"
