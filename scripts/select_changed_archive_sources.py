from __future__ import annotations

import email.utils
import json
import os
import re
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


MANIFEST_PATH = Path("src/archive/build-manifest.json")
DEFAULT_OUTPUT_LIMIT = 256


def slugify(value: str) -> str:
    value = value.lower().replace("&", "and").replace("+", "plus")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "item"


def source_slug(repo: str) -> str:
    return slugify(repo.replace("/", "-"))


def parse_http_date(value: str | None) -> datetime | None:
    if not value:
        return None
    parsed = email.utils.parsedate_to_datetime(value)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def head_updated_at(url: str) -> datetime | None:
    request = urllib.request.Request(
        url,
        method="HEAD",
        headers={"User-Agent": "morphe-builder-checker/1.0"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return parse_http_date(response.headers.get("Last-Modified"))


def get_json(url: str) -> object:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "morphe-builder-checker/1.0",
        },
    )
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        request.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def bundle_updated_at(source_url: str) -> datetime:
    bundle = get_json(source_url)
    if not isinstance(bundle, dict):
        raise ValueError("bundle JSON is not an object")
    download_url = bundle.get("download_url")
    signature_url = bundle.get("signature_download_url")
    candidates = [url for url in (download_url, signature_url) if isinstance(url, str) and url]
    dates = []
    for url in candidates:
        try:
            date = head_updated_at(url)
            if date:
                dates.append(date)
        except Exception as exc:
            print(f"warning: could not read asset date for {url}: {exc}", file=sys.stderr)
    return max(dates) if dates else datetime.now(timezone.utc)


def release_assets_by_name(repo: str) -> dict[str, datetime]:
    url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
    releases = get_json(url)
    assets: dict[str, datetime] = {}
    if not isinstance(releases, list):
        return assets
    for release in releases:
        for asset in release.get("assets", []):
            name = asset.get("name")
            updated_at = asset.get("updated_at")
            if not name or not updated_at or name in assets:
                continue
            assets[name] = datetime.fromisoformat(updated_at.replace("Z", "+00:00")).astimezone(timezone.utc)
    return assets


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def main() -> None:
    repo = os.environ.get("GITHUB_REPOSITORY", "rushiforai/morphe-builder")
    limit = int(os.environ.get("SOURCE_LIMIT", str(DEFAULT_OUTPUT_LIMIT)))
    force_all = os.environ.get("FORCE_ALL", "").lower() in {"1", "true", "yes"}

    manifest = load_manifest()
    by_source: dict[str, dict] = {}
    for item in manifest.get("builds", []):
        source_repo = item.get("sourceRepo")
        if not source_repo:
            continue
        source = by_source.setdefault(
            source_repo,
            {"repo": source_repo, "sourceUrl": item.get("sourceUrl"), "assets": []},
        )
        asset_name = item.get("release", {}).get("assetName")
        if asset_name:
            source["assets"].append(asset_name)

    release_assets = release_assets_by_name(repo)
    changed: list[str] = []
    for source_repo, source in sorted(by_source.items(), key=lambda pair: pair[0].lower()):
        if force_all:
            changed.append(source_repo)
            continue

        source_url = source.get("sourceUrl")
        if not source_url:
            changed.append(source_repo)
            continue

        try:
            patch_date = bundle_updated_at(source_url)
        except Exception as exc:
            print(f"warning: treating {source_repo} as changed; {exc}", file=sys.stderr)
            changed.append(source_repo)
            continue

        asset_dates = [release_assets[name] for name in source["assets"] if name in release_assets]
        if len(asset_dates) != len(source["assets"]) or any(date < patch_date for date in asset_dates):
            changed.append(source_repo)

    if len(changed) > limit:
        raise SystemExit(f"{len(changed)} sources selected, above matrix limit {limit}")

    print(f"Changed sources: {len(changed)}", file=sys.stderr)
    for source in changed:
        print(f"  - {source}", file=sys.stderr)

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as f:
            f.write(f"sources={json.dumps(changed)}\n")
            f.write(f"count={len(changed)}\n")
    else:
        print(json.dumps(changed, indent=2))


if __name__ == "__main__":
    main()
