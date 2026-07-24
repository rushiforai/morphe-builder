#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${MANIFEST:-src/archive/build-manifest.json}"
BUILD_ID="${1:-}"

if [ -z "$BUILD_ID" ]; then
  echo "Usage: bash src/build/archive-entry.sh <build-id>" >&2
  exit 2
fi

source ./src/build/utils.sh

WORK_DIR=".work/archive-build/$BUILD_ID"
mkdir -p "$WORK_DIR" ./download ./release

python - "$MANIFEST" "$BUILD_ID" "$WORK_DIR" <<'PY'
import json
import shlex
import sys
from pathlib import Path

manifest_path, build_id, work_dir = sys.argv[1], sys.argv[2], Path(sys.argv[3])
manifest = json.loads(Path(manifest_path).read_text(encoding="utf-8"))
entry = next((item for item in manifest.get("builds", []) if item.get("id") == build_id), None)
if entry is None:
    raise SystemExit(f"Build id not found: {build_id}")

patch_file = work_dir / "include-patches"
patch_file.write_text(
    "\n".join(patch["name"] for patch in entry.get("patches", []) if patch.get("name")) + "\n",
    encoding="utf-8",
)

options_file = work_dir / "options.json"
options_file.write_text("[]\n", encoding="utf-8")

env = {
    "ARCHIVE_BUILD_ID": entry["id"],
    "APP_NAME": entry["appName"],
    "PACKAGE_NAME": entry["packageName"],
    "SOURCE_REPO": entry["sourceRepo"],
    "SOURCE_URL": entry["sourceUrl"],
    "SOURCE_WEB_URL": entry["sourceWebUrl"],
    "APK_ARCH": entry["apk"].get("arch", "all"),
    "APK_DPI": entry["apk"].get("dpi", "nodpi anydpi auto"),
    "APK_TYPES": " ".join(entry["apk"].get("apkTypes", [])),
    "RELEASE_TAG": entry["release"]["tag"],
    "ASSET_NAME": entry["release"]["assetName"],
    "OPTIONS_FILE": str(options_file),
    "PATCH_FILE": str(patch_file),
}

(work_dir / "entry.json").write_text(json.dumps(entry, indent=2) + "\n", encoding="utf-8")
(work_dir / "env.sh").write_text(
    "\n".join(f"{key}={shlex.quote(str(value))}" for key, value in env.items()) + "\n",
    encoding="utf-8",
)
PY

source "$WORK_DIR/env.sh"

green_log "[+] Archive build: $ARCHIVE_BUILD_ID"
green_log "[+] App: $APP_NAME [$PACKAGE_NAME]"
green_log "[+] Source: $SOURCE_REPO"

dl_gh "morphe-desktop" "MorpheApp" "latest"

BUNDLE_JSON="$WORK_DIR/patches-bundle.json"
PATCHES_FILE="$WORK_DIR/patches.mpp"
export PATCHES_FILE
curl -L --fail -s -S "$SOURCE_URL" -o "$BUNDLE_JSON"

PATCHES_URL=$(python - "$BUNDLE_JSON" <<'PY'
import json
import sys
from pathlib import Path

bundle = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
url = bundle.get("download_url") or bundle.get("patches_download_url")
if not url:
    raise SystemExit("No download_url found in patches-bundle.json")
print(url)
PY
)

green_log "[+] Downloading patch bundle: $PATCHES_URL"
curl -L --fail -s -S "$PATCHES_URL" -o "$PATCHES_FILE"

APK_BASENAME="${ASSET_NAME%.apk}"
mapfile -t INCLUDED_PATCHES < "$PATCH_FILE"
PATCH_ARGS=()
for patch_name in "${INCLUDED_PATCHES[@]}"; do
  [ -n "$patch_name" ] || continue
  PATCH_ARGS+=("-e" "$patch_name")
done

SOURCE_ORDER="${APK_SOURCE_ORDER:-apkmirror uptodown apkpure apkcombo gplay}"
PATCHED_FROM_SOURCE=""
PATCH_LOG="$WORK_DIR/patch-attempts.log"
: > "$PATCH_LOG"

for apk_source in $SOURCE_ORDER; do
  green_log "[+] Trying APK source: $apk_source"
  rm -f "./download/$APK_BASENAME.apk" "./release/$ASSET_NAME"

  if ! get_apk_auto "$PACKAGE_NAME" "$APK_BASENAME" "apk" "$APK_ARCH" "$APK_DPI" "$APK_TYPES" "$apk_source"; then
    echo "Download failed from $apk_source" >> "$PATCH_LOG"
    continue
  fi

  green_log "[+] Patching $APK_BASENAME from $apk_source -> release/$ASSET_NAME"
  if java -jar morphe-desktop-*.jar patch \
    -p "$PATCHES_FILE" \
    --options-file "$OPTIONS_FILE" \
    --out="./release/$ASSET_NAME" \
    --keystore=./src/morphe.keystore \
    --force \
    --continue-on-error \
    "${PATCH_ARGS[@]}" \
    "./download/$APK_BASENAME.apk" >> "$PATCH_LOG" 2>&1 && [ -s "./release/$ASSET_NAME" ]; then
    PATCHED_FROM_SOURCE="$apk_source"
    break
  fi

  echo "Patch failed from $apk_source" >> "$PATCH_LOG"
done

if [ -z "$PATCHED_FROM_SOURCE" ]; then
  echo "No APK source produced a patchable build for $ARCHIVE_BUILD_ID" >&2
  cat "$PATCH_LOG" >&2
  exit 1
fi

{
  printf 'ARCHIVE_BUILD_ID=%q\n' "$ARCHIVE_BUILD_ID"
  printf 'RELEASE_TAG=%q\n' "${RELEASE_TAG_OVERRIDE:-$RELEASE_TAG}"
  printf 'ASSET_NAME=%q\n' "$ASSET_NAME"
  printf 'APP_NAME=%q\n' "$APP_NAME"
  printf 'PACKAGE_NAME=%q\n' "$PACKAGE_NAME"
  printf 'SOURCE_REPO=%q\n' "$SOURCE_REPO"
  printf 'SOURCE_WEB_URL=%q\n' "$SOURCE_WEB_URL"
  printf 'PATCHED_FROM_SOURCE=%q\n' "$PATCHED_FROM_SOURCE"
} > "$WORK_DIR/release.env"

green_log "[+] Built ./release/$ASSET_NAME from $PATCHED_FROM_SOURCE"
