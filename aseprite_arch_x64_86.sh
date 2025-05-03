#!/usr/bin/env bash
# -------------------------------------------------------
#  Aseprite Arch Linux Build & Installer (Smart Version)
# -------------------------------------------------------
set -euo pipefail
IFS=

# ---------- Locations ----------
DEPS_DIR="$HOME/deps"           # Skia + depot_tools
WORKSPACE="$HOME/workspace/c++" # Aseprite source
REPO_DIR="$WORKSPACE/aseprite"
BUILD_DIR="$REPO_DIR/build"

SKIA_VERSION="m124-08a5439a6b"
SKIA_ZIP="Skia-Linux-Release-x64.zip"
SKIA_URL="https://github.com/aseprite/skia/releases/download/${SKIA_VERSION}/${SKIA_ZIP}"

DEPOT_DIR="$DEPS_DIR/depot_tools"

DEST="$HOME/.local/bin/aseprite" # user-local install
DESK_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor"
JOBS=$(nproc)

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

# ---------- System dependencies ----------
green "Checking system dependencies"
PKGS="cmake ninja git imagemagick"

# Check if pacman is available (Arch-based systems)
if command -v pacman >/dev/null; then
    for pkg in $PKGS; do
        if ! pacman -Q "$pkg" &>/dev/null; then
            green "Installing $pkg"
            doit sudo pacman -S --needed --noconfirm "$pkg"
        fi
    done
else
    die "This script requires pacman (Arch Linux). Adapt it for your package manager."
fi

# ---------- depot_tools ----------
if [[ -d "$DEPOT_DIR/.git" ]]; then
    green "Checking depot_tools for updates"
    if ! git -C "$DEPOT_DIR" fetch --quiet; then
        green "Fetch failed, re-cloning depot_tools"
        doit rm -rf "$DEPOT_DIR"
        doit git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$DEPOT_DIR"
    else
        DEPOT_LOCAL=$(git -C "$DEPOT_DIR" rev-parse HEAD)
        DEPOT_REMOTE=$(git -C "$DEPOT_DIR" rev-parse @{u})

        if [[ "$DEPOT_LOCAL" != "$DEPOT_REMOTE" ]]; then
            green "Updating depot_tools"
            if ! git -C "$DEPOT_DIR" pull --quiet; then
                green "Pull failed, re-cloning depot_tools"
                doit rm -rf "$DEPOT_DIR"
                doit git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$DEPOT_DIR"
            fi
        else
            green "depot_tools is already up to date"
        fi
    fi
else
    green "Cloning depot_tools"
    doit git clone https://chromium.googlesource.com/chromium/tools/depot_tools "$DEPOT_DIR"
fi
export PATH="$DEPOT_DIR:$PATH"
PROFILE="${HOME}/.bashrc"
[[ -f "$HOME/.zshrc" ]] && PROFILE="${HOME}/.zshrc"
grep -q "$DEPOT_DIR" "$PROFILE" 2>/dev/null || echo "export PATH=\"$DEPOT_DIR:\$PATH\"" >>"$PROFILE"

# ---------- Skia ----------
SKIA_MARKER="$DEPS_DIR/skia/.version_${SKIA_VERSION}"

# Always refresh Skia if it doesn't exist or version marker doesn't match
if [[ ! -d "$DEPS_DIR/skia" || ! -f "$SKIA_MARKER" ]]; then
    green "Refreshing Skia $SKIA_VERSION"
    doit rm -rf "$DEPS_DIR/skia"
    pushd "$DEPS_DIR" >/dev/null

    # Download only if we don't already have the zip
    if [[ ! -f "$DEPS_DIR/$SKIA_ZIP" ]]; then
        green "Downloading Skia"
        doit curl -sSL -O "$SKIA_URL"
    else
        green "Using existing Skia download"
    fi

    green "Extracting Skia"
    doit unzip -q "$SKIA_ZIP" -d skia
    rm -f "$SKIA_ZIP"

    # Create version marker
    touch "$SKIA_MARKER"
    popd >/dev/null
else
    green "Skia $SKIA_VERSION is already installed"
fi

# ---------- Aseprite ----------
if [[ -d "$REPO_DIR/.git" ]]; then
    green "Checking Aseprite for updates"
    if ! git -C "$REPO_DIR" fetch --quiet; then
        green "Fetch failed, re-cloning Aseprite"
        doit rm -rf "$REPO_DIR"
        doit git clone --recursive https://github.com/aseprite/aseprite.git "$REPO_DIR"
        REPO_UPDATED=true
    else
        # Check if we need to update
        REPO_LOCAL=$(git -C "$REPO_DIR" rev-parse HEAD)
        REPO_REMOTE=$(git -C "$REPO_DIR" rev-parse @{u})

        if [[ "$REPO_LOCAL" != "$REPO_REMOTE" ]]; then
            green "Updating Aseprite repository"
            if ! git -C "$REPO_DIR" pull --ff-only; then
                green "Pull failed, re-cloning Aseprite"
                doit rm -rf "$REPO_DIR"
                doit git clone --recursive https://github.com/aseprite/aseprite.git "$REPO_DIR"
            else
                green "Updating submodules"
                git -C "$REPO_DIR" submodule update --init --recursive
            fi
            REPO_UPDATED=true
        else
            green "Aseprite repository is already up to date"
            REPO_UPDATED=false
        fi
    fi
