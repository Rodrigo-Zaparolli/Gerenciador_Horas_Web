@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start_edesk_central.ps1"
if errorlevel 1 pause
