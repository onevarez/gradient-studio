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

## Status

v1 scope: one composed scene with four layers (Linear → WaveDistortion → Mesh → Glass), sliders per layer, export button. See plan for out-of-scope items.
