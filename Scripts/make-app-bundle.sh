#!/bin/bash
set -euo pipefail

# Build GradientStudio.app (universal) and a distributable zip.
# Usage: Scripts/make-app-bundle.sh [version]
#   version: e.g. v0.1.0 — used for CFBundleShortVersionString and the zip name.
#            Defaults to "dev" for local builds.

VERSION="${1:-dev}"
APP_NAME="GradientStudio"
BUNDLE_ID="com.onevarez.gradientstudio"
DIST_DIR="dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

# Strip a leading 'v' so CFBundleShortVersionString is a clean semver.
SHORT_VERSION="${VERSION#v}"

rm -rf "$DIST_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# GS_UNIVERSAL=0 builds a native single-arch binary (useful locally without full Xcode).
# Default is universal (arm64 + x86_64); CI relies on this.
if [ "${GS_UNIVERSAL:-1}" = "1" ]; then
  echo "==> Building universal release binary (arm64 + x86_64)"
  swift build -c release --arch arm64 --arch x86_64
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  echo "==> Building native release binary (GS_UNIVERSAL=0)"
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

echo "==> Writing Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
    <key>CFBundleVersion</key><string>$SHORT_VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Zipping with ditto"
( cd "$DIST_DIR" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME-$VERSION.zip" )

echo ""
echo "Built: $APP_DIR"
echo "Zip:   $DIST_DIR/$APP_NAME-$VERSION.zip"
