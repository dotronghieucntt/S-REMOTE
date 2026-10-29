@echo off
chcp 65001 >nul
setlocal
title Kich hoat REMOTE vao PM2 / NMS CONTROL

rem ============================================================
rem  Dua trang remote.novivo.net vao he thong PM2 (NMS CONTROL).
rem
rem  Chay bang tai khoan dang giu PM2 daemon (ADMIN) - dung chay
rem  tu session khac, se bao "connect EPERM \\.\pipe\rpc.sock".
rem
rem  Hai tien trinh duoc them:
rem    novivo-remote         node server.js  -> 127.0.0.1:5301
rem    novivo-tunnel-remote  cloudflared     -> remote.novivo.net
rem ============================================================

set "PM2=C:\Users\HOST\AppData\Local\Programs\nodejs\pm2.cmd"
set "ECO=C:\Users\HOST\Desktop\NOVIVO\SOURCE\NOVIVO\ecosystem.config.js"
set "PS=powershell -NoProfile -ExecutionPolicy Bypass -Command"

echo.
echo [1/4] Dong cac tien trinh REMOTE chay tay ngoai PM2 (neu co)...
rem Node: tim dung tien trinh dang giu cong 5301 (KHONG loc theo 'server.js'
rem vi novivo-backend cung chay file ten server.js - loc kieu do se giet nham).
%PS% "$n=0; try { Get-NetTCPConnection -LocalPort 5301 -State Listen -EA Stop | Select-Object -Expand OwningProcess -Unique | ForEach-Object { $p=Get-Process -Id $_ -EA SilentlyContinue; if ($p -and $p.ProcessName -eq 'node') { Stop-Process -Id $_ -Force -EA SilentlyContinue; $n++ } } } catch {}; Get-CimInstance Win32_Process -Filter \"Name='cloudflared.exe'\" -EA SilentlyContinue | Where-Object { $_.CommandLine -like '*novivo-remote*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -EA SilentlyContinue; $n++ }; Write-Host ('      da dong ' + $n + ' tien trinh')"

echo.
echo [2/4] Khoi dong hai tien trinh trong PM2...
call "%PM2%" start "%ECO%" --only novivo-remote,novivo-tunnel-remote
if errorlevel 1 (
    echo       [!] PM2 bao loi. Kiem tra lai tai khoan dang chay file nay.
    pause
    exit /b 1
)

echo.
echo [3/4] Luu danh sach tien trinh de tu chay lai sau khi khoi dong may...
call "%PM2%" save

echo.
echo [4/4] Kiem tra...
"%SystemRoot%\System32\ping.exe" -n 4 127.0.0.1 >nul
%PS% "try { $r=Invoke-WebRequest -Uri 'http://127.0.0.1:5301/health' -UseBasicParsing -TimeoutSec 10; Write-Host ('      LOCAL  OK  ' + $r.Content) } catch { Write-Host '      LOCAL  LOI - xem: pm2 logs novivo-remote' }"
%PS% "try { $r=Invoke-WebRequest -Uri 'https://remote.novivo.net/health' -UseBasicParsing -TimeoutSec 20; Write-Host ('      PUBLIC OK  ' + $r.Content) } catch { Write-Host '      PUBLIC chua len - doi them ~30 giay roi thu lai, hoac xem: pm2 logs novivo-tunnel-remote' }"

echo.
echo Xong. Mo https://remote.novivo.net de xem trang.
echo.
echo Muon thay hai nut "REMOTE Web" va "Tunnel-REMOTE" trong NMS CONTROL
echo thi chay tiep file:  C:\Users\HOST\Desktop\NOVIVO\run pm2.bat
echo (file do tat NMS CONTROL cu va mo lai ban moi tu source .py)
echo.
pause
endlocal
