"""
Generate a Morphe Builder manifest from Morphe Archive site data.

Usage:
    python scripts/generate_archive_manifest.py [ARCHIVE_DATA_JSON] [OUTPUT_JSON]

Defaults:
    ARCHIVE_DATA_JSON = ../morphe-archive/docs/data.json
    OUTPUT_JSON       = src/archive/build-manifest.json
"""

from __future__ import annotations

import json
import re
import sys
import urllib.request
from pathlib import Path


DEFAULT_ARCHIVE_DATA = "https://raw.githubusercontent.com/rushiforai/morphe-archive/refs/heads/main/docs/data.json"
DEFAULT_OUTPUT = Path("src/archive/build-manifest.json")


def slugify(value: str) -> str:
    value = value.lower().replace("&", "and").replace("+", "plus")
    value = re.sub(r"[^a-z0-9]+", "-", value)
    return value.strip("-") or "item"


def source_slug(repo: str) -> str:
    return slugify(repo.replace("/", "-"))


def app_slug(app: dict) -> str:
    return slugify(app.get("name") or app.get("packageName") or "app")


def release_tag(package_name: str, repo: str) -> str:
    return f"app-{slugify(package_name)}-{source_slug(repo)}"


def asset_name(app: dict, source: dict) -> str:
    return f"{app_slug(app)}-{source_slug(source.get('repo', 'source'))}.apk"


def build_id(app: dict, source: dict) -> str:
    return f"{slugify(app.get('packageName', 'app'))}-{source_slug(source.get('repo', 'source'))}"


def manifest_entry(app: dict, source: dict) -> dict:
    patches = source.get("patches", [])
    return {
        "id": build_id(app, source),
        "appName": app.get("name") or app.get("packageName"),
        "packageName": app.get("packageName"),
        "sourceRepo": source.get("repo"),
        "sourceHost": source.get("host"),
        "sourceUrl": source.get("source"),
        "sourceWebUrl": source.get("webUrl"),
        "addSourceUrl": source.get("addUrl"),
        "patches": [
            {
                "name": patch.get("name"),
                "description": patch.get("description", ""),
            }
            for patch in patches
        ],
        "versions": source.get("versions", []),
        "apk": {
            "resolver": "auto",
            "arch": "all",
            "dpi": "nodpi anydpi auto",
            "apkTypes": ["apk", "apkm", "xapk", "apks"],
        },
        "release": {
            "tag": release_tag(app.get("packageName", "app"), source.get("repo", "source")),
            "assetName": asset_name(app, source),
        },
    }


def generate(data: dict) -> dict:
    entries = []
    for app in data.get("apps", []):
        for source in app.get("sources", []):
            entries.append(manifest_entry(app, source))

    entries.sort(key=lambda item: (item["packageName"].lower(), item["sourceRepo"].lower()))
    return {
        "generatedFrom": {
            "archiveGeneratedAt": data.get("generatedAt", ""),
            "configFile": data.get("configFile", ""),
            "repoCount": data.get("repoCount", 0),
            "appCount": data.get("appCount", 0),
            "patchCount": data.get("patchCount", 0),
        },
        "summary": {
            "apps": data.get("appCount", 0),
            "sources": data.get("repoCount", 0),
            "appSourceBuilds": len(entries),
        },
        "builds": entries,
    }


def load_archive_data(source: str) -> dict:
    if source.startswith(("http://", "https://")):
        request = urllib.request.Request(
            source,
            headers={"User-Agent": "morphe-builder-manifest-generator/1.0"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            charset = response.headers.get_content_charset() or "utf-8"
            return json.loads(response.read().decode(charset))
    return json.loads(Path(source).read_text(encoding="utf-8"))


def main() -> None:
    archive_data = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ARCHIVE_DATA
    output = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_OUTPUT

    data = load_archive_data(archive_data)
    manifest = generate(data)

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {output} with {manifest['summary']['appSourceBuilds']} app/source builds")


if __name__ == "__main__":
    main()