else
    green "Cloning Aseprite"
    doit git clone --recursive https://github.com/aseprite/aseprite.git "$REPO_DIR"
    REPO_UPDATED=true
fi

# ---------- Build ----------
# Check if we need to rebuild
BUILD_NEEDED=true
EXECUTABLE="$BUILD_DIR/bin/aseprite"

# Skip build if repo wasn't updated AND executable exists
if [[ "$REPO_UPDATED" == "false" && -f "$EXECUTABLE" ]]; then
    # Check executable freshness against repo HEAD
    REPO_TIMESTAMP=$(git -C "$REPO_DIR" log -1 --format=%ct HEAD)
    if [[ -n "$REPO_TIMESTAMP" ]]; then
        EXE_TIMESTAMP=$(stat -c %Y "$EXECUTABLE")
        if [[ "$EXE_TIMESTAMP" -gt "$REPO_TIMESTAMP" ]]; then
            green "Build is already up to date (executable is newer than repo HEAD)"
            BUILD_NEEDED=false
        fi
    fi
fi

if [[ "$BUILD_NEEDED" == "true" ]]; then
    green "Configuring CMake"
    mkdir -p "$BUILD_DIR"
    pushd "$BUILD_DIR" >/dev/null

    # Check if CMakeCache.txt exists to determine if we need to run cmake again
    if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
        doit cmake \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DLAF_BACKEND=skia \
            -DSKIA_DIR="$DEPS_DIR/skia" \
            -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-x64" \
            -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-x64/libskia.a" \
            -GNinja ..
    else
        green "CMake cache already exists, skipping configuration"
    fi

    green "Building using $JOBS cores"
    doit ninja -j"$JOBS" aseprite
    popd >/dev/null
else
    green "Skipping build (already up to date)"
fi

# ---------- Install ----------
# Check if installation is needed
INSTALL_NEEDED=true

if [[ -f "$DEST" && "$BUILD_NEEDED" == "false" ]]; then
    # Compare timestamps of executable and installed binary
    EXE_TIMESTAMP=$(stat -c %Y "$EXECUTABLE")
    INSTALLED_TIMESTAMP=$(stat -c %Y "$DEST" 2>/dev/null || echo "0")

    if [[ "$INSTALLED_TIMESTAMP" -ge "$EXE_TIMESTAMP" ]]; then
        green "Installation is already up to date"
        INSTALL_NEEDED=false
    fi
fi

if [[ "$INSTALL_NEEDED" == "true" ]]; then
    green "Installing Aseprite to ~/.local/bin"
    doit mkdir -p "$HOME/.local/bin"

    # Copy executable
    doit cp "$BUILD_DIR/bin/aseprite" "$DEST"
    doit chmod +x "$DEST"

    # Install desktop file
    green "Installing desktop entry"
    doit mkdir -p "$DESK_DIR"

    cat >"$DESK_DIR/aseprite.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aseprite
GenericName=Sprite Editor
Comment=Animated sprite editor & pixel art tool
Exec=$DEST %f
Icon=aseprite
Terminal=false
Categories=Graphics;2DGraphics;RasterGraphics;
MimeType=image/bmp;image/gif;image/jpeg;image/png;image/x-pcx;image/x-tga;image/vnd.microsoft.icon;video/x-flic;image/webp;image/x-aseprite;
EOF

    # Install icons
    green "Installing icons"
    ICON_SRC="$REPO_DIR/data/icons/ase256.png"

    for size in 16 32 48 64 128 256; do
        DIR="$ICON_DIR/${size}x${size}/apps"
        doit mkdir -p "$DIR"
        doit convert "$ICON_SRC" -resize ${size}x${size} "$DIR/aseprite.png"
    done

    # Update icon cache
    if command -v gtk-update-icon-cache >/dev/null; then
        green "Updating icon cache"
        doit gtk-update-icon-cache -f -t "$ICON_DIR"
    fi

    green "✅  Done — Aseprite has been freshly installed to ~/.local/bin"
else
    green "✅  Done — Aseprite is already up to date in ~/.local/bin"
fi

green "   Launch it by running: aseprite"
green "   Or find it in your applications menu"
