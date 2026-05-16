<#
.SYNOPSIS
    NOVIVO Remote Desktop - Official Release Build Script
    Builds onefile EXE + onedir Full, bumps version, uploads to GitHub.

.USAGE
    .\Build-Release.ps1               # normal build
    .\Build-Release.ps1 -SkipGitHub  # build only, skip git push
    .\Build-Release.ps1 -BumpType minor   # bump minor version (default: patch)
#>
param(
    [switch]$SkipGitHub,
    [ValidateSet("patch","minor","major")]
    [string]$BumpType = "patch"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PYTHON = "C:/Users/HIEU/AppData/Roaming/uv/python/cpython-3.13.12-windows-x86_64-none/python.exe"
$PYI    = "C:/Users/HIEU/AppData/Roaming/uv/python/cpython-3.13.12-windows-x86_64-none/Scripts/pyinstaller.exe"
$ROOT   = $PSScriptRoot

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host ">> $msg" -ForegroundColor Cyan
}

# --- 0. Verify tools ---------------------------------------------------------
Write-Step "0/7  Verifying build tools"
foreach ($t in @($PYTHON, $PYI)) {
    if (-not (Test-Path $t)) { throw "Not found: $t" }
}
Write-Host "[OK] Python: $PYTHON"
Write-Host "[OK] PyInstaller: $PYI"

# --- 1. Read current version -------------------------------------------------
Write-Step "1/7  Reading version"
$verFile    = Join-Path $ROOT "version.txt"
$verCurrent = (Get-Content $verFile -Raw).Trim()
$parts      = $verCurrent.Split(".")
$major      = [int]$parts[0]
$minor      = [int]$parts[1]
$patch      = [int]$parts[2]
Write-Host "[OK] Current version: $verCurrent"

# --- 2. Convert logo PNG → icon.ico ------------------------------------------
Write-Step "2/7  Generating icon.ico from LOGO KO CHU.png"
$iconScript = @"
from PIL import Image
import os
src = os.path.join(r'$ROOT', 'LOGO KO CHU.png')
dst = os.path.join(r'$ROOT', 'icon.ico')
img = Image.open(src).convert('RGBA')
# Generate standard Windows icon sizes
sizes = [(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)]
imgs = [img.resize(s, Image.LANCZOS) for s in sizes]
imgs[0].save(dst, format='ICO', sizes=sizes, append_images=imgs[1:])
print(f'[OK] icon.ico written ({os.path.getsize(dst)//1024} KB)')
"@
& $PYTHON -c $iconScript
if ($LASTEXITCODE -ne 0) { throw "Icon conversion failed" }

# --- 3. Generate Windows version resource ------------------------------------
Write-Step "3/7  Generating Windows version resource"
& $PYTHON (Join-Path $ROOT "version_info.py")
if ($LASTEXITCODE -ne 0) { throw "version_info.py failed" }

# --- 4. Clean previous build artifacts ---------------------------------------
Write-Step "4/7  Cleaning previous build artifacts"
foreach ($d in @("build_tmp", "dist")) {
    $p = Join-Path $ROOT $d
    if (Test-Path $p) { Remove-Item $p -Recurse -Force; Write-Host "  Cleaned: $d" }
}

# --- 5. Run PyInstaller with spec --------------------------------------------
Write-Step "5/7  Building with PyInstaller (onefile + onedir)"
$spec       = Join-Path $ROOT "NOVIVO-RemoteDesktop.spec"
$distPath   = Join-Path $ROOT "dist"
$buildPath  = Join-Path $ROOT "build_tmp"

& $PYI `
    --distpath $distPath `
    --workpath $buildPath `
    --noconfirm `
    --clean `
    $spec

if ($LASTEXITCODE -ne 0) { throw "PyInstaller build failed (exit $LASTEXITCODE)" }

# --- 6. Stage release outputs ------------------------------------------------
Write-Step "6/7  Staging release outputs"
$relDir = Join-Path (Join-Path $ROOT "releases") "v$verCurrent"
New-Item -ItemType Directory -Path $relDir -Force | Out-Null

$appName    = "NOVIVO Remote Desktop v$verCurrent"
$onefile    = Join-Path $distPath "$appName.exe"
$onedirBase = Join-Path $distPath "$appName (Full)"

# Copy onefile EXE
if (Test-Path $onefile) {
    $dst = Join-Path $relDir "$appName.exe"
    Copy-Item $onefile $dst -Force
    Write-Host "[OK] EXE  → releases\v$verCurrent\$appName.exe"
} else {
    Write-Warning "Onefile EXE not found at: $onefile"
}

# Copy onedir folder
if (Test-Path $onedirBase) {
    $dst = Join-Path $relDir "$appName (Full)"
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $onedirBase $dst -Recurse -Force
    Write-Host "[OK] Full → releases\v$verCurrent\$appName (Full)\"
} else {
    Write-Warning "Onedir folder not found at: $onedirBase"
}

# Also place onefile EXE in workspace root for quick access
if (Test-Path $onefile) {
    Copy-Item $onefile (Join-Path $ROOT "$appName.exe") -Force
    Write-Host "[OK] Quick-access EXE placed in workspace root"
}

# --- 7. Bump version ---------------------------------------------------------
Write-Step "7/7  Bumping version ($BumpType)"
switch ($BumpType) {
    "major" { $major++; $minor = 0; $patch = 0 }
    "minor" { $minor++;             $patch = 0 }
    "patch" {                       $patch++   }
}
$verNext = "$major.$minor.$patch"
Set-Content -Path $verFile -Value $verNext -NoNewline
Write-Host "[OK] Version bumped: $verCurrent → $verNext"

# --- GitHub upload ---------------------------------------------------------
if (-not $SkipGitHub) {
    Write-Step "** Uploading to GitHub"
    Push-Location $ROOT
    try {
        # Stage all changed/new build artefacts and source
        git add version.txt
        git add icon.ico
        git add version_info.py
        git add NOVIVO-RemoteDesktop.spec
        git add Build-Release.ps1
        git add NOVIVO-App.py
        git add NOVIVO-Backend.ps1
        git add "LOGO KO CHU.png"
        git add "NEN DEN.png"
        git add releases/

        # Check if there is anything to commit
        $status = git status --porcelain
        if ($status) {
            git commit -m "Release v$verCurrent"
            Write-Host "[OK] Committed: Release v$verCurrent"
        } else {
            Write-Host "[INFO] Nothing changed - skipping commit"
        }

        # Tag this version
        $tagExists = git tag -l "v$verCurrent"
        if (-not $tagExists) {
            git tag -a "v$verCurrent" -m "NOVIVO Remote Desktop v$verCurrent"
            Write-Host "[OK] Tagged: v$verCurrent"
        }

        # Push commits and tags
        git push origin master
        git push origin "v$verCurrent"
        Write-Host "[OK] Pushed to GitHub"
    }
    finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "=================================================" -ForegroundColor Green
Write-Host "  BUILD COMPLETE -- NOVIVO Remote Desktop v$verCurrent" -ForegroundColor Green
Write-Host "  Next version will be: v$verNext" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
