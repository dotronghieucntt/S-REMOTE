# Convert PNG to ICO
Add-Type -AssemblyName System.Drawing

$pngPath = "$PSScriptRoot\icon.png"
$icoPath = "$PSScriptRoot\icon.ico"

if (Test-Path $pngPath) {
    $img = [System.Drawing.Image]::FromFile($pngPath)
    $bitmap = New-Object System.Drawing.Bitmap($img)
    $icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
    $stream = [System.IO.File]::Create($icoPath)
    $icon.Save($stream)
    $stream.Close()
    $icon.Dispose()
    $bitmap.Dispose()
    $img.Dispose()
    
    Write-Host "[OK] Icon file created: $icoPath" -ForegroundColor Green
} else {
    Write-Host "[ERROR] PNG file not found!" -ForegroundColor Red
}
