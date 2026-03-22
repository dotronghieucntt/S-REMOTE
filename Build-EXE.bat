@echo off
title Build ZeroTier QuickSetup to EXE
color 0A

echo ===============================================
echo    ZeroTier QuickSetup - Build to EXE
echo ===============================================
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp0Build-EXE.ps1"

pause
