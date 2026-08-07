#!/usr/bin/env bash
# Build VibePilot.app from the swift build product, then sign it.
# Uses a fixed self-signed certificate so TCC screen-recording permission
# survives rebuilds (ad-hoc signing changes on every rebuild).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/mac-stream"

CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
swift build -c release --product vibeapp \
  --disable-sandbox -Xcc -fmodules-cache-path=/tmp/clang-module-cache

APP_DIR="$ROOT/build/VibePilot.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp .build/release/vibeapp "$APP_DIR/Contents/MacOS/vibeapp"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VibePilot</string>
    <key>CFBundleDisplayName</key>
    <string>VibePilot</string>
    <key>CFBundleIdentifier</key>
    <string>com.vibework.vibepilot</string>
    <key>CFBundleExecutable</key>
    <string>vibeapp</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>vibework</string>
</dict>
</plist>
PLIST

# Prefer a stable Apple Development identity so TCC screen-recording
# permission survives rebuilds; fall back to ad-hoc otherwise.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -o 'Apple Development: [^"]*' | head -1)
if [ -z "$IDENTITY" ]; then
    echo "No Apple Development identity found; using ad-hoc signing."
    codesign --force --sign - "$APP_DIR"
else
    echo "Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" "$APP_DIR"
fi
echo "OK: $APP_DIR"
echo "Open it with: open $APP_DIR"
