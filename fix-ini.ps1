# Stop service, update ini, restart
Stop-Service TermService -Force -ErrorAction SilentlyContinue
Stop-Service UmRdpService -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 4
Write-Host "Services stopped"

$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent","Mozilla/5.0")
$data = $wc.DownloadString("https://raw.githubusercontent.com/asmtron/rdpwrap/master/res/rdpwrap.ini")
Write-Host "Downloaded: $($data.Length) chars"

$data | Set-Content "C:\Program Files\RDP Wrapper\rdpwrap.ini" -Encoding ASCII -Force
$sz = (Get-Item "C:\Program Files\RDP Wrapper\rdpwrap.ini").Length
Write-Host "Saved: $sz bytes"

Start-Service TermService
Start-Sleep -Seconds 6
Write-Host "TermService: $((Get-Service TermService).Status)"

$p = netstat -an | Select-String ":3389"
if ($p) { Write-Host "SUCCESS: Port 3389 LISTEN" -ForegroundColor Green; $p } else { Write-Host "FAIL: port 3389 not listening" -ForegroundColor Red }
