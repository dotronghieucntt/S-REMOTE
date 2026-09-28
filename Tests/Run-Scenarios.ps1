# Runs the NOVIVO install scenario matrix. No dependencies, no admin, no network.
#   powershell -ExecutionPolicy Bypass -File Tests\Run-Scenarios.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host ""
Write-Host "  NOVIVO install scenario matrix" -ForegroundColor Cyan
Write-Host "  (simulated machines - runs the real backend functions)" -ForegroundColor DarkGray
Write-Host ""
& (Join-Path $here 'Install-Scenarios.Tests.ps1')
exit $LASTEXITCODE
