# Create Icon for ZeroTier QuickSetup
Add-Type -AssemblyName System.Drawing

# Create a 256x256 bitmap
$size = 256
$bitmap = New-Object System.Drawing.Bitmap($size, $size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Background - Blue gradient
$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$brush1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30, 144, 255))
$graphics.FillEllipse($brush1, 10, 10, $size - 20, $size - 20)

# Draw ZeroTier-like network symbol
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 12)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

# Draw network nodes (circles)
$whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$graphics.FillEllipse($whiteBrush, 70, 70, 40, 40)    # Top-left node
$graphics.FillEllipse($whiteBrush, 146, 70, 40, 40)   # Top-right node
$graphics.FillEllipse($whiteBrush, 70, 146, 40, 40)   # Bottom-left node
$graphics.FillEllipse($whiteBrush, 146, 146, 40, 40)  # Bottom-right node
$graphics.FillEllipse($whiteBrush, 108, 108, 40, 40)  # Center node

# Draw connections
$pen2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 255, 255, 255), 8)
$graphics.DrawLine($pen2, 90, 90, 128, 128)    # Top-left to center
$graphics.DrawLine($pen2, 166, 90, 128, 128)   # Top-right to center
$graphics.DrawLine($pen2, 90, 166, 128, 128)   # Bottom-left to center
$graphics.DrawLine($pen2, 166, 166, 128, 128)  # Bottom-right to center

# Add "RDP" text
$font = New-Object System.Drawing.Font("Arial", 32, [System.Drawing.FontStyle]::Bold)
$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$graphics.DrawString("RDP", $font, $textBrush, 85, 195)

# Save as PNG first
$pngPath = "$PSScriptRoot\icon.png"
$bitmap.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)

Write-Host "[OK] PNG icon created: $pngPath" -ForegroundColor Green

# Clean up
$graphics.Dispose()
$bitmap.Dispose()

# Convert PNG to ICO using online method or manual
Write-Host ""
Write-Host "Note: PowerShell cannot directly create .ico files." -ForegroundColor Yellow
Write-Host "Converting PNG to ICO..." -ForegroundColor Yellow

# Try to create ICO using .NET
try {
    # Load the PNG
    $pngImage = [System.Drawing.Image]::FromFile($pngPath)
    
    # Create icon stream
    $iconPath = "$PSScriptRoot\icon.ico"
    $iconStream = [System.IO.File]::Create($iconPath)
    
    # ICO header
    $iconStream.WriteByte(0)  # Reserved
    $iconStream.WriteByte(0)
    $iconStream.WriteByte(1)  # Type: 1 = ICO
    $iconStream.WriteByte(0)
    $iconStream.WriteByte(1)  # Number of images
    $iconStream.WriteByte(0)
    
    # Image directory
    $iconStream.WriteByte([byte]$size)  # Width
    $iconStream.WriteByte([byte]$size)  # Height
    $iconStream.WriteByte(0)   # Color palette
    $iconStream.WriteByte(0)   # Reserved
    $iconStream.WriteByte(1)   # Color planes
    $iconStream.WriteByte(0)
    $iconStream.WriteByte(32)  # Bits per pixel
    $iconStream.WriteByte(0)
    
    # Image size (placeholder)
    $pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
    $imageSize = $pngBytes.Length
    $iconStream.WriteByte([byte]($imageSize -band 0xFF))
    $iconStream.WriteByte([byte](($imageSize -shr 8) -band 0xFF))
    $iconStream.WriteByte([byte](($imageSize -shr 16) -band 0xFF))
    $iconStream.WriteByte([byte](($imageSize -shr 24) -band 0xFF))
    
    # Image offset
    $offset = 22
    $iconStream.WriteByte([byte]($offset -band 0xFF))
    $iconStream.WriteByte([byte](($offset -shr 8) -band 0xFF))
    $iconStream.WriteByte([byte](($offset -shr 16) -band 0xFF))
    $iconStream.WriteByte([byte](($offset -shr 24) -band 0xFF))
    
    # Write PNG data
    $iconStream.Write($pngBytes, 0, $pngBytes.Length)
    $iconStream.Close()
    
    Write-Host "[OK] ICO icon created: $iconPath" -ForegroundColor Green
    
    $pngImage.Dispose()
} catch {
    Write-Host "[!] Could not create ICO automatically." -ForegroundColor Yellow
    Write-Host "Please convert $pngPath to icon.ico manually or use: https://convertio.co/png-ico/" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Icon creation complete!" -ForegroundColor Green
