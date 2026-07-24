#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${RESOLVER:-$SCRIPT_DIR/resolve-apk.sh}"

usage() {
  cat >&2 <<'EOF'
Usage:
  resolve-auto-apk.sh <package> <version|latest> <output.apk> [arch] [dpi] [apk-types] [source-order]

Default source order:
  apkmirror uptodown apkpure apkcombo

Examples:
  resolve-auto-apk.sh com.discord latest ./download/discord.apk all "nodpi anydpi auto"
  resolve-auto-apk.sh com.discord 327.12 ./download/discord.apk arm64-v8a "nodpi anydpi auto" "apk apkm xapk"
EOF
}

log() { echo >&2 "[+] $*"; }
warn() { echo >&2 "[!] $*"; }

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi

package_name="$1"
version="$2"
output="$3"
arch="${4:-all}"
dpi="${5:-nodpi anydpi auto}"
apk_types="${6:-apk apkm xapk apks}"
source_order="${7:-apkmirror uptodown apkpure apkcombo}"

url_for_source() {
  case "$1" in
    apkmirror) printf 'https://www.apkmirror.com/?post_type=app_release&searchtype=app&s=%s\n' "$package_name" ;;
    uptodown) printf 'https://en.uptodown.com/android/search?query=%s\n' "$package_name" ;;
    apkpure) printf 'https://apkpure.com/apk-info/%s\n' "$package_name" ;;
    apkcombo) printf 'https://apkcombo.com/search/%s/\n' "$package_name" ;;
    gplay) printf 'https://play.google.com/store/apps/details?id=%s\n' "$package_name" ;;
    *) return 1 ;;
  esac
}

is_comparable_source() {
  case "$1" in
    apkmirror|uptodown|apkpure|apkcombo) return 0 ;;
    *) return 1 ;;
  esac
}

version_key() {
  python - "$1" <<'PYC'
import re
import sys

value = sys.argv[1]
parts = [int(part) for part in re.findall(r"\d+", value)]
while parts and parts[-1] == 0:
    parts.pop()
suffix = -1 if re.search(r"(alpha|beta|rc|preview)", value, re.I) else 0
print(".".join(f"{part:08d}" for part in parts) + f".{suffix + 1:02d}")
PYC
}

resolve_latest() {
  local source url latest
  for source in $source_order; do
    is_comparable_source "$source" || continue
    url=$(url_for_source "$source") || continue
    log "Resolving latest $package_name via $source"
    if latest=$(bash "$RESOLVER" latest "$source" "$url" | tail -n 1); then
      if [ -n "$latest" ]; then
        log "$source latest: $latest"
        printf '%s\t%s\t%s\n' "$latest" "$source" "$url"
        return 0
      fi
    else
      warn "$source did not resolve a latest version"
    fi
  done
  return 1
}

download_with_fallbacks() {
  local wanted_version="$1" preferred_source="${2:-}" preferred_url="${3:-}" source url

  if [ -n "$preferred_source" ]; then
    log "Downloading $package_name $wanted_version via selected $preferred_source"
    if bash "$RESOLVER" "$preferred_source" "$preferred_url" "$wanted_version" "$output" "$arch" "$dpi" "$apk_types"; then
      return 0
    fi
    warn "$preferred_source failed; trying fallback sources"
  fi

  for source in $source_order; do
    [ "$source" = "$preferred_source" ] && continue
    url=$(url_for_source "$source") || continue
    log "Trying $source for $package_name $wanted_version"
    if bash "$RESOLVER" "$source" "$url" "$wanted_version" "$output" "$arch" "$dpi" "$apk_types"; then
      return 0
    fi
    warn "$source could not resolve $package_name $wanted_version; trying next source"
  done

  return 1
}

if [ "$version" = "latest" ]; then
  latest_row=$(resolve_latest) || {
    warn "Could not resolve latest comparable version; trying Google Play fallback"
    download_with_fallbacks "" "" ""
    exit $?
  }
  IFS=$'\t' read -r version selected_source selected_url <<<"$latest_row"
  log "Selected $package_name version $version from $selected_source"
  download_with_fallbacks "$version" "$selected_source" "$selected_url"
else
  download_with_fallbacks "$version" "" ""
fi
