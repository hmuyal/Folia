#!/usr/bin/env bash
# Builds MDApp.app without Xcode: SwiftPM for the binary, esbuild for the web
# bundle, then a hand-assembled bundle signed ad-hoc so Gatekeeper is happy
# with a locally built app.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MDApp"
BUNDLE_ID="com.hmuyal.mdapp"
VERSION="1.0.0"
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

CONFIG="release"
DO_RUN=0
SKIP_WEB=0
ARCHS=(--arch arm64)

for arg in "$@"; do
  case "$arg" in
    --debug)     CONFIG="debug" ;;
    --run)       DO_RUN=1 ;;
    --skip-web)  SKIP_WEB=1 ;;
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    -h|--help)
      cat <<'USAGE'
usage: ./build.sh [options]
  --debug      build the debug configuration (faster, unoptimised)
  --run        launch the app when the build finishes
  --skip-web   reuse the existing web bundle
  --universal  build a universal arm64 + x86_64 binary
USAGE
      exit 0 ;;
  esac
done

say() { printf '\033[1;38;5;173m▸\033[0m %s\n' "$1"; }
die() { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- web ------
if [[ $SKIP_WEB -eq 0 ]]; then
  say "Building web bundle"
  [[ -d web/node_modules ]] || (cd web && npm install --no-audit --no-fund)
  (cd web && node build.mjs) || die "web build failed"
fi

say "Checking Swift/JS render-option parity"
node Tools/check-options-parity.mjs || die "render options are out of sync"

# -------------------------------------------------------------- binary -----
say "Compiling Swift ($CONFIG)"
swift build -c "$CONFIG" "${ARCHS[@]}" --product MDApp || die "swift build failed"

BIN_PATH="$(swift build -c "$CONFIG" "${ARCHS[@]}" --product MDApp --show-bin-path)"
[[ -x "$BIN_PATH/MDApp" ]] || die "binary not found at $BIN_PATH/MDApp"

# ---------------------------------------------------------------- icon -----
say "Rendering app icon"
swift build -c release --arch arm64 --product IconGen >/dev/null 2>&1 || true
ICON_BIN="$(swift build -c release --arch arm64 --product IconGen --show-bin-path 2>/dev/null)/IconGen"
ICONSET="build/MDApp.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if [[ -x "$ICON_BIN" ]] && "$ICON_BIN" "$ICONSET" >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "build/MDApp.icns" 2>/dev/null || true
fi

# -------------------------------------------------------------- bundle -----
say "Assembling $APP_NAME.app"
APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/MDApp" "$APP/Contents/MacOS/$APP_NAME"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Sources/MDApp/Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || die "Info.plist is invalid"

printf 'APPL????' > "$APP/Contents/PkgInfo"

[[ -d web/dist/web ]] || die "web bundle missing — run without --skip-web"
cp -R web/dist/web "$APP/Contents/Resources/web"
rm -rf "$APP/Contents/Resources/web/docs"     # dev samples, not shipped

# CoreText cannot load woff2, so native chrome falls back to the system face.
# Drop any .otf/.ttf placed here and FontRegistrar will pick it up.
mkdir -p "$APP/Contents/Resources/Fonts"
find Resources/Fonts -type f \( -name '*.otf' -o -name '*.ttf' \) \
  -exec cp {} "$APP/Contents/Resources/Fonts/" \; 2>/dev/null || true

[[ -f build/MDApp.icns ]] && cp build/MDApp.icns "$APP/Contents/Resources/MDApp.icns"

# ---------------------------------------------------------------- sign -----
say "Signing (ad-hoc)"
codesign --force --deep --sign - --timestamp=none "$APP" 2>/dev/null \
  || printf '  (ad-hoc signing failed; the app will still run locally)\n'

SIZE="$(du -sh "$APP" | cut -f1)"
printf '\n\033[1;32m✓\033[0m %s  (%s, %s)\n' "$APP" "$CONFIG" "$SIZE"
printf '   open %s\n' "$APP"

if [[ $DO_RUN -eq 1 ]]; then
  say "Launching"
  open "$APP"
fi
