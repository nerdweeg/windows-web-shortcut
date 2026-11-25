@echo off
rem Double-click launcher for New-WebShortcut.ps1.
rem Bypasses the execution policy for this run only; no system settings are changed.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-WebShortcut.ps1" %*
if errorlevel 1 pause
