#!/usr/bin/env bash
# Builds Folia.app without Xcode: SwiftPM for the binary, esbuild for the web
# bundle, then a hand-assembled bundle signed ad-hoc so Gatekeeper is happy
# with a locally built app.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Folia"
BUNDLE_ID="com.hmuyal.folia"
VERSION="1.4.0"
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

say "Checking design tokens are in sync"
node Tools/check-design-tokens.mjs || die "design tokens are out of sync"

# ----------------------------------------------------------------- sdk -----
# The macOS 27 SDK turns SwiftUI's @State into a macro, and the compiler plugin
# that expands it ships with Xcode but not with the Command Line Tools. This
# script exists to build without Xcode, so when only the Command Line Tools are
# selected, build against the newest installed SDK that predates the macro.
DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${SDKROOT:-}" && "$DEV_DIR" == */CommandLineTools ]]; then
  needs_macro_plugin() {
    # -S: the framework's Modules directory is a symlink into Versions/.
    grep -rqsS StateMacro "$1/System/Library/Frameworks/SwiftUICore.framework/Modules"
  }
  if needs_macro_plugin "$DEV_DIR/SDKs/MacOSX.sdk"; then
    while IFS= read -r sdk; do
      [[ -L "$sdk" ]] && continue
      if ! needs_macro_plugin "$sdk"; then export SDKROOT="$sdk"; break; fi
    done < <(ls -d "$DEV_DIR"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV)
    [[ -n "${SDKROOT:-}" ]] \
      || die "the default SDK needs Xcode's SwiftUI macro plugin, and no older SDK is installed — install Xcode, or set SDKROOT"
    say "Using $(basename "$SDKROOT") (the default SDK needs Xcode's SwiftUI macro plugin)"
  fi
fi

# -------------------------------------------------------------- binary -----
# SwiftPM's newer default engine links no @loader_path rpath (so the binary
# cannot find the Sparkle.framework placed beside it) and rewrites whole
# bundles in .build, which a cloud-synced checkout fights it for. The native
# engine is deprecated but still builds exactly what has shipped so far; when
# it is removed, this needs --scratch-path outside the synced folder plus an
# install_name_tool -add_rpath @loader_path on the copied binary.
SWIFT_BUILD=(swift build --build-system native -c "$CONFIG" "${ARCHS[@]}" --product Folia)

say "Compiling Swift ($CONFIG)"
"${SWIFT_BUILD[@]}" || die "swift build failed"

BIN_PATH="$("${SWIFT_BUILD[@]}" --show-bin-path 2>/dev/null)"
[[ -x "$BIN_PATH/Folia" ]] || die "binary not found at $BIN_PATH/Folia"

# ---------------------------------------------------------------- icon -----
say "Rendering app icon"
ICON_SRC="Sources/Folia/Resources/AppIcon.png"
ICONSET="build/Folia.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if [[ -f "$ICON_SRC" ]]; then
  # (pixel size, iconutil filename) pairs for a complete .iconset.
  variants=(16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x
            128:icon_128x128 256:icon_128x128@2x 256:icon_256x256
            512:icon_256x256@2x 512:icon_512x512 1024:icon_512x512@2x)
  for variant in "${variants[@]}"; do
    px="${variant%%:*}"; name="${variant##*:}"
    sips -z "$px" "$px" "$ICON_SRC" --out "$ICONSET/$name.png" >/dev/null 2>&1
  done
  iconutil -c icns "$ICONSET" -o "build/Folia.icns" 2>/dev/null || true
fi

# -------------------------------------------------------------- bundle -----
say "Assembling $APP_NAME.app"
APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Folia" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM links Sparkle with an @loader_path rpath (no Xcode-style Frameworks
# embedding here), so the framework has to sit right next to the binary.
[[ -d "$BIN_PATH/Sparkle.framework" ]] || die "Sparkle.framework not found at $BIN_PATH — swift build did not produce it"
cp -R "$BIN_PATH/Sparkle.framework" "$APP/Contents/MacOS/Sparkle.framework"
# SwiftPM's extracted copy carries com.apple.provenance (from the downloaded
# artifact), which codesign refuses to sign over.
xattr -cr "$APP/Contents/MacOS/Sparkle.framework"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    Sources/Folia/Resources/Info.plist > "$APP/Contents/Info.plist"
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

[[ -f build/Folia.icns ]] && cp build/Folia.icns "$APP/Contents/Resources/Folia.icns"

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
