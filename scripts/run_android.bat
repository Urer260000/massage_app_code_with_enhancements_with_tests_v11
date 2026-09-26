@echo off
title Massage app - Android
REM Starts the backend, boots the Android emulator, and runs the app on it.
start "" "%~dp0start_backend.bat"
cd /d "%~dp0\..\frontend"
for /f "tokens=1" %%e in ('flutter emulators ^| findstr /i "Pixel"') do (set EMU=%%e & goto :found)
:found
if defined EMU (
  call flutter emulators --launch %EMU%
  echo Waiting for the emulator to boot...
  timeout /t 40 /nobreak >nul
)
call flutter run -d emulator
pause
