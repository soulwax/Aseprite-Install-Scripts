#!/bin/bash
# Arch Linux Aseprite Builder (clang/libc++ enforced, Skia prebuilt, no GCC)
set -eo pipefail

# --- Configuration ---
BUILD_DIR="$HOME/aseprite-build"
DEPS_DIR="$HOME/deps"
SKIA_VERSION="m124-08a5439a6b"
SKIA_URL="https://github.com/aseprite/skia/releases/download/$SKIA_VERSION/Skia-Linux-Release-x64.zip"
APP_DIR="$HOME/.local/share/aseprite"

# --- Dependency Check ---
echo "Installing required packages (clang, libc++, cmake, ninja, etc)..."
sudo pacman -Sy --needed --noconfirm \
    clang llvm libc++ cmake ninja git unzip \
    libx11 libxcursor mesa libxi fontconfig libpng libwebp harfbuzz

# --- Clean Previous Builds ---
rm -rf "$BUILD_DIR" "$DEPS_DIR"
mkdir -p "$BUILD_DIR" "$DEPS_DIR"

# --- Fetch Skia ---
echo "Downloading and extracting Skia..."
curl -L "$SKIA_URL" -o /tmp/skia.zip
unzip -q /tmp/skia.zip -d "$DEPS_DIR/skia"
rm /tmp/skia.zip

# --- Clone Aseprite ---
echo "Cloning Aseprite source..."
git clone --recursive --depth 1 https://github.com/aseprite/aseprite.git "$BUILD_DIR"
cd "$BUILD_DIR"

# --- Build ---
mkdir -p build
cd build

export CC=clang
export CXX=clang++
export CXXFLAGS="-stdlib=libc++"
export LDFLAGS="-stdlib=libc++"

echo "Configuring CMake for clang/libc++ and Skia..."
cmake \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_FLAGS="-stdlib=libc++" \
    -DCMAKE_EXE_LINKER_FLAGS="-stdlib=libc++" \
    -DLAF_BACKEND=skia \
    -DSKIA_DIR="$DEPS_DIR/skia" \
    -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-x64" \
    -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-x64/libskia.a" \
    -G Ninja \
    ..

echo "Building Aseprite with Ninja..."
ninja aseprite

# --- Install ---
echo "Installing to $APP_DIR..."
mkdir -p "$APP_DIR"
cp bin/aseprite "$APP_DIR/"
cp -r bin/data "$APP_DIR/"

# --- Optional: Desktop Entry ---
read -p "Create desktop entry? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ICON_PATH="$APP_DIR/data/icons/ase256.png"
    DESKTOP_FILE="$HOME/.local/share/applications/aseprite.desktop"
    cat <<EOF >"$DESKTOP_FILE"
[Desktop Entry]
Type=Application
Name=Aseprite
Exec=$APP_DIR/aseprite
Icon=$ICON_PATH
Categories=Graphics;2DGraphics;
Comment=Animated sprite editor & pixel art tool
EOF
    echo "Desktop entry created: $DESKTOP_FILE"
fi

echo "Build successful! Run with: $APP_DIR/aseprite"
