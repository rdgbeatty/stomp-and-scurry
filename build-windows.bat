@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1"
set "build_result=%errorlevel%"
echo.
pause
exit /b %build_result%
