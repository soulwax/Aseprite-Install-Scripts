#!/usr/bin/env bash
# -------------------------------------------------------
#  Aseprite macOS-arm64 Build & Installer (Smart Version)
# -------------------------------------------------------
set -euo pipefail
IFS=

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
PROFILE="${HOME}/.zsh_env"
[[ -f $PROFILE ]] || PROFILE="${HOME}/.zshrc"
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
        EXE_TIMESTAMP=$(stat -f %m "$EXECUTABLE")
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
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
            -DLAF_BACKEND=skia \
            -DSKIA_DIR="$DEPS_DIR/skia" \
            -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-arm64" \
            -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-arm64/libskia.a" \
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

# ---------- Bundle ----------
green "Bundling $APP"
pushd "$BUILD_DIR" >/dev/null

# Check if we need to create a new bundle
BUNDLE_NEEDED=true

if [[ "$BUILD_NEEDED" == "false" && -d "$APP" && -f "$APP/Contents/MacOS/aseprite" ]]; then
    # Compare timestamps of executable and bundle
    EXE_TIMESTAMP=$(stat -f %m "$EXECUTABLE")
    BUNDLE_TIMESTAMP=$(stat -f %m "$APP/Contents/MacOS/aseprite")

    if [[ "$BUNDLE_TIMESTAMP" -ge "$EXE_TIMESTAMP" ]]; then
        green "Bundle is already up to date"
        BUNDLE_NEEDED=false
    fi
fi

if [[ "$BUNDLE_NEEDED" == "true" ]]; then
    doit rm -rf "$APP"
    doit mkdir -p "$APP/Contents/"{MacOS,Resources}
    doit cp bin/aseprite "$APP/Contents/MacOS/"
    doit cp -R bin/data "$APP/Contents/Resources/"
else
    green "Skipping bundle creation (already up to date)"
fi

# --- Improved Icon generation ---
if [[ "$BUNDLE_NEEDED" == "true" ]]; then
    green "Generating application icon"
    ICON_SRC="$APP/Contents/Resources/data/icons/ase256.png"
    ICONSET_DIR="$BUILD_DIR/Aseprite.iconset"
    ICNS_FILE="$APP/Contents/Resources/Aseprite.icns"

    # Check if we need to regenerate the icon
    ICON_NEEDED=true
    if [[ -f "$ICNS_FILE" && -f "$ICON_SRC" ]]; then
        ICON_TIMESTAMP=$(stat -f %m "$ICON_SRC")
        ICNS_TIMESTAMP=$(stat -f %m "$ICNS_FILE")

        if [[ "$ICNS_TIMESTAMP" -ge "$ICON_TIMESTAMP" ]]; then
            green "Icon is already up to date"
            ICON_NEEDED=false
        fi
    fi

    if [[ "$ICON_NEEDED" == "true" ]]; then
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
        doit iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
    fi
else
    green "Skipping icon generation (bundle already up to date)"
fi

# Create Info.plist file
if [[ "$BUNDLE_NEEDED" == "true" ]]; then
    green "Creating Info.plist"
    PLIST_FILE="$APP/Contents/Info.plist"

    cat >"$PLIST_FILE" <<'PLIST'
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
else
    green "Skipping Info.plist creation (bundle already up to date)"
fi

popd >/dev/null

# ---------- Install ----------
# Check if installation is needed
INSTALL_NEEDED=true

if [[ -d "$DEST" && -f "$DEST/Contents/MacOS/aseprite" && "$BUNDLE_NEEDED" == "false" ]]; then
    # Compare timestamps of bundle and installed app
    BUNDLE_TIMESTAMP=$(stat -f %m "$BUILD_DIR/$APP/Contents/MacOS/aseprite" 2>/dev/null || echo "0")
    INSTALLED_TIMESTAMP=$(stat -f %m "$DEST/Contents/MacOS/aseprite" 2>/dev/null || echo "0")

    if [[ "$INSTALLED_TIMESTAMP" -ge "$BUNDLE_TIMESTAMP" ]]; then
        green "Installation is already up to date"
        INSTALL_NEEDED=false
    fi
fi

if [[ "$INSTALL_NEEDED" == "true" ]]; then
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

    green "✅  Done — Aseprite has been freshly installed to ~/Applications"
else
    green "✅  Done — Aseprite is already up to date in ~/Applications"
fi

green "   Launch it from Launchpad or by running: open \"$DEST\""

