#!/usr/bin/env bash
# -------------------------------------------------------
#  Aseprite macOS-arm64 Build & Installer (Improved)
# -------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ---------- Locations ----------
DEPS_DIR="$HOME/deps"           # Skia + depot_tools
WORKSPACE="$HOME/workspace/c++" # Aseprite source
REPO_DIR="$WORKSPACE/aseprite"
BUILD_DIR="$REPO_DIR/build"

SKIA_VERSION="m124-08a5439a6b"
SKIA_ZIP="Skia-macOS-Release-arm64.zip"
SKIA_URL="https://github.com/aseprite/skia/releases/download/${SKIA_VERSION}/${SKIA_ZIP}"

DEPOT_DIR="$DEPS_DIR/depot_tools"

APP="Aseprite.app"
DEST="$HOME/Applications/$APP" # user-local install
JOBS=$(sysctl -n hw.ncpu)

CLEAN=false
[[ ${1:-} == "--clean" ]] && CLEAN=true

# ---------- helpers ----------
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue() { printf "\033[34m• %s\033[0m\n" "$*"; }
doit() {
    blue "$*"
    "$@"
}
die() {
    printf "\033[31m%s\033[0m\n" "$*"
    exit 1
}

# ---------- Folders ----------
green "Preparing folders"
$CLEAN && doit rm -rf "$REPO_DIR" "$DEPS_DIR/skia"
mkdir -p "$DEPS_DIR" "$WORKSPACE"

# ---------- Homebrew toolchain ----------
command -v brew >/dev/null || die "Install Homebrew first → https://brew.sh"
eval "$(brew shellenv)"
for pkg in cmake ninja git imagemagick; do
    brew list "$pkg" &>/dev/null || doit brew install --quiet "$pkg"
done

# ---------- depot_tools ----------
if [[ -d "$DEPOT_DIR/.git" ]]; then
    green "Updating depot_tools"
    git -C "$DEPOT_DIR" pull --quiet
else
    green "Cloning depot_tools"
    doit git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$DEPOT_DIR"
fi
export PATH="$DEPOT_DIR:$PATH"
PROFILE="${HOME}/.zsh_env"
[[ -f $PROFILE ]] || PROFILE="${HOME}/.zshrc"
grep -q "$DEPOT_DIR" "$PROFILE" 2>/dev/null || echo "export PATH=\"$DEPOT_DIR:\$PATH\"" >>"$PROFILE"

# ---------- Skia ----------
green "Refreshing Skia $SKIA_VERSION"
doit rm -rf "$DEPS_DIR/skia"
pushd "$DEPS_DIR" >/dev/null
doit curl -sSL -O "$SKIA_URL"
doit unzip -q "$SKIA_ZIP" -d skia
rm "$SKIA_ZIP"
popd >/dev/null

# ---------- Aseprite ----------
if [[ -d "$REPO_DIR/.git" ]]; then
    green "Updating Aseprite"
    git -C "$REPO_DIR" pull --ff-only
    git -C "$REPO_DIR" submodule update --init --recursive
else
    green "Cloning Aseprite"
    doit git clone --recursive https://github.com/aseprite/aseprite.git "$REPO_DIR"
fi

# ---------- Build ----------
green "Configuring CMake"
mkdir -p "$BUILD_DIR"
pushd "$BUILD_DIR" >/dev/null
doit cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="$DEPS_DIR/skia" \
    -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-arm64" \
    -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-arm64/libskia.a" \
    -GNinja ..
green "Building using $JOBS cores"
doit ninja -j"$JOBS" aseprite
popd >/dev/null

# ---------- Bundle ----------
green "Bundling $APP"
pushd "$BUILD_DIR" >/dev/null
doit rm -rf "$APP"
doit mkdir -p "$APP/Contents/"{MacOS,Resources}
doit cp bin/aseprite "$APP/Contents/MacOS/"
doit cp -R bin/data "$APP/Contents/Resources/"

# --- Improved Icon generation ---
green "Generating application icon"
ICON_SRC="$APP/Contents/Resources/data/icons/ase256.png"
ICONSET_DIR="$BUILD_DIR/Aseprite.iconset"
doit rm -rf "$ICONSET_DIR"
doit mkdir -p "$ICONSET_DIR"

# Create iconset with proper sizes for macOS
doit sips -z 16 16 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
doit sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null

doit sips -z 32 32 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
doit sips -z 64 64 "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null

doit sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
doit sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null

doit sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
doit sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null

doit sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null

# Use imagemagick for high-quality 1024×1024 icon
doit magick "$ICON_SRC" -filter Lanczos -resize 1024x1024 "$ICONSET_DIR/icon_512x512@2x.png"

# Generate .icns file from the iconset
green "Converting iconset to .icns format"
doit iconutil -c icns "$ICONSET_DIR" -o "$APP/Contents/Resources/Aseprite.icns"

# Create Info.plist file
green "Creating Info.plist"
cat >"$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key>       <string>aseprite</string>
  <key>CFBundleIdentifier</key>       <string>org.aseprite.app</string>
  <key>CFBundleName</key>             <string>Aseprite</string>
  <key>CFBundleIconFile</key>         <string>Aseprite</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>LSMinimumSystemVersion</key>   <string>11.0</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>ase</string>
        <string>aseprite</string>
      </array>
      <key>CFBundleTypeName</key>
      <string>Aseprite Document</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
    </dict>
  </array>
</dict></plist>
PLIST

popd >/dev/null

# ---------- Install ----------
green "Installing Aseprite to ~/Applications"
doit mkdir -p "$HOME/Applications"

# Ensure we remove any existing copy to avoid permission issues
if [[ -d "$DEST" ]]; then
    green "Removing existing installation"
    doit rm -rf "$DEST"
fi

# Use ditto for proper macOS bundle copying (preserves attributes)
doit ditto "$BUILD_DIR/$APP" "$DEST"

# Set executable permissions explicitly
doit chmod +x "$DEST/Contents/MacOS/aseprite"

# Register the app with Launch Services
green "Registering application with macOS"
doit /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"

green "✅  Done — Aseprite has been installed to ~/Applications"
green "   Launch it from Launchpad or by running: open \"$DEST\""
