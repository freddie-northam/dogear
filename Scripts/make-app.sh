#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
INTENTS_PROCESSOR="$TOOLCHAIN/usr/bin/appintentsmetadataprocessor"
PROTOCOLS="Scripts/appintents-protocols.json"

# Shortcuts finds an app's intents through a metadata bundle that Xcode
# normally builds behind a build phase. SwiftPM has no such phase, so the
# compiler is asked for the constant values the processor reads, and the
# processor runs by hand below. Both steps are skipped where the tools are
# missing: the app still builds, only without its Shortcuts actions.
if [ -x "$INTENTS_PROCESSOR" ] && [ -f "$PROTOCOLS" ]; then
    WITH_INTENTS=1
    swift build -c release \
        -Xswiftc -emit-const-values \
        -Xswiftc -Xfrontend -Xswiftc -const-gather-protocols-file \
        -Xswiftc -Xfrontend -Xswiftc "$PROTOCOLS"
else
    WITH_INTENTS=0
    echo "warning: App Intents metadata tools not found; building without Shortcuts actions"
    swift build -c release
fi

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

if [ "$WITH_INTENTS" = "1" ]; then
    CONST_VALS="$(mktemp)"
    SOURCE_LIST="$(mktemp)"
    find .build -path "*release/Dogear.build/*.swiftconstvalues" > "$CONST_VALS"
    ls Sources/Dogear/*.swift > "$SOURCE_LIST"
    TRIPLE="$(swift -print-target-info | sed -n 's/.*"triple": "\([^"]*\)".*/\1/p' | head -1)"
    # A failure here costs the Shortcuts actions, never the build.
    "$INTENTS_PROCESSOR" \
        --output "$APP/Contents/Resources" \
        --toolchain-dir "$TOOLCHAIN" \
        --module-name Dogear \
        --sdk-root "$(xcrun --show-sdk-path)" \
        --xcode-version "$(xcodebuild -version | tail -1 | awk '{print $3}')" \
        --platform-family macosx \
        --deployment-target 15.4 \
        --target-triple "$TRIPLE" \
        --source-file-list "$SOURCE_LIST" \
        --swift-const-vals-list "$CONST_VALS" \
        --force || echo "warning: App Intents metadata step failed; no Shortcuts actions"
    rm -f "$CONST_VALS" "$SOURCE_LIST"
fi

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

codesign --force --sign - "$APP"
echo "Built $APP"
