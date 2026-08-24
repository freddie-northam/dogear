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
# Strip local symbols: the release binary shipped 6,000 symbols nobody
# loads, which doubled its size. Crash reports still symbolicate through
# the dSYM that swift build leaves beside the binary.
strip -x "$APP/Contents/MacOS/Dogear"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

VERSION="$(tr -d '[:space:]' < VERSION)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Dogear</string>
    <key>CFBundleIdentifier</key><string>app.dogear.Dogear</string>
    <key>CFBundleName</key><string>Dogear</string>
    <key>CFBundleDisplayName</key><string>Dogear</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>15.4</string>
    <key>LSUIElement</key><true/>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Save to Dogear</string></dict>
            <key>NSMessage</key><string>saveToDogear</string>
            <key>NSPortName</key><string>Dogear</string>
            <key>NSSendTypes</key>
            <array><string>public.url</string><string>public.utf8-plain-text</string></array>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key><string>Dogear reads your notes to find links you saved.</string>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --options runtime --sign - "$APP"
echo "Built $APP"
