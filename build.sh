#!/bin/bash
set -euo pipefail

APP_NAME="Znap"
BUILD_DIR=".build/app"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "==> Building Swift package (release)…"
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BIN=".build/apple/Products/Release/$APP_NAME"
else
    swift build -c release
    BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
fi

if [ ! -x "$BIN" ]; then
    echo "Build did not produce $BIN" >&2
    exit 1
fi

echo "==> Assembling app bundle at $APP …"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/$APP_NAME"
cp App/Info.plist "$CONTENTS/Info.plist"
# Copy everything under App/Resources/ into the bundle.
if [ -d App/Resources ]; then
    for f in App/Resources/*; do
        [ -e "$f" ] && cp -R "$f" "$RES/"
    done
fi

echo "==> Ad-hoc signing…"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Installing to ~/Applications…"
INSTALL_DIR="$HOME/Applications"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
# Preserve the signature from the build copy — DON'T re-sign here.
cp -R "$APP" "$INSTALL_DIR/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
mdimport "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true

echo
echo "Built:     $APP"
echo "Installed: $INSTALL_DIR/$APP_NAME.app  (searchable in Spotlight as \"Znap\")"
echo "Run with:  open \"$INSTALL_DIR/$APP_NAME.app\""
echo
echo "First launch: macOS will prompt for Screen Recording permission."
echo "Grant it in System Settings → Privacy & Security → Screen Recording,"
echo "then relaunch the app."
