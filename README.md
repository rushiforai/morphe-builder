# Morphe Builder

Morphe Builder is the build backend for [Morphe Archive](https://github.com/rushiforai/morphe-archive). The archive discovers community patch bundles and supported apps; this repository turns those app/source entries into patched APK assets.

The goal is simple: build the latest patchable APK for every app/source combination shown on the archive website, then publish successful APKs in a format that works with Obtainium.

## What This Builds

The archive currently tracks:

- 103 patch sources
- 508 supported apps
- 645 app/source build combinations

An app/source build combination means one app patched with one patch repository. If the same app is supported by multiple patch sources, each source gets its own APK asset name so Obtainium can track them separately.

## Build Flow

Each build starts from one `build_id` in `src/archive/build-manifest.json`.

1. Download the app/source entry from the manifest.
2. Download the patch source `patches-bundle.json`.
3. Download the `.mpp` patch bundle from that JSON.
4. Resolve the latest stock APK by package name.
5. Patch the APK with only the patches listed for that app/source.
6. Upload the successful APK to the current workflow-run release.

If a source downloads an APK but patching fails, the builder moves to the next APK source. It does not try every architecture as a patch matrix; architecture is only a preference while choosing an APK.

## APK Source Priority

Default source order:

```text
APKMirror -> Uptodown -> APKPure -> APKCombo -> Google Play
```

Within each APK source, architecture priority is:

```text
universal/all -> arm64-v8a -> armeabi-v7a
```

`x86` and `x86_64` only APKs are skipped because they are not useful for most Android devices.

## Releases

Archive workflows publish all successful APKs from one workflow run into a single release.

Tag format:

```text
archive-build-<github-run-number>
```

Visible release name:

```text
Build No. <github-run-number>
```

Release notes contain a generated list:

```text
Apps in this release
1. Google
2. Gemini
```

APK asset names stay stable per app/source, for example:

```text
google-ariecos-gemini-patches.apk
1-1-1-1-rushiranpise-morphe-patches.apk
```

The archive website's **Install with Obtainium** button points to this repo and filters by the exact APK asset name, so all APKs can live in one run release without mixing update streams.

## GitHub Actions

### Archive Build

Build one app/source entry.

Input:

```text
build_id: com-google-android-apps-bard-ariecos-gemini-patches
source_order: apkmirror uptodown apkpure apkcombo
```

### Archive Build Source

Build every manifest entry from one patch source.

Inputs:

```text
source_repo: rushiranpise/morphe-patches
max_parallel: 20
source_order: apkmirror uptodown apkpure apkcombo
```

### Archive Build All

Build all manifest entries, optionally filtered to one source.

Inputs:

```text
source_repo: all
chunk_size: 10
max_parallel: 20
source_order: apkmirror uptodown apkpure apkcombo
```

Archive jobs use `timeout-minutes: 360`, the maximum GitHub-hosted job timeout.

## Local Usage

Generate the manifest from Morphe Archive:

```bash
python scripts/generate_archive_manifest.py
```

By default this reads:

```text
https://raw.githubusercontent.com/rushiforai/morphe-archive/refs/heads/main/docs/data.json
```

Build one app/source entry locally:

```bash
bash src/build/archive-entry.sh com-google-android-apps-bard-ariecos-gemini-patches
```

The built APK is written to:

```text
release/
```

## Important Notes

- This repository builds community patches. Patch sources are not individually verified here.
- Builds can fail because an app changed, a patch is outdated, a source blocks downloads, or the latest APK is incompatible.
- Successful build does not mean the patched app is safe, allowed by the app's terms, or free from side effects.
- Use at your own risk.

## Credits

This builder is based on and inspired by [FiorenMas/Revanced-And-Revanced-Extended-Non-Root](https://github.com/FiorenMas/Revanced-And-Revanced-Extended-Non-Root). Full credit to the original project and author for the workflow foundation.

APK resolving and hardening also borrows ideas from [rushiranpise/patches-tracker](https://github.com/rushiranpise/patches-tracker).
