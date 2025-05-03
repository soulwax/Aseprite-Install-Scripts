#!/bin/bash
# Aseprite Apple Silicon Bundler (M1/M2/M3)
set -eo pipefail

# --- Configuration ---
BUILD_DIR="$HOME/aseprite-build"
DEPS_DIR="$HOME/deps"
APP_NAME="Aseprite.app"
SKIA_VERSION="m124-08a5439a6b"

# --- Homebrew Check ---
install_brew() {
    echo "Homebrew is required but not installed."
    read -p "Would you like to install Homebrew now? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add Homebrew to PATH for current session
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    else
        echo "Aborting: Homebrew is required to continue."
        exit 1
    fi
}

# Check for Homebrew installation
if ! command -v brew &>/dev/null; then
    install_brew
fi

# --- Clean Previous Builds ---
rm -rf "$BUILD_DIR" "$DEPS_DIR"
mkdir -p "$BUILD_DIR" "$DEPS_DIR"

# --- Install Dependencies ---
brew update
brew install --quiet cmake ninja git imagemagick
brew install --cask --quiet xquartz

# --- Fetch Skia ---
echo "Downloading Skia..."
curl -LO "https://github.com/aseprite/skia/releases/download/$SKIA_VERSION/Skia-macOS-Release-arm64.zip"
unzip -q "Skia-macOS-Release-arm64.zip" -d "$DEPS_DIR/skia"

# --- Clone Aseprite ---
git clone --recursive --depth 1 https://github.com/aseprite/aseprite.git "$BUILD_DIR"
cd "$BUILD_DIR"

# --- Icon Preprocessing ---
ICON_SRC="data/icons/ase256.png"
if [ -f "$ICON_SRC" ]; then
    echo "Upscaling source icon..."
    magick "$ICON_SRC" -filter Lanczos -resize 400% -unsharp 1.5x1+0.7+0.02 "/tmp/ase1024.png"
    mv -f "/tmp/ase1024.png" "$ICON_SRC"
fi

# --- Build Configuration ---
mkdir -p build
cd build

cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="$DEPS_DIR/skia" \
    -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-arm64" \
    -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-arm64/libskia.a" \
    -G Ninja \
    ..

# --- Compile ---
echo "Building Aseprite..."
ninja aseprite

# --- Create App Bundle ---
echo "Creating application bundle..."
mkdir -p "$APP_NAME/Contents/"{MacOS,Resources}
cp bin/aseprite "$APP_NAME/Contents/MacOS/"
cp -r bin/data "$APP_NAME/Contents/Resources/"

# --- Generate Icon Set ---
ICON_SRC="$APP_NAME/Contents/Resources/data/icons/ase256.png"
ICONSET_DIR="aseprite.iconset"

mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$APP_NAME/Contents/Resources/Aseprite.icns"
rm -rf "$ICONSET_DIR"

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
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
</dict>
</plist>
EOF

# --- Finalize ---
mv "$APP_NAME" "$HOME/Desktop/"
echo "Build complete: ~/Desktop/Aseprite.app"
