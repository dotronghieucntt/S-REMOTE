# Build NOVIVO Remote Desktop to EXE
Write-Host "=== NOVIVO Remote Desktop - Build to EXE ===" -ForegroundColor Cyan
Write-Host ""

# Check if PS2EXE is installed
Write-Host "[1/3] Checking PS2EXE module..." -ForegroundColor Yellow
$ps2exe = Get-Module -ListAvailable -Name ps2exe

if (-not $ps2exe) {
    Write-Host "[!] PS2EXE not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
    Write-Host "[OK] PS2EXE installed successfully!" -ForegroundColor Green
} else {
    Write-Host "[OK] PS2EXE already installed!" -ForegroundColor Green
}

Import-Module ps2exe

# Build EXE
Write-Host ""
Write-Host "[2/3] Building EXE file..." -ForegroundColor Yellow

$scriptPath = Join-Path $PSScriptRoot "NOVIVO-Remote-Desktop.ps1"
$exePath    = Join-Path $PSScriptRoot "NOVIVO-Remote-Desktop.exe"
$iconPath   = Join-Path $PSScriptRoot "icon.ico"

if (-not (Test-Path $scriptPath)) {
    Write-Host "[ERROR] Script file not found: $scriptPath" -ForegroundColor Red
    pause
    exit 1
}

# Check if icon exists
$iconParam = @{}
if (Test-Path $iconPath) {
    $iconParam = @{iconFile = $iconPath}
    Write-Host "[OK] Using custom icon: $iconPath" -ForegroundColor Green
}

Invoke-ps2exe -inputFile $scriptPath -outputFile $exePath -title "NOVIVO Remote Desktop" -description "NOVIVO Remote Desktop Setup Tool" -company "NOVIVO" -product "NOVIVO Remote Desktop" -copyright "2026" -version "2.0.0.0" -requireAdmin -noConsole -noError -noOutput @iconParam

Write-Host "[OK] Build completed!" -ForegroundColor Green

# Verify EXE created
Write-Host ""
Write-Host "[3/3] Verifying output..." -ForegroundColor Yellow

if (Test-Path $exePath) {
    $fileInfo = Get-Item $exePath
    Write-Host "[OK] EXE file created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host "        NOVIVO Remote Desktop v2.0" -ForegroundColor Cyan
    Write-Host "           BUILD SUCCESSFUL!" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "File: $exePath" -ForegroundColor White
    Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB" -ForegroundColor White
    Write-Host ""
    Write-Host "You can now run: NOVIVO-Remote-Desktop.exe" -ForegroundColor Green
} else {
    Write-Host "[ERROR] EXE file not found after build!" -ForegroundColor Red
}

Write-Host ""
pause
