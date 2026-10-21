#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=~/Applications/Pausa.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 main.swift Config.swift -o "$APP/Contents/MacOS/Pausa"
cp config.example.yml "$APP/Contents/Resources/"
# config.yml es tuyo (no va a git): se arma del example la primera vez y la app lo lee por el symlink.
[[ -f config.yml ]] || cp config.example.yml config.yml
mkdir -p ~/.config/pausa
[[ -e ~/.config/pausa/config.yml && ! -L ~/.config/pausa/config.yml ]] || ln -sf "$PWD/config.yml" ~/.config/pausa/config.yml
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
