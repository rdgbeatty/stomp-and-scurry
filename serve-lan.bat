@echo off
setlocal
if exist "%ProgramFiles%\nodejs\node.exe" (
    "%ProgramFiles%\nodejs\node.exe" "%~dp0serve-lan.cjs"
) else (
    node "%~dp0serve-lan.cjs"
)
if errorlevel 1 pause