# Set default variable values
REPO_UPDATED=true
BUILD_NEEDED=true
BUNDLE_NEEDED=true

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
PROFILE="${HOME}/.zsh_env"
[[ -f $PROFILE ]] || PROFILE="${HOME}/.zshrc"
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
        EXE_TIMESTAMP=$(stat -f %m "$EXECUTABLE")
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
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
            -DLAF_BACKEND=skia \
            -DSKIA_DIR="$DEPS_DIR/skia" \
            -DSKIA_LIBRARY_DIR="$DEPS_DIR/skia/out/Release-arm64" \
            -DSKIA_LIBRARY="$DEPS_DIR/skia/out/Release-arm64/libskia.a" \
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

# ---------- Bundle ----------
green "Bundling $APP"
pushd "$BUILD_DIR" >/dev/null

# Check if we need to create a new bundle
BUNDLE_NEEDED=true

if [[ "$BUILD_NEEDED" == "false" && -d "$APP" && -f "$APP/Contents/MacOS/aseprite" ]]; then
    # Compare timestamps of executable and bundle
    EXE_TIMESTAMP=$(stat -f %m "$EXECUTABLE")
    BUNDLE_TIMESTAMP=$(stat -f %m "$APP/Contents/MacOS/aseprite")

    if [[ "$BUNDLE_TIMESTAMP" -ge "$EXE_TIMESTAMP" ]]; then
        green "Bundle is already up to date"
        BUNDLE_NEEDED=false
    fi
fi

if [[ "$BUNDLE_NEEDED" == "true" ]]; then
    doit rm -rf "$APP"
    doit mkdir -p "$APP/Contents/"{MacOS,Resources}
    doit cp bin/aseprite "$APP/Contents/MacOS/"
    doit cp -R bin/data "$APP/Contents/Resources/"
else
    green "Skipping bundle creation (already up to date)"
fi

# --- Improved Icon generation ---
if [[ "$BUNDLE_NEEDED" == "true" ]]; then
    green "Generating application icon"
    ICON_SRC="$APP/Contents/Resources/data/icons/ase256.png"
    ICONSET_DIR="$BUILD_DIR/Aseprite.iconset"
    ICNS_FILE="$APP/Contents/Resources/Aseprite.icns"

    # Check if we need to regenerate the icon
    ICON_NEEDED=true
    if [[ -f "$ICNS_FILE" && -f "$ICON_SRC" ]]; then
        ICON_TIMESTAMP=$(stat -f %m "$ICON_SRC")
        ICNS_TIMESTAMP=$(stat -f %m "$ICNS_FILE")

        if [[ "$ICNS_TIMESTAMP" -ge "$ICON_TIMESTAMP" ]]; then
            green "Icon is already up to date"
            ICON_NEEDED=false
        fi
    fi

    if [[ "$ICON_NEEDED" == "true" ]]; then
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
        doit iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
    fi
else
    green "Skipping icon generation (bundle already up to date)"
fi

# Create Info.plist file
if [[ "$BUNDLE_NEEDED" == "true" ]]; then
    green "Creating Info.plist"
    PLIST_FILE="$APP/Contents/Info.plist"

    cat >"$PLIST_FILE" <<'PLIST'
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
else
    green "Skipping Info.plist creation (bundle already up to date)"
fi

popd >/dev/null

# ---------- Install ----------
# Check if installation is needed
INSTALL_NEEDED=true

if [[ -d "$DEST" && -f "$DEST/Contents/MacOS/aseprite" && "$BUNDLE_NEEDED" == "false" ]]; then
    # Compare timestamps of bundle and installed app
    BUNDLE_TIMESTAMP=$(stat -f %m "$BUILD_DIR/$APP/Contents/MacOS/aseprite" 2>/dev/null || echo "0")
    INSTALLED_TIMESTAMP=$(stat -f %m "$DEST/Contents/MacOS/aseprite" 2>/dev/null || echo "0")

    if [[ "$INSTALLED_TIMESTAMP" -ge "$BUNDLE_TIMESTAMP" ]]; then
        green "Installation is already up to date"
        INSTALL_NEEDED=false
    fi
fi

if [[ "$INSTALL_NEEDED" == "true" ]]; then
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

    green "✅  Done — Aseprite has been freshly installed to ~/Applications"
else
    green "✅  Done — Aseprite is already up to date in ~/Applications"
fi

green "   Launch it from Launchpad or by running: open \"$DEST\""
