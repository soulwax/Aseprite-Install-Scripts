# (WIP) Aseprite Build Scripts

## WINDOWS

### 1. Install Dependencies

Install [Visual Studio 2022 Community Edition](https://visualstudio.microsoft.com/vs/community/) with C++ Desktop Development component at the very least. You should also install the optional components for CMake and Windows 10 SDK (10.0.19041.0) if you want to build with CMake.

### 2. Install Scoop and with it, the dependencies

Install [scoop](https://scoop.sh/) and run the following command to install the dependencies:

```bash
scoop install 7zip git
scoop bucket add extras
scoop bucket add nonportable
scoop bucket add versions
```

### 3, install the dependencies

```bash
scoop install --global --skip-autoupdate --no-cache 7zip git cmake ninja miniconda3 sudo
```

### Finally, with or without admin rights execute the script, e.g. like

```powershell
.\aseprite_windows_x64_86.ps1 # or with sudo that we installed earlier with scoop
```

1. As admin (CTRL+SHIFT) + click on the script to run it, it will be installed under `C:\ProgramFiles\Aseprite\bin\Release` after the build.

2. Alternatively, if you do not want to execute the script as admin, the finished buuld will be placed in C:\Users\<username>\AppData\Local\Programs\Aseprite\bin\Release.

A Shortcut will be created on the desktop. You can also create a shortcut to the executable in the start menu or taskbar if you want but it is not necessary and should be done manually since it always requires admin rights.

## LINUX (Arch Linux only for now)

---

## MACOS (Apple Silicon only)

The macOS build script provides a smart, incremental build system for Aseprite on Apple Silicon Macs.

### Features

- **Smart Rebuilding**: Only rebuilds when necessary, saving time on subsequent runs
- **Automatic Dependency Management**: Handles Skia, depot_tools, and other dependencies
- **Complete macOS Integration**: Creates a proper `.app` bundle with icons and file associations
- **User-local Installation**: Installs to `~/Applications` without requiring admin privileges

### Requirements

- macOS 11.0 or later on Apple Silicon (M1/M2/M3)
- [Homebrew](https://brew.sh/) for package management
- Internet connection for downloading dependencies

### Usage

```bash
# Normal build
./build-aseprite-macos.sh

# Clean build (removes existing source and dependencies)
./build-aseprite-macos.sh --clean
```

### Build Process

The script performs the following steps:

1. **Setup Environment**:
   - Creates necessary directories
   - Ensures Homebrew and required packages are installed (cmake, ninja, git, imagemagick)

2. **Install Dependencies**:
   - Google depot_tools for building Skia
   - Pre-compiled Skia graphics library

3. **Source Management**:
   - Clones or updates the Aseprite repository and submodules
   - Tracks versions to avoid unnecessary rebuilds

4. **Build**:
   - Configures CMake with optimal settings for Apple Silicon
   - Uses Ninja for faster parallel compilation

5. **Bundle Creation**:
   - Creates a properly structured macOS `.app` bundle
   - Generates high-quality app icons with proper Retina support
   - Creates the Info.plist with file associations

6. **Installation**:
   - Installs to `~/Applications`
   - Registers with macOS Launch Services

### Smart Update System

The script includes intelligence to avoid unnecessary work:

- Skips repository updates when already up-to-date
- Skips rebuilding when the source hasn't changed
- Skips bundle creation when the executable hasn't changed
- Skips installation when the bundle hasn't changed

This means subsequent runs are very fast if no changes are needed!

### Troubleshooting

If you encounter issues:

- Run with `--clean` to start fresh
- Ensure you have at least 10GB of free disk space
- Check that your internet connection is stable for downloading dependencies
- Make sure Homebrew is properly installed and functioning
