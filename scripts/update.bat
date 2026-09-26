@echo off
title the20sspa - update
REM Pulls the latest code, re-applies branding and runs all tests.
cd /d "%~dp0\.."
git fetch origin || goto :err
for /f %%b in ('git rev-parse --abbrev-ref HEAD') do set BRANCH=%%b
git reset --hard origin/%BRANCH% || goto :err
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply_branding.ps1"
cd backend
call npm install || goto :err
call npm test || goto :err
cd ..\frontend
call flutter pub get || goto :err
call flutter analyze || goto :err
call flutter test || goto :err
echo.
echo Up to date and all tests passed.
pause
exit /b 0
:err
echo.
echo Update failed - see the error above.
pause
exit /b 1
