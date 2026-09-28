@echo off
chcp 65001 >nul 2>&1
title SeaGull 2.0 for DSH
where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh-files\install.ps1"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh-files\install.ps1"
)
pause
