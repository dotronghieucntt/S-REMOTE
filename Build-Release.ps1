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

$ROOT = $PSScriptRoot

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host ">> $msg" -ForegroundColor Cyan
}

# --- 0. Auto-detect Python + PyInstaller ------------------------------------
Write-Step "0/7  Verifying build tools"

# Build candidate list of python.exe paths to check
$pyCandidates = [System.Collections.Generic.List[string]]::new()

# 1. uv-managed installs (current user) — preferred, usually have all packages
$uvBase = Join-Path $env:APPDATA "uv\python"
if (Test-Path $uvBase) {
    Get-ChildItem $uvBase -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | ForEach-Object { $pyCandidates.Add($_.FullName) }
}

# 2. python / python3 / py on PATH
foreach ($cmd in @("python","python3","py")) {
    $p = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($p -and ($p.Source -match "Python 3|python3" -or (& $p.Source --version 2>&1) -match "Python 3")) {
        if (-not $pyCandidates.Contains($p.Source)) { $pyCandidates.Add($p.Source) }
    }
}

# Pick the first candidate that has pyinstaller.exe in its Scripts/ or AppData Scripts/
$PYTHON = $null ; $PYI = $null
foreach ($py in $pyCandidates) {
    $pyDir2   = Split-Path $py
    $pyi_sys  = Join-Path $pyDir2 "Scripts\pyinstaller.exe"
    # Also check per-user Scripts folder that pip --user installs to
    $ver3     = & $py --version 2>&1
    $pyVer    = if ($ver3 -match "Python (\d+\.\d+)") { $Matches[1] } else { "" }
    $pyi_user = "$env:APPDATA\Python\Python$($pyVer -replace '\.','')\Scripts\pyinstaller.exe"
    if (Test-Path $pyi_sys)  { $PYTHON = $py ; $PYI = $pyi_sys  ; break }
    if (Test-Path $pyi_user) { $PYTHON = $py ; $PYI = $pyi_user ; break }
}

# Fallback: pick any Python 3, install PyInstaller into it
if (-not $PYTHON) {
    if ($pyCandidates.Count -gt 0) {
        $PYTHON = $pyCandidates[0]
        $pyDir2 = Split-Path $PYTHON
        Write-Host "PyInstaller not found, installing into $PYTHON ..." -ForegroundColor Yellow
        & $PYTHON -m pip install pyinstaller --quiet
        $PYI = Join-Path $pyDir2 "Scripts\pyinstaller.exe"
        if (-not (Test-Path $PYI)) { throw "PyInstaller install failed. Run: pip install pyinstaller" }
    } else {
        throw "Python 3 not found. Install Python or uv, then: pip install pyinstaller"
    }
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
# Kill any running NOVIVO EXE that may be locking dist/ files
Get-Process | Where-Object { $_.Name -like "*NOVIVO*" } |
    ForEach-Object { Write-Host "  Stopping: $($_.Name)"; Stop-Process $_ -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 1

foreach ($d in @("build_tmp", "dist")) {
    $p = Join-Path $ROOT $d
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $p) { Write-Host "  [WARN] Could not fully clean: $d (file may be locked)" }
        else              { Write-Host "  Cleaned: $d" }
    }
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

# Copy onedir folder + zip it
if (Test-Path $onedirBase) {
    $dst = Join-Path $relDir "$appName (Full)"
    if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
    Copy-Item $onedirBase $dst -Recurse -Force
    Write-Host "[OK] Full → releases\v$verCurrent\$appName (Full)\"

    # Zip the Full folder
    $zipPath = Join-Path $relDir "$appName (Full).zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($dst, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $zipMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "[OK] ZIP  → releases\v$verCurrent\$appName (Full).zip ($zipMB MB)"
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
Write-Host ""
Write-Host "Output files:" -ForegroundColor Cyan
$relDirFinal = Join-Path (Join-Path $ROOT "releases") "v$verCurrent"
Get-ChildItem $relDirFinal -File | ForEach-Object {
    Write-Host "  $($_.Name)  ($([math]::Round($_.Length/1MB,1)) MB)" -ForegroundColor White
}
Write-Host "  Folder: $relDirFinal" -ForegroundColor DarkGray
