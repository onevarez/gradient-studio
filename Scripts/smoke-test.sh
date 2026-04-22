#!/usr/bin/env bash
# Headless render smoke test for GradientStudio.
#
# Builds the app (if needed), renders a short MP4 via the headless export
# path, and verifies the output file was produced. Intended to catch gross
# regressions in the renderer, shader compile, preset decode, or export
# pipeline — not visual parity.
#
# Usage:
#   Scripts/smoke-test.sh [output.mp4]
#
# Environment overrides:
#   GRADIENT_EXPORT_PRESET    path to a v1 or v2 preset JSON (optional)
#   GRADIENT_EXPORT_DURATION  seconds, default 2
#   GRADIENT_EXPORT_FPS       frames/sec, default 30
#   GRADIENT_EXPORT_WIDTH     pixels, default 640
#   GRADIENT_EXPORT_HEIGHT    pixels, default 360

set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUT=${1:-/tmp/gs-smoke.mp4}
rm -f "$OUTPUT"

echo "→ building GradientStudio"
swift build

BIN_DIR="$(swift build --show-bin-path)"
BINARY="$BIN_DIR/GradientStudio"
if [[ ! -x "$BINARY" ]]; then
    echo "ERROR: binary not found at $BINARY" >&2
    exit 1
fi

echo "→ rendering to $OUTPUT"
GRADIENT_EXPORT_PATH="$OUTPUT" \
  GRADIENT_EXPORT_DURATION="${GRADIENT_EXPORT_DURATION:-2}" \
  GRADIENT_EXPORT_FPS="${GRADIENT_EXPORT_FPS:-30}" \
  GRADIENT_EXPORT_WIDTH="${GRADIENT_EXPORT_WIDTH:-640}" \
  GRADIENT_EXPORT_HEIGHT="${GRADIENT_EXPORT_HEIGHT:-360}" \
  GRADIENT_EXPORT_PRESET="${GRADIENT_EXPORT_PRESET:-}" \
  "$BINARY"

if [[ ! -s "$OUTPUT" ]]; then
    echo "ERROR: output $OUTPUT was not produced or is empty" >&2
    exit 1
fi

SIZE=$(stat -f %z "$OUTPUT")
echo "✓ smoke test OK: $OUTPUT ($SIZE bytes)"
