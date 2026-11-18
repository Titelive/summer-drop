#!/bin/bash
# Compile « Summer Drop » et produit build/Summer Drop.app
# Usage : ./build.sh            -> compile
#         ./build.sh --dmg      -> compile et crée build/SummerDrop.dmg
#         ./build.sh --install  -> compile puis copie l'app dans « Jeux/Analogue 3D » (iCloud)
# Variable facultative : VERSION=1.2.0 ./build.sh --dmg  (numéro de version de l'app)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Summer Drop"
EXEC="SummerDrop"
APP="build/$APP_NAME.app"
DMG="build/SummerDrop.dmg"
ICLOUD_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/Documents/Jeux/Analogue 3D"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "❌ Compilateur Swift introuvable. Installez les outils : xcode-select --install"
    exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [ "${SDK_VERSION%%.*}" -lt 26 ]; then
    echo "❌ Le SDK macOS $SDK_VERSION est trop ancien : Liquid Glass demande le SDK macOS 26."
    echo "   Mettez à jour Xcode ou les Command Line Tools (Réglages > Mise à jour de logiciels)."
    exit 1
fi

echo "▶︎ Compilation (SDK macOS $SDK_VERSION)…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc \
    -O \
    -swift-version 5 \
    -parse-as-library \
    -target arm64-apple-macos26.0 \
    -sdk "$SDK_PATH" \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/$EXEC"

cp Info.plist "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    echo "✓ Version $VERSION"
fi

# Icône (facultative) : placez un AppIcon.icns à côté de ce script.
if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Copie de sc64deployer dans l'app (Contents/Resources), comme la version 1.
DEPLOYER=""
for candidate in "./sc64deployer" "../sc64deployer" "$ICLOUD_DIR/sc64deployer"; do
    if [ -f "$candidate" ]; then
        DEPLOYER="$candidate"
        break
    fi
done
if [ -n "$DEPLOYER" ]; then
    cp "$DEPLOYER" "$APP/Contents/Resources/sc64deployer"
    chmod +x "$APP/Contents/Resources/sc64deployer"
    echo "✓ sc64deployer inclus depuis : $DEPLOYER"
else
    echo "⚠︎ sc64deployer non trouvé : l'app le cherchera à côté d'elle au lancement."
fi

# Retire la quarantaine et signe localement (signature « ad hoc »).
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/Resources/sc64deployer" 2>/dev/null || true
codesign --force --sign - "$APP"

echo "✅ Terminé : $(pwd)/$APP"

DO_DMG=0
DO_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dmg) DO_DMG=1 ;;
        --install) DO_INSTALL=1 ;;
    esac
done

if [ "$DO_DMG" = 1 ]; then
    echo "▶︎ Création de l'image disque…"
    STAGE="build/dmg"
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "✅ Image disque : $(pwd)/$DMG"
fi

if [ "$DO_INSTALL" = 1 ]; then
    if [ -d "$ICLOUD_DIR" ]; then
        rm -rf "$ICLOUD_DIR/$APP_NAME.app"
        cp -R "$APP" "$ICLOUD_DIR/"
        echo "✅ Installée dans : $ICLOUD_DIR/$APP_NAME.app"
    else
        echo "⚠︎ Dossier introuvable : $ICLOUD_DIR"
    fi
fi
