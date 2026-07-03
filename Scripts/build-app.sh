#!/bin/bash
# Empacota o executável SPM num bundle .app do macOS (Ciclo 12, etapa mínima).
#
# Por que existe: microfone real (AVAudioEngine + TCC) exige um bundle com
# Info.plist declarando NSMicrophoneUsageDescription e assinatura de código —
# `swift run` não tem bundle, então o macOS bloqueia o microfone. Este script
# gera um .app assinado ad-hoc, suficiente para testar áudio localmente.
#
# Uso:
#   Scripts/build-app.sh              # release, abre o app ao final
#   Scripts/build-app.sh --debug      # build debug, mais rápido
#   Scripts/build-app.sh --no-open    # não abre ao final
#
# Distribuição a clientes exige Developer ID + notarização (docs/08) — fora
# do escopo deste script de teste local.

set -euo pipefail

CONFIG="release"
OPEN_APP=1
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG="debug" ;;
    --no-open) OPEN_APP=0 ;;
    *) echo "Argumento desconhecido: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Flux Softphone"
EXECUTABLE="FluxSoftphone"
BUNDLE_ID="br.com.flux.softphone"
VERSION="1.0.0"
BUILD_DIR="$ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "▸ Compilando ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Montando o bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE"

# Bundle de recursos do SPM (brand-config.json etc.), se presente.
RESOURCE_BUNDLE="$BIN_PATH/FluxSoftphone_FluxWhiteLabel.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>O microfone é usado para transmitir sua voz durante as chamadas telefônicas.</string>
</dict>
</plist>
PLIST

echo "▸ Assinando (ad-hoc) com entitlement de microfone…"
ENTITLEMENTS="$BUILD_DIR/softphone.entitlements"
cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
ENT

codesign --force --sign - \
  --entitlements "$ENTITLEMENTS" \
  --options runtime \
  "$APP_BUNDLE" >/dev/null 2>&1 || \
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_BUNDLE"

echo "▸ Pronto: $APP_BUNDLE"

if [ "$OPEN_APP" -eq 1 ]; then
  echo "▸ Abrindo…"
  open "$APP_BUNDLE"
fi
