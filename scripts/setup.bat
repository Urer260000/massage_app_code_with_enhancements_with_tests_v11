@echo off
title the20sspa - setup
REM One-time setup: installs backend packages, generates Flutter platform folders, applies branding, runs tests.
cd /d "%~dp0\..\backend"
call npm install || goto :err
call npm test || goto :err
cd /d "%~dp0\..\frontend"
call flutter create --platforms=android,ios,web --org com.the20sspa --project-name the20sspa . || goto :err
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_branding.ps1"
call flutter pub get || goto :err
call flutter test || goto :err
echo.
echo Setup complete.
pause
exit /b 0
:err
echo.
echo Setup failed - see the error above.
pause
exit /b 1
