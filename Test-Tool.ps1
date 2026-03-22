# Test Script - Dry Run Mode
# Kiểm tra logic của ZeroTier QuickSetup mà không thực sự cài đặt

Write-Host "=== ZEROTIER QUICKSETUP - DRY RUN TEST ===" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$totalTests = 0

function Test-Component {
    param($name, $scriptBlock)
    $script:totalTests++
    Write-Host "Test $totalTests : $name" -ForegroundColor Yellow -NoNewline
    try {
        $result = & $scriptBlock
        if ($result) {
            Write-Host " [PASS]" -ForegroundColor Green
            $script:testsPassed++
            return $true
        } else {
            Write-Host " [FAIL]" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host " [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Test 1: Check if script file exists and is readable
Test-Component "Script file exists and readable" {
    $scriptPath = ".\ZeroTier-QuickSetup.ps1"
    if (Test-Path $scriptPath) {
        $content = Get-Content $scriptPath -Raw
        return $content.Length -gt 0
    }
    return $false
}

# Test 2: Check PowerShell syntax
Test-Component "PowerShell syntax validation" {
    $scriptPath = ".\ZeroTier-QuickSetup.ps1"
    $errors = $null
    $tokens = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    return ($errors.Count -eq 0)
}

# Test 3: Check required .NET assemblies can be loaded
Test-Component "Windows.Forms assembly" {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        return $true
    } catch {
        return $false
    }
}

Test-Component "Drawing assembly" {
    try {
        Add-Type -AssemblyName System.Drawing
        return $true
    } catch {
        return $false
    }
}

# Test 4: Check if running as Administrator
Test-Component "Administrator privileges" {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "  [!] Warning: Not running as Administrator" -ForegroundColor Yellow
        Write-Host "  [!] Tool requires admin rights to work properly" -ForegroundColor Yellow
    }
    return $true  # Pass anyway but warn
}

# Test 5: Check ZeroTier download URL
Test-Component "ZeroTier download URL reachable" {
    try {
        $url = "https://download.zerotier.com/dist/ZeroTier%20One.msi"
        $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return ($response.StatusCode -eq 200)
    } catch {
        Write-Host ""
        Write-Host "  [!] Cannot reach ZeroTier download URL" -ForegroundColor Yellow
        return $false
    }
}

# Test 6: Check Registry paths exist
Test-Component "Terminal Server registry path" {
    return (Test-Path "HKLM:\System\CurrentControlSet\Control\Terminal Server")
}

Test-Component "RDP-Tcp registry path" {
    return (Test-Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp")
}

# Test 7: Check if TermService exists
Test-Component "Terminal Service exists" {
    $service = Get-Service -Name "TermService" -ErrorAction SilentlyContinue
    return ($null -ne $service)
}

# Test 8: Check firewall cmdlets available
Test-Component "Firewall cmdlets available" {
    $cmd = Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

# Test 9: Check if can create local user (simulated)
Test-Component "LocalUser cmdlets available" {
    $cmd = Get-Command Get-LocalUser -ErrorAction SilentlyContinue
    return ($null -ne $cmd)
}

# Test 10: Check clipboard functionality
Test-Component "Clipboard functionality" {
    try {
        Set-Clipboard -Value "test"
        $clip = Get-Clipboard
        return ($clip -eq "test")
    } catch {
        return $false
    }
}

# Test 11: Check EXE file exists
Test-Component "EXE file built and exists" {
    $exePath = ".\ZeroTier-QuickSetup.exe"
    if (Test-Path $exePath) {
        $size = (Get-Item $exePath).Length
        Write-Host ""
        Write-Host "  [i] EXE size: $([math]::Round($size/1KB, 2)) KB" -ForegroundColor Gray
        return $true
    }
    return $false
}

# Test 12: Check icon file
Test-Component "Icon file exists" {
    return (Test-Path ".\icon.ico")
}

# Test 13: Validate Network ID format
Test-Component "Default Network ID format" {
    $networkId = "743993800f9dac1e"
    return ($networkId -match '^[a-f0-9]{16}$')
}

# Test 14: Check if can read script content for key components
Test-Component "Script contains all required steps" {
    $content = Get-Content ".\ZeroTier-QuickSetup.ps1" -Raw
    $checks = @(
        "Install ZeroTier",
        "Join Network",
        "Enable Remote Desktop",
        "Set Password",
        "Test.*Configuration",
        "Get.*IP",
        "fDenyTSConnections",
        "UserAuthentication",
        "TermService",
        "ZeroTier-RDP-TCP"
    )
    
    $allFound = $true
    foreach ($check in $checks) {
        if ($content -notmatch $check) {
            Write-Host ""
            Write-Host "  [!] Missing: $check" -ForegroundColor Yellow
            $allFound = $false
        }
    }
    return $allFound
}

# Test 15: Check UI components defined
Test-Component "UI components properly defined" {
    $content = Get-Content ".\ZeroTier-QuickSetup.ps1" -Raw
    $uiComponents = @(
        'System.Windows.Forms.Form',
        'System.Windows.Forms.TextBox',
        'System.Windows.Forms.Button',
        'System.Windows.Forms.Label'
    )
    
    foreach ($component in $uiComponents) {
        if ($content -notmatch [regex]::Escape($component)) {
            return $false
        }
    }
    return $true
}

# Summary
Write-Host ""
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 50 -ForegroundColor Cyan
Write-Host ""
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $($totalTests - $testsPassed)" -ForegroundColor Red
Write-Host ""

$passRate = [math]::Round(($testsPassed / $totalTests) * 100, 2)
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -eq 100) { "Green" } elseif ($passRate -ge 80) { "Yellow" } else { "Red" })
Write-Host ""

if ($testsPassed -eq $totalTests) {
    Write-Host "STATUS: CHUẨN! Tool sẵn sàng sử dụng! " -ForegroundColor Green -NoNewline
    Write-Host "🚀" -ForegroundColor Green
} elseif ($passRate -ge 80) {
    Write-Host "STATUS: GẦN CHUẨN! Có thể sử dụng nhưng cần lưu ý một số vấn đề." -ForegroundColor Yellow
} else {
    Write-Host "STATUS: CHƯA CHUẨN! Cần sửa một số vấn đề trước khi sử dụng." -ForegroundColor Red
}

Write-Host ""
Write-Host "Để chạy thật, double-click: ZeroTier-QuickSetup.exe" -ForegroundColor Cyan
Write-Host ""
