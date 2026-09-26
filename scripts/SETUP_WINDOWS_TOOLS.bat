@echo off
REM Installs portable Git, JDK 17, Flutter, Android SDK + Pixel emulator (no admin needed).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_windows_tools.ps1"
