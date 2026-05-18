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

# Install to /Applications by default (the system-wide Applications folder).
# Override with: INSTALL_DIR=~/Applications ./build.sh
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DEST="$INSTALL_DIR/$APP_NAME.app"

# /Applications is owned by root; use sudo only when we don't have write access.
if [ -w "$INSTALL_DIR" ]; then
    SUDO=""
else
    SUDO="sudo"
    echo "==> Installing to ${INSTALL_DIR} (requires admin password)…"
fi

[ -z "$SUDO" ] && echo "==> Installing to ${INSTALL_DIR}…"
$SUDO mkdir -p "$INSTALL_DIR"
$SUDO rm -rf "$DEST"
# Preserve the signature from the build copy — DON'T re-sign here.
$SUDO cp -R "$APP" "$DEST"
$SUDO /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "$DEST" 2>/dev/null || true
mdimport "$DEST" 2>/dev/null || true

echo
echo "Built:     $APP"
echo "Installed: $DEST  (searchable in Spotlight as \"Znap\")"
echo "Run with:  open \"$DEST\""
echo
echo "First launch: macOS will prompt for Screen Recording permission."
echo "Grant it in System Settings → Privacy & Security → Screen Recording,"
echo "then relaunch the app."
