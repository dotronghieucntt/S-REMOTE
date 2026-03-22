# Install RDP Wrapper on Windows 10 Home
# Enables RDP server functionality

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$tmpDir = "$env:TEMP\RDPWrapInstall"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

Write-Host "=== RDP Wrapper Installer ===" -ForegroundColor Cyan

# Step 1: Download
Write-Host "[1/4] Downloading RDP Wrapper..." -ForegroundColor Yellow
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")

$urls = @(
    "https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip",
    "https://github.com/sebaxakerhtc/rdpwrap/releases/latest/download/RDPWrap.zip"
)

$zipPath = "$tmpDir\RDPWrap.zip"
$downloaded = $false

foreach ($url in $urls) {
    try {
        Write-Host "  Trying: $url" -ForegroundColor Gray
        $wc.DownloadFile($url, $zipPath)
        if ((Test-Path $zipPath) -and (Get-Item $zipPath).Length -gt 100KB) {
            Write-Host "  [OK] Downloaded $([math]::Round((Get-Item $zipPath).Length/1KB))KB" -ForegroundColor Green
            $downloaded = $true
            break
        }
    } catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $downloaded) {
    Write-Host "[ERROR] Download failed. Tao se open browser de ban tu tai ve." -ForegroundColor Red
    Start-Process "https://github.com/stascorp/rdpwrap/releases/latest"
    Write-Host "Sau khi tai ve, giai nen va chay install.bat voi quyen Administrator." -ForegroundColor Yellow
    pause
    exit 1
}

# Step 2: Extract
Write-Host "[2/4] Extracting..." -ForegroundColor Yellow
$extractDir = "$tmpDir\RDPWrap"
if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)
Write-Host "  [OK] Extracted" -ForegroundColor Green

# Find install.bat
$installBat = Get-ChildItem -Path $extractDir -Recurse -Filter "install.bat" | Select-Object -First 1
if (-not $installBat) {
    Write-Host "[ERROR] install.bat not found in zip!" -ForegroundColor Red
    Write-Host "Contents:" -ForegroundColor Yellow
    Get-ChildItem -Path $extractDir -Recurse | ForEach-Object { Write-Host "  $($_.FullName)" }
    pause
    exit 1
}

Write-Host "  Found: $($installBat.FullName)" -ForegroundColor Cyan

# Step 3: Run installer
Write-Host "[3/4] Running install.bat..." -ForegroundColor Yellow
$proc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$($installBat.FullName)`"" -WorkingDirectory $installBat.DirectoryName -Wait -PassThru -Verb RunAs
Write-Host "  Exit code: $($proc.ExitCode)" -ForegroundColor Cyan

# Step 4: Update ini config (needed for newer Windows builds)
Write-Host "[4/4] Updating rdpwrap.ini for current Windows build..." -ForegroundColor Yellow
$iniPath = "C:\Program Files\RDP Wrapper\rdpwrap.ini"
$iniUrl = "https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap/master/res/rdpwrap.ini"
if (Test-Path $iniPath) {
    try {
        $wc2 = New-Object System.Net.WebClient
        $wc2.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc2.DownloadFile($iniUrl, $iniPath)
        Write-Host "  [OK] rdpwrap.ini updated" -ForegroundColor Green
    } catch {
        Write-Host "  [WARN] Could not update ini: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Restart TermService
Write-Host "Restarting TermService..." -ForegroundColor Yellow
Stop-Service -Name TermService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-Service -Name TermService -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Verify
Write-Host ""
$listen = netstat -an | Select-String ":3389"
if ($listen) {
    Write-Host "=== THANH CONG! ===" -ForegroundColor Green
    Write-Host "Port 3389 dang LISTEN - RDP hoat dong!" -ForegroundColor Green
    $listen | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
} else {
    Write-Host "Port 3389 chua thay listen. Thu chay RDPConf.exe de kiem tra trang thai." -ForegroundColor Yellow
}

# Show verification tool
$rdpConf = "C:\Program Files\RDP Wrapper\RDPConf.exe"
if (Test-Path $rdpConf) {
    Write-Host ""
    Write-Host "Mo RDPConf.exe de kiem tra trang thai..." -ForegroundColor Cyan
    Start-Process $rdpConf
}

Write-Host ""
Write-Host "IP de ket noi:" -ForegroundColor Cyan
Get-NetIPAddress | Where-Object { $_.AddressFamily -eq "IPv4" -and $_.PrefixOrigin -ne "WellKnown" } | Select-Object InterfaceAlias, IPAddress | Format-Table -AutoSize

pause
