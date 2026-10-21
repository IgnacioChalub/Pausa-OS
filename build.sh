#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=~/Applications/Pausa.app
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift -o "$APP/Contents/MacOS/Pausa"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Pausa</string>
<key>CFBundleIdentifier</key><string>com.ignacio.pausa</string>
<key>CFBundleExecutable</key><string>Pausa</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign -s - --force "$APP"
echo "OK: $APP"
