#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
mkdir -p build
rm -rf build/AppIcon.iconset
swift Scripts/make-icon.swift
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

APP=build/Dogear.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Dogear "$APP/Contents/MacOS/Dogear"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Dogear</string>
    <key>CFBundleIdentifier</key><string>app.dogear.Dogear</string>
    <key>CFBundleName</key><string>Dogear</string>
    <key>CFBundleDisplayName</key><string>Dogear</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>15.4</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Dogear reads your notes to find links you saved.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
