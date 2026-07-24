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
  RELEASE_TITLE="${RELEASE_TITLE:-Build No. ${BASH_REMATCH[1]}}"
fi
if [ "$RELEASE_TITLE" = "$RELEASE_TAG" ] && [[ "$RELEASE_TAG" =~ ^archive-build-([0-9]+)$ ]]; then
  RELEASE_TITLE="Build No. ${BASH_REMATCH[1]}"
fi

BODY_FILE="$(mktemp)"
write_release_body() {
  local existing_body="$1"
  python - "$APP_NAME" "$existing_body" > "$BODY_FILE" <<'PY'
import re
import sys

app_name = sys.argv[1].strip()
existing = sys.argv[2]
apps = []

match = re.search(r"(?ms)^## Apps in this release\s*(.*?)(?:\n## |\Z)", existing)
if match:
    for line in match.group(1).splitlines():
        item = re.sub(r"^\s*\d+\.\s*", "", line).strip()
        if item:
            apps.append(item)

if app_name and app_name not in apps:
    apps.append(app_name)

print("# Morphe Archive build")
print()
print("This release contains successful APKs from one archive workflow run.")
print()
print("## Apps in this release")
for index, app in enumerate(apps, 1):
    print(f"{index}. {app}")
PY
}

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  existing_body=$(gh release view "$RELEASE_TAG" --json body --jq '.body // ""')
  write_release_body "$existing_body"
  gh release upload "$RELEASE_TAG" "$ASSET_PATH" --clobber
  gh release edit "$RELEASE_TAG" \
    --title "$RELEASE_TITLE" \
    --notes-file "$BODY_FILE"
else
  write_release_body ""
  gh release create "$RELEASE_TAG" "$ASSET_PATH" \
    --title "$RELEASE_TITLE" \
    --notes-file "$BODY_FILE" || {
      existing_body=$(gh release view "$RELEASE_TAG" --json body --jq '.body // ""')
      write_release_body "$existing_body"
      gh release upload "$RELEASE_TAG" "$ASSET_PATH" --clobber
      gh release edit "$RELEASE_TAG" \
        --title "$RELEASE_TITLE" \
        --notes-file "$BODY_FILE"
    }
fi

rm -f "$BODY_FILE"
