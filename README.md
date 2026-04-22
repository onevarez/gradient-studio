# GradientStudio

<img width="2592" height="1268" alt="image" src="https://github.com/user-attachments/assets/c35471af-7c2d-410a-a5ce-5173cf2fc69a" />


macOS POC for crafting and exporting animated gradient videos. Pure Swift + Metal + SwiftUI + AVFoundation. No third-party dependencies; all licensing is Apple-SDK-only.


## Requirements

- macOS 14+
- Swift 5.9+ (ships with Xcode 15)

## Run

```sh
swift run
```

Opens a window with a live-animated gradient preview on the left and a layer stack on the right. The Metal source lives in `Shaders.swift` as a Swift string literal and is compiled at runtime via `MTLDevice.makeLibrary(source:)` — no `.metallib` build step. Toolbar: **Undo / Redo**, **Copy Preset**, **Paste Preset**, **Export…**.

## Features

- **Composable layer stack.** Add, remove, duplicate, drag-to-reorder, and toggle layers. Multiple layers of the same kind are allowed; the renderer walks the list in order.
- **Four layer kinds.** Linear gradient, Mesh, Wave distortion, Glass. Post-fx (grain, vignette) is a scene-wide pass that runs last.
- **Undo / redo** over all parameter changes (`⌘Z` / `⇧⌘Z`), coalesced by a short idle window so slider drags collapse into one checkpoint.
- **Preset clipboard.** `⇧⌘C` copies the scene as JSON; `⇧⌘V` applies one from the clipboard. v1 presets (pre-composable-layers) are auto-upgraded on paste.
- **Image palette extraction.** Pick an image; k-means extracts a palette and pushes it into each Mesh layer.
- **Randomize** (`⌘R`) and per-layer actions (reseed, cycle colors, blackout rows/columns).
- **Aspect-ratio preview** (free / 16:9 / 9:16 / 1:1 / 4:5) in the preview toolbar.

## Project layout

```
Sources/GradientStudio/
├── GradientStudioApp.swift       # @main + headless export entry point
├── ContentView.swift             # split view shell + toolbar
├── Shaders.swift                 # Metal source as a Swift string literal
├── Render/                       # GradientRenderer, Layer, RenderParams, ColorHarmony
├── Preview/                      # MTKView bridge + frame pump
├── Controls/                     # per-layer SwiftUI controls + layer list
├── Preset/                       # versioned JSON preset + pasteboard I/O
├── Palette/                      # k-means palette extraction from images
├── Export/                       # AVAssetWriter pipeline + sheet
└── State/                        # @Observable AppState (undo/redo, checkpoints)
```

## Rendering

Multi-pass pipeline with `rgba16Float` ping-pong intermediates. Each layer kind is its own fragment function with its own typed uniform struct; the renderer iterates `params.layers` in order, skipping disabled entries, and writes the final result through a PostFx pass into the app-facing `bgra8Unorm` target. Each layer gets its own uniform buffer from a per-kind pool, grown lazily — so multiple layers of the same kind don't stomp each other's uniforms within a single command buffer.

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

Pin a specific scene by pointing `GRADIENT_EXPORT_PRESET` at a v1 or v2 preset JSON (the same format `Copy Preset` produces):

```sh
GRADIENT_EXPORT_PATH=/tmp/out.mp4 \
GRADIENT_EXPORT_PRESET=/path/to/preset.json \
  .build/arm64-apple-macosx/debug/GradientStudio
```

There's a `Scripts/smoke-test.sh` wrapper that builds, renders a short clip, and checks the output was produced — a gross-regression catch for the renderer, shader compile, and export path. Drop `GRADIENT_EXPORT_PRESET` into the env to pin a scene for repeatable runs.

```sh
Scripts/smoke-test.sh
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

POC / personal playground. The composable layer pipeline (v2 presets) is the current target surface. The smoke-test harness is the only regression check — there's no unit test suite.
