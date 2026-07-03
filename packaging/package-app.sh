#!/bin/bash
#
# Empacota o Flux Softphone como .app e gera o instalador .dmg em dist/.
#
# Uso:
#   ./packaging/package-app.sh
#
# Saída:
#   dist/Flux Softphone.app
#   dist/FluxSoftphone-<versão>.dmg   (versão lida do packaging/Info.plist)
#
# Assinatura: ad hoc (testes internos). O macOS de quem baixar via navegador
# vai exigir clique-direito → Abrir na primeira execução (Gatekeeper).
# Developer ID + notarização entram no Ciclo 12 (docs/08_MACOS_RELEASE.md).

set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Flux Softphone"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/FluxSoftphone-$VERSION.dmg"

echo "== Build release (universal: arm64 + x86_64) =="
# Triples explícitos + lipo: `swift build --arch a --arch b` exige o Xcode
# completo; este caminho funciona só com as Command Line Tools.
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0

echo "== Montando $APP =="
rm -rf "$APP" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp packaging/Info.plist "$APP/Contents/Info.plist"
lipo -create \
    .build/arm64-apple-macosx/release/FluxSoftphone \
    .build/x86_64-apple-macosx/release/FluxSoftphone \
    -output "$APP/Contents/MacOS/FluxSoftphone"
lipo -info "$APP/Contents/MacOS/FluxSoftphone"
# Recursos white label DENTRO do .app — o app precisa ser autossuficiente
# em qualquer Mac (bug corrigido em 2026-07-03, docs/10_PROJECT_STATUS.md).
cp -R .build/arm64-apple-macosx/release/FluxSoftphone_FluxWhiteLabel.bundle "$APP/Contents/Resources/"

echo "== Assinando (ad hoc, hardened runtime) =="
codesign --force -s - --options runtime \
    --entitlements packaging/softphone.entitlements "$APP"
codesign --verify --strict "$APP"

echo "== Gerando $DMG =="
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/LEIA-ME.txt" <<EOF
Flux Softphone $VERSION — build de teste interno (assinatura ad hoc)

Instalação:
1. Arraste "Flux Softphone" para a pasta Applications.
2. Na PRIMEIRA abertura: clique com o botão direito no app → Abrir → Abrir.
   (Necessário porque o build de teste ainda não é notarizado pela Apple.
    Se o botão Abrir não aparecer: Ajustes do Sistema → Privacidade e
    Segurança → "Abrir Mesmo Assim".)
3. Conceda o acesso ao microfone quando solicitado.

Configuração: seção Ajustes → Conta SIP (usuário, senha e domínio do PABX).
Personalização white label: seção Aparência.
Modo compacto (só o discador): botão no topo direito ou ⇧⌘M.
EOF
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG" >/dev/null

echo "== Pronto =="
ls -lh "$DMG"
