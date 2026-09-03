#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
DIST="$ROOT/dist"
APP="$DIST/FlowKeeper.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
ICONSRC="$ROOT/Resources/AppIcon.png"
ICONSET="$ROOT/.build/AppIcon.iconset"

mkdir -p "$MACOS" "$RES" "$ROOT/.build"

echo "Compiling Flow Keeper…"
swift build -c release --package-path "$ROOT"
BIN="$ROOT/.build/release/FlowKeeper"
if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/out/Products/Release/FlowKeeper"
fi
if [[ ! -x "$BIN" ]]; then
  echo "Could not find FlowKeeper binary under .build" >&2
  exit 1
fi
cp "$BIN" "$MACOS/FlowKeeper"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
echo -n 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ICONSRC" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512 1024; do
    sips -z $size $size "$ICONSRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  done
  sips -z 32 32 "$ICONSRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 64 64 "$ICONSRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 256 256 "$ICONSRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 512 512 "$ICONSRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 1024 1024 "$ICONSRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
fi

MENUBAR="$ROOT/Resources/MenuBarIcon.png"
if [[ -f "$MENUBAR" ]]; then
  cp "$MENUBAR" "$RES/MenuBarIcon.png"
fi

chmod +x "$MACOS/FlowKeeper"
echo "Built $APP"

if [[ "${1:-}" == "run" ]]; then
  killall FlowKeeper 2>/dev/null || true
  open "$APP"
fi
