#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP=${APP:-~/Applications/Pausa.app}   # package.sh lo arma en dist/
VERSION=$(cat VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
SOURCES=(main.swift Config.swift Settings.swift Sync.swift Design.swift)
[[ $APP == *.app ]] && rm -rf "$APP"  # sin restos de builds viejos
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Universal (Apple Silicon + Intel) y desde macOS 13. Sin -target, swiftc apunta a la versión
# de esta Mac y la app no abre en una con macOS más viejo.
TMP=$(mktemp -d)
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos13.0 $SOURCES -o "$TMP/Pausa-$arch"
done
lipo -create "$TMP"/Pausa-* -output "$APP/Contents/MacOS/Pausa"
rm -rf "$TMP"
cp config.example.yml assets/AppIcon.icns "$APP/Contents/Resources/"
# config.yml es tuyo (no va a git): se arma del example la primera vez y la app lo lee por el symlink.
# Al empaquetar no se toca: quien instala desde el .dmg arranca con el example.
if [[ -z $PAUSA_PACKAGE ]]; then
  [[ -f config.yml ]] || cp config.example.yml config.yml
  mkdir -p ~/.config/pausa
  [[ -e ~/.config/pausa/config.yml && ! -L ~/.config/pausa/config.yml ]] || ln -sf "$PWD/config.yml" ~/.config/pausa/config.yml
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Pausa</string>
<key>CFBundleDisplayName</key><string>Pausa</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.healthcare-fitness</string>
<key>NSHumanReadableCopyright</key><string>Recordatorios de descanso para macOS.</string>
<key>CFBundleIdentifier</key><string>com.ignacio.pausa</string>
<key>CFBundleExecutable</key><string>Pausa</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Pausa busca y crea jams de pausas en tu red.</string>
<key>NSBonjourServices</key><array><string>_pausa._tcp</string></array>
<key>CFBundleURLTypes</key><array><dict>
  <key>CFBundleURLName</key><string>com.ignacio.pausa</string>
  <key>CFBundleURLSchemes</key><array><string>pausa</string></array>
</dict></array>
</dict></plist>
PLIST

# "Pausa Configuración": mini-app que abre pausa://configuracion, para que Spotlight la encuentre
# escribiendo "Pausa Config". Va adentro de Pausa y Pausa la copia al lado suyo al arrancar.
HELPER="$APP/Contents/Resources/Pausa Configuración.app"
mkdir -p "$HELPER/Contents/MacOS" "$HELPER/Contents/Resources"
cat > "$HELPER/Contents/MacOS/abrir" <<'SH'
#!/bin/sh
exec /usr/bin/open "pausa://configuracion"
SH
chmod +x "$HELPER/Contents/MacOS/abrir"
cp assets/AppIcon.icns "$HELPER/Contents/Resources/"
cat > "$HELPER/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Pausa Configuración</string>
<key>CFBundleDisplayName</key><string>Pausa Configuración</string>
<key>CFBundleIdentifier</key><string>com.ignacio.pausa.configuracion</string>
<key>CFBundleExecutable</key><string>abrir</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# Firmar con una identidad estable. Con firma ad-hoc macOS identifica la app por el hash
# del binario, que cambia en cada build, y se olvida de los permisos (Red local).
# PAUSA_SIGN elige otra identidad; si no hay ninguna, queda ad-hoc como antes.
IDENTITY=${PAUSA_SIGN:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}
[[ -n $IDENTITY ]] || echo "Aviso: no hay identidad de firma (Apple Development); firmo ad-hoc y macOS va a volver a pedir el permiso de Red local en cada build."
# Con Developer ID (package.sh) va con hardened runtime y sello de tiempo, que pide la notarización.
# Primero la mini-app de adentro y después Pausa, que sella lo que tiene adentro.
for bundle in "$HELPER" "$APP"; do
  codesign -s "${IDENTITY:--}" --force ${IDENTITY:+${PAUSA_RUNTIME:+--options runtime --timestamp}} "$bundle"
done
echo "OK: $APP"
