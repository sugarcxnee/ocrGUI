#!/bin/zsh
# 构建发布版 .app：swift build -c release + 组装 bundle + ad-hoc 签名
# 产物：dist/OCR GUI.app
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

APP_NAME="OCR GUI"
DIST="$REPO/dist"
APP="$DIST/$APP_NAME.app"

log() { echo "[make-app] $*"; }

log "编译 release …"
swift build -c release

# 图标：源码生成 icns（有 swift 环境即自动重建）
if [[ ! -f build/AppIcon.icns ]]; then
  log "生成应用图标 …"
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

log "组装 $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/OCRGUI "$APP/Contents/MacOS/OCRGUI"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>OCR GUI</string>
    <key>CFBundleDisplayName</key>       <string>OCR GUI</string>
    <key>CFBundleIdentifier</key>        <string>local.ocrgui</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleExecutable</key>        <string>OCRGUI</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleDevelopmentRegion</key> <string>zh-CN</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>NSScreenCaptureDescription</key>
    <string>用于截图识别屏幕上的文字。</string>
</dict>
</plist>
PLIST

log "ad-hoc 签名 …"
codesign --force --sign - "$APP"

log "✓ 完成：$APP"
log "  启动：open \"$APP\""
