$lines = Get-Content "C:\Program Files\RDP Wrapper\rdpwrap.ini"
$idx = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "19041\.6456") { $idx = $i; break }
}
Write-Host "Found at line $idx"
$lines[$idx..([Math]::Min($idx+25, $lines.Count-1))]
