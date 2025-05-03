#!/usr/bin/env bash
# -------------------------------------------------------
#  Aseprite macOS-arm64 Build & Installer
# -------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ---------- Paths ----------
DEPS_DIR="$HOME/deps"
WORKSPACE="$HOME/workspace/c++"
REPO_DIR="$WORKSPACE/aseprite"
BUILD_DIR="$REPO_DIR/build"

SKIA_VERSION="m124-08a5439a6b"
SKIA_ZIP="Skia-macOS-Release-arm64.zip"
SKIA_URL="https://github.com/aseprite/skia/releases/download/${SKIA_VERSION}/${SKIA_ZIP}"

DEPOT_DIR="$DEPS_DIR/depot_tools"

APP="Aseprite.app"
DEST="/Applications/${APP}"
JOBS=$(sysctl -n hw.ncpu)

CLEAN=false
[[ ${1:-} == "--clean" ]] && CLEAN=true

# ---------- Utilities ----------
log() { printf "\033[32m==> %s\033[0m\n" "$1"; }
cmd() {
    printf "   \033[34m• %s\033[0m\n" "$*"
    "$@"
}

# ---------- Folders ----------
log "Creating folders"
$CLEAN && cmd rm -rf "$REPO_DIR" "$DEPS_DIR/skia" "$DEPS_DIR/depot_tools"
mkdir -p "$DEPS_DIR" "$WORKSPACE"

# ---------- Homebrew & packages ----------
if ! command -v brew &>/dev/null; then
    printf "Homebrew missing – install from https://brew.sh and re-run.\n"
    exit 1
fi
eval "$(brew shellenv)"
for p in cmake ninja git imagemagick; do
    brew list "$p" &>/dev/null || cmd brew install --quiet "$p"
done

# ---------- depot_tools ----------
if [[ ! -d "$DEPOT_DIR/.git" ]]; then
    log "Cloning depot_tools"
    cmd git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$DEPOT_DIR"
fi
# persist in shell startup file
PROFILE="$HOME/.zsh_env"
[[ -f $PROFILE ]] || PROFILE="$HOME/.zshrc"
if ! grep -q "$DEPOT_DIR" "$PROFILE" 2>/dev/null; then
    log "Adding depot_tools to PATH in $(basename "$PROFILE")"
    echo "export PATH=\"$DEPOT_DIR:\$PATH\"" >>"$PROFILE"
fi
export PATH="$DEPOT_DIR:$PATH"

# ---------- Skia ----------
if [[ ! -d "$DEPS_DIR/skia" ]]; then
    log "Downloading Skia arm64 ${SKIA_VERSION}"
    pushd "$DEPS_DIR" >/dev/null
    cmd curl -L -O "$SKIA_URL"
    cmd unzip -q "$SKIA_ZIP" -d skia
    cmd rm "$SKIA_ZIP"
    popd >/dev/null
fi

# ---------- Aseprite source ----------
if [[ ! -d "$REPO_DIR/.git" ]]; then
    log "Cloning Aseprite"
    cmd git clone --recursive https://github.com/aseprite/aseprite.git "$REPO_DIR"
else
    log "Updating Aseprite"
    pushd "$REPO_DIR" >/dev/null
    cmd git pull --ff-only
    cmd git submodule update --init --recursive
    popd >/dev/null
fi

# ---------- Build ----------
log "Configuring CMake"
mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null
cmd cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="$DEPS_DIR/skia" \
    -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-arm64" \
    -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-arm64/libskia.a" \
    -GNinja ..
log "Building ($JOBS threads)"
cmd ninja -j"$JOBS" aseprite
popd >/dev/null

# ---------- Bundle ----------
log "Creating ${APP}"
pushd "$BUILD_DIR" >/dev/null
rm -rf "$APP"
mkdir -p "$APP/Contents/"{MacOS,Resources}
cmd cp bin/aseprite "$APP/Contents/MacOS/"
cmd cp -R bin/data "$APP/Contents/Resources/"

# icon
ICON="$APP/Contents/Resources/data/icons/ase256.png"
if [[ -f "$ICON" && ! -f "$APP/Contents/Resources/Aseprite.icns" ]]; then
    TMP=/tmp/ase1024.png
    cmd magick "$ICON" -filter Lanczos -resize 1024x1024 "$TMP"
    ICONSET=$(mktemp -d)
    for s in 16 32 64 128 256 512; do
        sips -z $s $s "$TMP" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        [[ $s -eq 512 ]] && cp "$TMP" "$ICONSET/icon_${s}x${s}@2x.png" ||
            sips -z $((s * 2)) $((s * 2)) "$TMP" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    cmd iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Aseprite.icns"
    cmd rm -rf "$ICONSET" "$TMP"
fi

# Info.plist
cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key>       <string>aseprite</string>
  <key>CFBundleIdentifier</key>       <string>org.aseprite.app</string>
  <key>CFBundleName</key>             <string>Aseprite</string>
  <key>CFBundleIconFile</key>         <string>Aseprite</string>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>LSMinimumSystemVersion</key>   <string>11.0</string>
  <key>LSMinimumSystemVersion</key>   <true/>
  <string>11.0</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
</dict></plist>
PLIST
popd >/dev/null

# ---------- Install ----------
log "Installing to /Applications"
if [[ -w "/Applications" ]]; then
    cmd rsync -a --delete "$BUILD_DIR/$APP" "$DEST"
else
    cmd sudo rsync -a --delete "$BUILD_DIR/$APP" "$DEST"
fi
cmd codesign --force --options=runtime --deep -s - "$DEST" # ad-hoc sign
cmd xattr -dr com.apple.quarantine "$DEST"

log "✅  Build complete – launch Aseprite from /Applications."

# --- Create Info.plist ---
cat <<EOF >"$APP_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>aseprite</string>
    <key>CFBundleIdentifier</key>
    <string>com.aseprite.app</string>
    <key>CFBundleName</key>
    <string>Aseprite</string>
    <key>CFBundleIconFile</key>
    <string>Aseprite.icns</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <string>11.0</string>
</dict>
</plist>
EOF

# --- Finalize ---
mv "$APP_NAME" "$HOME/Desktop/"
echo "Build complete: ~/Desktop/Aseprite.app"
