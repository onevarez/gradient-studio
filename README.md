# GradientStudio

macOS POC for crafting and exporting animated gradient videos. Pure Swift + Metal + SwiftUI + AVFoundation. No third-party dependencies; all licensing is Apple-SDK-only.

## Requirements

- macOS 14+
- Swift 5.9+ (ships with Xcode 15)

## Run

```sh
swift run
```

The first run compiles the Metal shader into `default.metallib` and drops you into a window with a live-animated gradient preview on the left and sliders on the right. Click **Export…** in the toolbar to render an MP4.

## Project layout

```
Sources/GradientStudio/
├── GradientStudioApp.swift       # @main
├── ContentView.swift             # split view shell
├── Shaders.metal                 # all layer math (single composite pass)
├── Render/                       # GradientRenderer, RenderParams
├── Preview/                      # MTKView bridge + frame pump
├── Controls/                     # per-layer SwiftUI controls
├── Export/                       # AVAssetWriter pipeline + sheet
└── State/                        # @Observable AppState
```

## Export

Exports via `AVAssetWriter` with `AVAssetWriterInputPixelBufferAdaptor`. Frames render into a `CVMetalTextureCache`-backed texture (zero-copy). H.264 by default, HEVC toggleable.

### Headless export (smoke test / batch)

Set `GRADIENT_EXPORT_PATH` on the built binary to skip the UI and export the default preset directly:

```sh
swift build
GRADIENT_EXPORT_PATH=/tmp/out.mp4 \
GRADIENT_EXPORT_DURATION=5 \
GRADIENT_EXPORT_FPS=30 \
GRADIENT_EXPORT_WIDTH=1920 \
GRADIENT_EXPORT_HEIGHT=1080 \
  .build/arm64-apple-macosx/debug/GradientStudio
```

## Releases

Three paths produce a GitHub Release. All of them converge on `.github/workflows/release.yml`, which builds a universal `GradientStudio.app` on `macos-14`, zips it, and attaches it to a Release.

### Preferred: label a PR

Commit freely using [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `feat!:`, etc.). Individual commits **do not** cut releases.

When you're ready to ship everything accumulated on `main`:

1. Label the PR with `release` (create the label once at **github.com/onevarez/gradient-studio/labels**).
2. Merge the PR.

`.github/workflows/label-release.yml` then scans commits since the last `v*` tag, picks the next semver from the aggregate bump level, tags, and dispatches the release build.

Bump rules (`Scripts/compute-next-version.sh`):

| Commit subject                            | Bump    |
|-------------------------------------------|---------|
| `<type>!:` or `BREAKING CHANGE:` footer   | major   |
| `feat:` / `feat(scope):`                  | minor   |
| `fix:` / `perf:` / `revert:` (no feat)    | patch   |
| anything else (no feat/fix)               | patch   |

### Manual: push a tag

```sh
git tag v0.1.0
git push origin v0.1.0
```

### Dry run: dispatch without publishing

**Actions → Release → Run workflow**, set any `version` label (e.g. `v0.1.0-dryrun`), leave `publish` unchecked. The zipped bundle lands as a workflow artifact; no Release is created.

Build locally:

```sh
# Universal (requires full Xcode)
Scripts/make-app-bundle.sh v0.1.0

# Native arch only (works with Command Line Tools)
GS_UNIVERSAL=0 Scripts/make-app-bundle.sh v0.1.0
```

The app is **unsigned**, so on first launch macOS will block it. Either right-click → **Open** → **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/GradientStudio.app
```

## Status

v1 scope: one composed scene with four layers (Linear → WaveDistortion → Mesh → Glass), sliders per layer, export button. See plan for out-of-scope items.
