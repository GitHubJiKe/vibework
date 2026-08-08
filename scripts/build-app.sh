#!/usr/bin/env bash
# 构建 VibePilot.app（基于 swift build 产物打包，ad-hoc 签名，本机自用）
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
    <string>com.vibepilot.app</string>
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
    <string>VibePilot</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR"
echo "✅ 已生成 $APP_DIR"
echo "   打开方式：open $APP_DIR"
