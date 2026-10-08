<#
.SYNOPSIS
    NOVIVO Remote Desktop - Official Release Build Script
    Builds onefile EXE + onedir Full, bumps version, uploads to GitHub.

.USAGE
    .\Build-Release.ps1               # normal build
    .\Build-Release.ps1 -SkipGitHub  # build only, skip git push
    .\Build-Release.ps1 -BumpType minor   # bump minor version (default: patch)

    Doc truoc: BUILD.md. Moi thu ve dong goi (import, thu vien, file di kem, icon,
    version resource) nam trong NOVIVO-RemoteDesktop.spec - script nay chi dieu phoi.
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

# icon.ico (du co 16-256) va version resource gio do spec tu tao trong build_tmp/.
# Truoc day 2 buoc nay chay O DAY, roi buoc don dep xoa mat build_tmp/version_info.txt
# -> exe v1.0.0-v1.0.18 khong co version resource, icon chi co co 16px.

# --- 2. Clean previous build artifacts ---------------------------------------
Write-Step "2/7  Cleaning previous build artifacts"
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

# --- 3. Run PyInstaller with spec --------------------------------------------
Write-Step "3/7  Building with PyInstaller (onefile + onedir)"
$spec       = Join-Path $ROOT "NOVIVO-RemoteDesktop.spec"
$distPath   = Join-Path $ROOT "dist"
$buildPath  = Join-Path $ROOT "build_tmp"

& $PYI `
    --distpath $distPath `
    --workpath $buildPath `
    --noconfirm `
    --clean `
    $spec

if ($LASTEXITCODE -ne 0) { throw "PyInstaller build failed (exit $LASTEXITCODE) - xem dong [spec] DUNG BUILD o tren" }

# --- 4. Self-test: chay chinh exe vua build -----------------------------------
# Runtime hook pyi_hooks/pyi_rth_selftest.py: exe goi kem --selftest thi import du
# module app dung, kiem file di kem, Tcl/Tk, SSL roi THOAT (app khong chay).
# __COMPAT_LAYER=RunAsInvoker de khong hien hop UAC (manifest doi admin).
# Hong thi xoa dist/: landing server remote.novivo.net doc ca dist/, khong duoc de
# ban hong nam do. (v1.0.18 tung len trang voi loi "No module named 'email'".)
Write-Step "4/7  Self-testing the built EXEs"

function Invoke-SelfTest([string]$exePath) {
    $out  = Join-Path $buildPath ("selftest-" + [guid]::NewGuid().ToString("N") + ".json")
    $prev = $env:__COMPAT_LAYER
    $env:__COMPAT_LAYER = "RunAsInvoker"
    try {
        $p = Start-Process -FilePath $exePath -ArgumentList @("--selftest", "`"$out`"") -PassThru
    } finally {
        $env:__COMPAT_LAYER = $prev
    }
    if (-not $p.WaitForExit(120000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        return @{ ok = $false; errors = @("treo qua 120 giay (co the dang hien hop traceback)") }
    }
    if (-not (Test-Path $out)) {
        return @{ ok = $false; errors = @("khong co ket qua (exit $($p.ExitCode)) - exe chet truoc khi runtime hook chay") }
    }
    return (Get-Content $out -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$appName  = "NOVIVO Remote Desktop v$verCurrent"
$stFailed = @()
foreach ($t in @(
    @{ Label = "EXE";  Path = (Join-Path $distPath "$appName.exe") },
    @{ Label = "Full"; Path = (Join-Path (Join-Path $distPath "$appName (Full)") "$appName.exe") }
)) {
    if (-not (Test-Path $t.Path)) { $stFailed += "$($t.Label): khong thay $($t.Path)"; continue }
    $r = Invoke-SelfTest $t.Path
    if ($r.ok) {
        Write-Host "[OK] $($t.Label) self-test: $($r.checked.imports) module, $($r.checked.files) file, Tk $($r.checked.tk)"
        $net = $r.checked.PSObject.Properties["net"]
        if ($net) { Write-Host "     mang: $($net.Value)" }
    } else {
        foreach ($e in $r.errors) { $stFailed += "$($t.Label): $e" }
    }
}
if ($stFailed.Count -gt 0) {
    Write-Host ""
    Write-Host "  ================= SELF-TEST HONG =================" -ForegroundColor Red
    $stFailed | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host "  Da xoa dist/ de ban hong khong len trang tai ve." -ForegroundColor Yellow
    Write-Host "  ==================================================" -ForegroundColor Red
    Remove-Item $distPath -Recurse -Force -ErrorAction SilentlyContinue
    throw "Self-test failed - build khong duoc phat hanh."
}

# --- 5. Stage release outputs ------------------------------------------------
Write-Step "5/7  Staging release outputs"
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

# --- 6.5 Secret scan (BAT BUOC truoc khi phat hanh) --------------------------
# Cac ban v1.0.0 - v1.0.15 tung nhung thang mot Tailscale auth key vao EXE, tuc la
# ai tai cung co chia khoa vao mang rieng. Quet truoc khi phat hanh, khong tin tri nho.
Write-Step "6/7  Scanning artifacts for embedded secrets"

$secretPatterns = @(
    @{ Name = "Tailscale auth key";  Pattern = "tskey-[a-zA-Z]+-[A-Za-z0-9\-]{10,}" },
    @{ Name = "GitHub token";        Pattern = "gh[pousr]_[A-Za-z0-9]{20,}" },
    @{ Name = "GitHub fine-grained"; Pattern = "github_pat_[A-Za-z0-9_]{20,}" }
)

function Test-FileForSecrets {
    param([string]$Path)
    $found = @()
    if (-not (Test-Path $Path)) { return $found }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text  = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)   # latin1: giu nguyen byte
    foreach ($p in $secretPatterns) {
        if ([regex]::IsMatch($text, $p.Pattern)) { $found += $p.Name }
    }
    return ,$found
}

$dirty = @()
foreach ($f in @(
    (Join-Path $relDir "$appName.exe"),
    (Join-Path $relDir "$appName (Full).zip")
)) {
    $hits = Test-FileForSecrets -Path $f
    if ($hits.Count -gt 0) {
        $dirty += "$([System.IO.Path]::GetFileName($f)) -> $($hits -join ', ')"
    }
}
# ZIP nen nen chuoi khong lo ra khi quet tho: quet luon thu muc onedir goc
if (Test-Path $dst) {
    foreach ($f in (Get-ChildItem $dst -Recurse -File -Include *.exe,*.json,*.ps1,*.txt -EA SilentlyContinue)) {
        $hits = Test-FileForSecrets -Path $f.FullName
        if ($hits.Count -gt 0) { $dirty += "$($f.Name) (trong Full) -> $($hits -join ', ')" }
    }
}

if ($dirty.Count -gt 0) {
    Write-Host ""
    Write-Host "  ================= DUNG PHAT HANH =================" -ForegroundColor Red
    Write-Host "  Goi cai dat co nhung bi mat, KHONG duoc phat hanh:" -ForegroundColor Red
    $dirty | Sort-Object -Unique | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Xu ly: thu hoi key da lo, xoa gia tri hardcode trong source," -ForegroundColor Yellow
    Write-Host "  build lai, roi chay lai script nay." -ForegroundColor Yellow
    Write-Host "  ==================================================" -ForegroundColor Red
    throw "Secret scan failed - build khong duoc phat hanh."
}
Write-Host "[OK] Khong tim thay bi mat nao trong goi phat hanh"

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
        git add NOVIVO-AlwaysAdmin.ps1
        git add pyi_hooks/
        git add BUILD.md
        git add CLAUDE.md
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
