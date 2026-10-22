#!/bin/zsh
# Arma dist/Pausa-<versión>.dmg para pasarle la app a otros: arrastrar Pausa a Aplicaciones.
#
# Para que abra sin advertencias en otras Macs hace falta un certificado "Developer ID Application"
# (cuenta paga de Apple Developer) y notarizar. Si hay uno en el llavero se usa solo; para notarizar,
# guardá una vez las credenciales y pasá el perfil:
#   xcrun notarytool store-credentials pausa --apple-id <mail> --team-id <team> --password <app-specific>
#   NOTARY_PROFILE=pausa ./package.sh
set -e
cd "$(dirname "$0")"
VERSION=$(cat VERSION)
DMG=dist/Pausa-$VERSION.dmg
rm -rf dist
mkdir -p dist/dmg

DEVID=$(security find-identity -v -p codesigning | awk '/Developer ID Application/ {print $2; exit}')
APP=$PWD/dist/dmg/Pausa.app PAUSA_PACKAGE=1 PAUSA_SIGN=${PAUSA_SIGN:-$DEVID} PAUSA_RUNTIME=${DEVID:+1} ./build.sh

# Instalador con fondo propio, íconos ubicados y sin barras de Finder (dmgbuild escribe el
# .DS_Store directo, sin abrir Finder ni pedir permisos). Se instala solo en tools/.venv.
[[ -x tools/.venv/bin/dmgbuild ]] || { python3 -m venv tools/.venv && tools/.venv/bin/pip install -q dmgbuild==1.6.7; }
swift tools/make-dmg-background.swift dist/bg "$VERSION" >/dev/null
tiffutil -cathidpicheck dist/bg/background.png dist/bg/background@2x.png -out dist/bg/background.tiff 2>/dev/null
tools/.venv/bin/dmgbuild -s tools/dmg-settings.py -D app=dist/dmg/Pausa.app -D background_dir=dist/bg \
  "Pausa $VERSION" "$DMG" >/dev/null
rm -rf dist/dmg dist/bg

if [[ -n $DEVID ]]; then
  codesign -s "$DEVID" --timestamp "$DMG"
  if [[ -n $NOTARY_PROFILE ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  else
    echo "Aviso: firmado con Developer ID pero sin notarizar (NOTARY_PROFILE). Gatekeeper va a advertir igual."
  fi
else
  echo "Aviso: no hay certificado Developer ID Application. En otras Macs, la primera vez:"
  echo "  clic derecho en Pausa → Abrir, o Ajustes del Sistema → Privacidad y seguridad → Abrir igual."
fi
echo "OK: $DMG"
