#Requires -Version 7.0
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Build and install Aseprite on Windows with modern PowerShell
#>

param (
    [string]$SkiaVersion = "m124-08a5439a6b"
)

$ErrorActionPreference = 'Stop'

# Path configuration
$UserDeps = Join-Path $env:USERPROFILE ".deps"
$AsepriteInstallPath = "C:\ProgramData\Aseprite"
$StartMenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Aseprite.lnk"

# Validate PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This script requires PowerShell 7 or newer"
}

# Check existing installation
if (Test-Path $AsepriteInstallPath) {
    $confirmation = Read-Host "Aseprite installation exists at $AsepriteInstallPath. Delete? (y/n)"
    if ($confirmation -eq 'y') {
        Remove-Item $AsepriteInstallPath -Recurse -Force
    }
    else {
        exit
    }
}

# Create dependency directories
$null = New-Item -ItemType Directory -Path $UserDeps -Force
$null = New-Item -ItemType Directory -Path $AsepriteInstallPath -Force

# Install build tools
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')
}

choco install -y cmake --installargs 'ADD_CMAKE_TO_PATH=System'
choco install -y ninja git

# Download Skia
$SkiaUrl = "https://github.com/aseprite/skia/releases/download/$SkiaVersion/Skia-Windows-Release-x64.zip"
$SkiaZip = Join-Path $env:TEMP "Skia-$SkiaVersion.zip"

Invoke-WebRequest -Uri $SkiaUrl -OutFile $SkiaZip -UseBasicParsing
Expand-Archive -Path $SkiaZip -DestinationPath (Join-Path $UserDeps "skia") -Force
Remove-Item $SkiaZip

# Clone Aseprite
$AsepriteRepo = Join-Path $UserDeps "aseprite"
git clone --recursive --depth 1 https://github.com/aseprite/aseprite.git $AsepriteRepo

# Configure build environment
$VCVarsPath = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $VCVarsPath)) {
    throw "Visual Studio 2022 with C++ tools required"
}

# Build process
Push-Location $AsepriteRepo
try {
    # Create build directory
    $BuildDir = Join-Path $AsepriteRepo "build"
    $null = New-Item -ItemType Directory -Path $BuildDir -Force

    # Configure CMake
    & $VCVarsPath
    cmake -B $BuildDir `
        -DCMAKE_BUILD_TYPE=RelWithDebInfo `
        -DLAF_BACKEND=skia `
        -DSKIA_DIR="$UserDeps\skia" `
        -DSKIA_LIBRARY_DIR="$UserDeps\skia\out\Release-x64" `
        -DSKIA_LIBRARY="$UserDeps\skia\out\Release-x64\skia.lib" `
        -G Ninja

    # Compile
    ninja -C $BuildDir aseprite

    # Install
    Copy-Item -Path "$BuildDir\bin\aseprite.exe" -Destination $AsepriteInstallPath
    Copy-Item -Path "$BuildDir\bin\data" -Destination $AsepriteInstallPath -Recurse
}
finally {
    Pop-Location
}

# Create Start Menu shortcut
$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($StartMenuPath)
$Shortcut.TargetPath = Join-Path $AsepriteInstallPath "aseprite.exe"
$Shortcut.WorkingDirectory = $AsepriteInstallPath
$Shortcut.IconLocation = Join-Path $AsepriteInstallPath "data\icons\ase256.ico"
$Shortcut.Save()

# Set permissions
icacls $AsepriteInstallPath /grant "Users:(OI)(CI)RX"

Write-Host "Installation complete! Aseprite is available in Start Menu" -ForegroundColor Green
