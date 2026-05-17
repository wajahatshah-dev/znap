#!/bin/bash
# Regenerate Znap.icns and the menu-bar PNGs from the source PNGs in Assets/.
# Run from the project root: scripts/generate-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC_APP_ICON="Assets/znap.png"
SRC_MENU_ICON="Assets/znapbw.png"
ICONSET="Assets/Znap.iconset"
OUT_APP_ICNS="App/Resources/Znap.icns"
OUT_MENU_1X="App/Resources/MenuBarIcon.png"
OUT_MENU_2X="App/Resources/MenuBarIcon@2x.png"

if [ ! -f "$SRC_APP_ICON" ]; then
    echo "Missing source: $SRC_APP_ICON" >&2
    exit 1
fi
if [ ! -f "$SRC_MENU_ICON" ]; then
    echo "Missing source: $SRC_MENU_ICON" >&2
    exit 1
fi

echo "==> Building iconset → $ICONSET"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$SRC_APP_ICON" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
done
sips -z 32  32  "$SRC_APP_ICON" --out "$ICONSET/icon_16x16@2x.png"  >/dev/null
sips -z 64  64  "$SRC_APP_ICON" --out "$ICONSET/icon_32x32@2x.png"  >/dev/null
sips -z 256 256 "$SRC_APP_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 512 512 "$SRC_APP_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 1024 1024 "$SRC_APP_ICON" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

echo "==> Compiling $OUT_APP_ICNS"
iconutil -c icns "$ICONSET" -o "$OUT_APP_ICNS"

echo "==> Generating menu-bar PNGs from $SRC_MENU_ICON"
# Crop center square first (handles non-square source like 1536x1024).
TMP_SQUARE="$(mktemp -t znap-menu-square-XXXXXX).png"
trap 'rm -f "$TMP_SQUARE"' EXIT
W=$(sips -g pixelWidth  "$SRC_MENU_ICON" | awk '/pixelWidth/  {print $2}')
H=$(sips -g pixelHeight "$SRC_MENU_ICON" | awk '/pixelHeight/ {print $2}')
S=$(( W < H ? W : H ))
sips -c "$S" "$S" "$SRC_MENU_ICON" --out "$TMP_SQUARE" >/dev/null
sips -z 44 44 "$TMP_SQUARE" --out "$OUT_MENU_1X" >/dev/null
sips -z 88 88 "$TMP_SQUARE" --out "$OUT_MENU_2X" >/dev/null

echo
echo "Done. Updated:"
echo "  $OUT_APP_ICNS"
echo "  $OUT_MENU_1X"
echo "  $OUT_MENU_2X"
