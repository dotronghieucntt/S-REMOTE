# Fix Script - Repair ZeroTier-QuickSetup.ps1
Write-Host "=== FIXING ZEROTIER QUICKSETUP SCRIPT ===" -ForegroundColor Cyan
Write-Host ""

# Read as UTF8 with BOM
$content = [System.IO.File]::ReadAllText(".\ZeroTier-QuickSetup.ps1.backup", [System.Text.Encoding]::UTF8)

Write-Host "[1] Checking for common issues..." -ForegroundColor Yellow

# Fix 1: Replace corrupted emoji/unicode
$fixes = 0

if ($content -match "ðŸš€|🚀") {
    $content = $content -replace "ðŸš€|🚀", ">>>"
    $fixes++
    Write-Host "  [FIX] Replaced rocket emoji" -ForegroundColor Green
}

if ($content -match "ðŸ""'|🔑") {
    $content = $content -replace "ðŸ""'|🔑", "[KEY]"
    $fixes++
    Write-Host "  [FIX] Replaced key emoji" -ForegroundColor Green
}

if ($content -match "âœ"|✓") {
    $content = $content -replace "âœ"|✓", "[OK]"
    $fixes++
    Write-Host "  [FIX] Replaced checkmark" -ForegroundColor Green
}

if ($content -match "âœ—|✗") {
    $content = $content -replace "âœ—|✗", "[X]"
    $fixes++
    Write-Host "  [FIX] Replaced X mark" -ForegroundColor Green
}

# Fix 2: Check for unclosed blocks
$openBraces = ($content.ToCharArray() | Where-Object {$_ -eq '{'}).Count
$closeBraces = ($content.ToCharArray() | Where-Object {$_ -eq '}'}).Count
$openParens = ($content.ToCharArray() | Where-Object {$_ -eq '('}).Count
$closeParens = ($content.ToCharArray() | Where-Object {$_ -eq ')'}).Count

Write-Host ""
Write-Host "[2] Structure check:" -ForegroundColor Yellow
Write-Host "  { : $openBraces, } : $closeBraces" -ForegroundColor $(if ($openBraces -eq $closeBraces) {"Green"} else {"Red"})
Write-Host "  ( : $openParens, ) : $closeParens" -ForegroundColor $(if ($openParens -eq $closeParens) {"Green"} else {"Red"})

# Save fixed version
Write-Host ""
Write-Host "[3] Saving fixed version..." -ForegroundColor Yellow

# Save with UTF8 NO BOM
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText(".\ZeroTier-QuickSetup-FIXED.ps1", $content, $utf8NoBom)

Write-Host "  [OK] Saved to: ZeroTier-QuickSetup-FIXED.ps1" -ForegroundColor Green

# Test syntax
Write-Host ""
Write-Host "[4] Testing syntax..." -ForegroundColor Yellow
$errors = $null
$tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile(".\ZeroTier-QuickSetup-FIXED.ps1", [ref]$tokens, [ref]$errors) | Out-Null

if ($errors.Count -eq 0) {
    Write-Host "  [OK] No syntax errors!" -ForegroundColor Green
    Write-Host ""
    Write-Host "=== SUCCESS ===" -ForegroundColor Green
    Write-Host "Fixed file ready: ZeroTier-QuickSetup-FIXED.ps1" -ForegroundColor Green
    Write-Host ""
    Write-Host "To use: Copy-Item '.\ZeroTier-QuickSetup-FIXED.ps1' '.\ZeroTier-QuickSetup.ps1' -Force" -ForegroundColor Yellow
} else {
    Write-Host "  [!] Still has $($errors.Count) errors" -ForegroundColor Red
    Write-Host ""
    Write-Host "Top errors:" -ForegroundColor Yellow
    $errors | Select-Object -First 5 | ForEach-Object {
        Write-Host "  Line $($_.Extent.StartLineNumber): $($_.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Applied $fixes automatic fixes" -ForegroundColor Cyan
