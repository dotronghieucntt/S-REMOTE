@echo off
echo Closing ZeroTier-QuickSetup...
taskkill /F /IM "ZeroTier-QuickSetup.exe" >nul 2>&1
timeout /t 2 /nobreak >nul

echo Deleting old EXE...
del "ZeroTier-QuickSetup.exe" >nul 2>&1
timeout /t 1 /nobreak >nul

echo Building new EXE...
powershell.exe -ExecutionPolicy Bypass -File "Build-EXE.ps1"
