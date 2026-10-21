#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=~/Applications/Pausa.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 main.swift Config.swift Settings.swift Sync.swift Design.swift -o "$APP/Contents/MacOS/Pausa"
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
<key>NSLocalNetworkUsageDescription</key><string>Pausa busca y crea jams de pausas en tu red.</string>
<key>NSBonjourServices</key><array><string>_pausa._tcp</string></array>
</dict></plist>
PLIST
# Firmar con una identidad estable. Con firma ad-hoc macOS identifica la app por el hash
# del binario, que cambia en cada build, y se olvida de los permisos (Red local).
# PAUSA_SIGN elige otra identidad; si no hay ninguna, queda ad-hoc como antes.
IDENTITY=${PAUSA_SIGN:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}
if [[ -n $IDENTITY ]]; then
  codesign -s "$IDENTITY" --force "$APP"
else
  echo "Aviso: no hay identidad de firma (Apple Development); firmo ad-hoc y macOS va a volver a pedir el permiso de Red local en cada build."
  codesign -s - --force "$APP"
fi
echo "OK: $APP"
