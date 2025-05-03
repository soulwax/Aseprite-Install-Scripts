# -------------------------------------------------------
#  Aseprite Windows Build & Installer (Smart Version)
# -------------------------------------------------------
param (
    [switch]$Clean = $false
)

# ---------- Locations ----------
$DEPS_DIR = "$env:USERPROFILE\deps"
$WORKSPACE = "$env:USERPROFILE\workspace\cpp"
$REPO_DIR = "$WORKSPACE\aseprite"
$BUILD_DIR = "$REPO_DIR\build"

$SKIA_VERSION = "m124-08a5439a6b"
$SKIA_ZIP = "Skia-Windows-Release-x64.zip"
$SKIA_URL = "https://github.com/aseprite/skia/releases/download/$SKIA_VERSION/$SKIA_ZIP"

$DEPOT_DIR = "$DEPS_DIR\depot_tools"

$DEST_DIR = "$env:LOCALAPPDATA\Programs\Aseprite"
$JOBS = [Environment]::ProcessorCount

# ---------- Helper Functions ----------
function Write-Green {
    param ([string]$Text)
    Write-Host $Text -ForegroundColor Green
}

function Write-Blue {
    param ([string]$Text)
    Write-Host "• $Text" -ForegroundColor Blue
}

function Invoke-Command {
    param ([string]$Text, [scriptblock]$ScriptBlock)
    Write-Blue $Text
    & $ScriptBlock
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Command failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

# ---------- Check Requirements ----------
function Test-CommandExists {
    param ([string]$Command)
    return [bool](Get-Command -Name $Command -ErrorAction SilentlyContinue)
}

# Check for Visual Studio
if (-not (Test-Path "C:\Program Files\Microsoft Visual Studio")) {
    Write-Host "Visual Studio is required. Please install Visual Studio 2019 or newer with C++ support." -ForegroundColor Red
    exit 1
}

# Check for required tools
$tools = @("git", "cmake", "ninja")
foreach ($tool in $tools) {
    if (-not (Test-CommandExists $tool)) {
        Write-Host "$tool is required but not found in PATH." -ForegroundColor Red
        exit 1
    }
}

# ---------- Folders ----------
Write-Green "Preparing folders"
if ($Clean) {
    Invoke-Command "Cleaning old directories" { 
        Remove-Item -Path $REPO_DIR -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$DEPS_DIR\skia" -Recurse -Force -ErrorAction SilentlyContinue
    }
}

New-Item -ItemType Directory -Path $DEPS_DIR -Force | Out-Null
New-Item -ItemType Directory -Path $WORKSPACE -Force | Out-Null

# ---------- depot_tools ----------
$REPO_UPDATED = $true

if (Test-Path "$DEPOT_DIR\.git") {
    Write-Green "Checking depot_tools for updates"
    try {
        Push-Location $DEPOT_DIR
        Invoke-Command "Fetching updates" { git fetch --quiet }
        $DEPOT_LOCAL = git rev-parse HEAD
        $DEPOT_REMOTE = git rev-parse "@{u}"
        
        if ($DEPOT_LOCAL -ne $DEPOT_REMOTE) {
            Write-Green "Updating depot_tools"
            Invoke-Command "Pulling updates" { git pull --quiet }
        } else {
            Write-Green "depot_tools is already up to date"
        }
        Pop-Location
    } catch {
        Write-Green "Git operations failed, re-cloning depot_tools"
        Remove-Item -Path $DEPOT_DIR -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-Command "Cloning depot_tools" { 
            git clone https://chromium.googlesource.com/chromium/tools/depot_tools $DEPOT_DIR 
        }
    }
} else {
    Write-Green "Cloning depot_tools"
    Invoke-Command "Cloning depot_tools" { 
        git clone https://chromium.googlesource.com/chromium/tools/depot_tools $DEPOT_DIR 
    }
}

# Add depot_tools to PATH
$env:PATH = "$DEPOT_DIR;$env:PATH"

# ---------- Skia ----------
$SKIA_MARKER = "$DEPS_DIR\skia\.version_$SKIA_VERSION"

# Always refresh Skia if it doesn't exist or version marker doesn't match
if (-not (Test-Path "$DEPS_DIR\skia") -or -not (Test-Path $SKIA_MARKER)) {
    Write-Green "Refreshing Skia $SKIA_VERSION"
    Remove-Item -Path "$DEPS_DIR\skia" -Recurse -Force -ErrorAction SilentlyContinue
    Push-Location $DEPS_DIR

    # Download only if we don't already have the zip
    if (-not (Test-Path "$DEPS_DIR\$SKIA_ZIP")) {
        Write-Green "Downloading Skia"
        Invoke-Command "Downloading Skia" { 
            Invoke-WebRequest -Uri $SKIA_URL -OutFile $SKIA_ZIP 
        }
    } else {
        Write-Green "Using existing Skia download"
    }

    Write-Green "Extracting Skia"
    Invoke-Command "Extracting Skia" { 
        Expand-Archive -Path $SKIA_ZIP -DestinationPath skia -Force
    }
    Remove-Item -Path $SKIA_ZIP -ErrorAction SilentlyContinue

    # Create version marker
    New-Item -ItemType File -Path $SKIA_MARKER -Force | Out-Null
    Pop-Location
} else {
    Write-Green "Skia $SKIA_VERSION is already installed"
}

# ---------- Aseprite ----------
if (Test-Path "$REPO_DIR\.git") {
    Write-Green "Checking Aseprite for updates"
    try {
        Push-Location $REPO_DIR
        Invoke-Command "Fetching updates" { git fetch --quiet }
        
        $REPO_LOCAL = git rev-parse HEAD
        $REPO_REMOTE = git rev-parse "@{u}"
        
        if ($REPO_LOCAL -ne $REPO_REMOTE) {
            Write-Green "Updating Aseprite repository"
            try {
                Invoke-Command "Pulling updates" { git pull --ff-only }
                Write-Green "Updating submodules"
                Invoke-Command "Updating submodules" { git submodule update --init --recursive }
                $REPO_UPDATED = $true
            } catch {
                Write-Green "Pull failed, re-cloning Aseprite"
                Pop-Location
                Remove-Item -Path $REPO_DIR -Recurse -Force -ErrorAction SilentlyContinue
                Invoke-Command "Cloning Aseprite" { 
                    git clone --recursive https://github.com/aseprite/aseprite.git $REPO_DIR 
                }
                $REPO_UPDATED = $true
            }
        } else {
            Write-Green "Aseprite repository is already up to date"
            $REPO_UPDATED = $false
        }
        Pop-Location
    } catch {
        Write-Green "Git operations failed, re-cloning Aseprite"
        Remove-Item -Path $REPO_DIR -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-Command "Cloning Aseprite" { 
            git clone --recursive https://github.com/aseprite/aseprite.git $REPO_DIR 
        }
        $REPO_UPDATED = $true
    }
} else {
    Write-Green "Cloning Aseprite"
    Invoke-Command "Cloning Aseprite" { 
        git clone --recursive https://github.com/aseprite/aseprite.git $REPO_DIR 
    }
    $REPO_UPDATED = $true
}

# ---------- Build ----------
# Check if we need to rebuild
$BUILD_NEEDED = $true
$EXECUTABLE = "$BUILD_DIR\bin\aseprite.exe"

# Skip build if repo wasn't updated AND executable exists
if (-not $REPO_UPDATED -and (Test-Path $EXECUTABLE)) {
    try {
        Push-Location $REPO_DIR
        $REPO_TIMESTAMP = [int](git log -1 --format=%ct HEAD)
        Pop-Location
        
        if ($REPO_TIMESTAMP) {
            $EXE_TIMESTAMP = (Get-Item $EXECUTABLE).LastWriteTime.ToFileTime() / 10000000 - 11644473600
            if ($EXE_TIMESTAMP -gt $REPO_TIMESTAMP) {
                Write-Green "Build is already up to date (executable is newer than repo HEAD)"
                $BUILD_NEEDED = $false
            }
        }
    } catch {
        # If there's any error in the timestamp checking, proceed with the build
        $BUILD_NEEDED = $true
    }
}

if ($BUILD_NEEDED) {
    Write-Green "Configuring CMake"
    New-Item -ItemType Directory -Path $BUILD_DIR -Force | Out-Null
    Push-Location $BUILD_DIR

    # Find Visual Studio installation
    $VS_WHERE = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $VS_WHERE) {
        $VS_PATH = & $VS_WHERE -latest -property installationPath
        if ($VS_PATH) {
            $VS_ENV = "$VS_PATH\Common7\Tools\VsDevCmd.bat"
            if (Test-Path $VS_ENV) {
                # Use Visual Studio environment
                Write-Green "Setting up Visual Studio environment"
                $VS_ENV_COMMAND = "`"$VS_ENV`" -arch=amd64 -host_arch=amd64"
                $VCVARS = cmd /c "$VS_ENV_COMMAND && set"
                foreach ($line in $VCVARS) {
                    if ($line -match "^(.*?)=(.*)$") {
                        $name = $matches[1]
                        $value = $matches[2]
                        Set-Item -Path "env:$name" -Value $value
                    }
                }
            }
        }
    }

    # Check if CMakeCache.txt exists to determine if we need to run cmake again
    if (-not (Test-Path "$BUILD_DIR\CMakeCache.txt")) {
        Invoke-Command "Running CMake" { 
            cmake `
                -DCMAKE_BUILD_TYPE=RelWithDebInfo `
                -DLAF_BACKEND=skia `
                -DSKIA_DIR="$DEPS_DIR\skia" `
                -DSKIA_LIBRARY_DIR="$DEPS_DIR\skia\out\Release-x64" `
                -DSKIA_LIBRARY="$DEPS_DIR\skia\out\Release-x64\skia.lib" `
                -GNinja ..
        }
    } else {
        Write-Green "CMake cache already exists, skipping configuration"
    }

    Write-Green "Building using $JOBS cores"
    Invoke-Command "Building Aseprite" { ninja -j $JOBS aseprite }
    Pop-Location
} else {
    Write-Green "Skipping build (already up to date)"
}

# ---------- Install ----------
# Check if installation is needed
$INSTALL_NEEDED = $true

if (Test-Path "$DEST_DIR\aseprite.exe" -and -not $BUILD_NEEDED) {
    # Compare timestamps of executable and installed binary
    $EXE_TIMESTAMP = (Get-Item $EXECUTABLE).LastWriteTime.Ticks
    $INSTALLED_TIMESTAMP = (Get-Item "$DEST_DIR\aseprite.exe").LastWriteTime.Ticks
    
    if ($INSTALLED_TIMESTAMP -ge $EXE_TIMESTAMP) {
        Write-Green "Installation is already up to date"
        $INSTALL_NEEDED = $false
    }
}

if ($INSTALL_NEEDED) {
    Write-Green "Installing Aseprite to $DEST_DIR"
    
    # Create destination directory
    New-Item -ItemType Directory -Path $DEST_DIR -Force | Out-Null
    
    # Copy executable and data files
    Invoke-Command "Copying executable" { 
        Copy-Item -Path "$BUILD_DIR\bin\aseprite.exe" -Destination "$DEST_DIR\aseprite.exe" -Force 
    }
    
    Invoke-Command "Copying data files" { 
        if (Test-Path "$DEST_DIR\data") {
            Remove-Item -Path "$DEST_DIR\data" -Recurse -Force
        }
        Copy-Item -Path "$BUILD_DIR\bin\data" -Destination "$DEST_DIR\data" -Recurse -Force
    }
    
    # Create shortcut
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut("$env:USERPROFILE\Desktop\Aseprite.lnk")
    $Shortcut.TargetPath = "$DEST_DIR\aseprite.exe"
    $Shortcut.IconLocation = "$DEST_DIR\data\icons\ase256.ico"
    $Shortcut.Save()
    
    # Create Start Menu shortcut
    $StartMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Aseprite"
    New-Item -ItemType Directory -Path $StartMenuPath -Force | Out-Null
    $Shortcut = $WshShell.CreateShortcut("$StartMenuPath\Aseprite.lnk")
    $Shortcut.TargetPath = "$DEST_DIR\aseprite.exe"
    $Shortcut.IconLocation = "$DEST_DIR\data\icons\ase256.ico"
    $Shortcut.Save()
    
    Write-Green "✅  Done — Aseprite has been freshly installed"
} else {
    Write-Green "✅  Done — Aseprite is already up to date"
}

Write-Green "   Launch from the Start Menu, Desktop shortcut, or by running: $DEST_DIR\aseprite.exe"