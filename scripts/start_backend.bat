@echo off
title Massage backend
REM Skip if something is already listening on port 3000 (e.g. started by the other launcher).
netstat -ano | findstr /r /c:":3000 .*LISTENING" >nul && (echo Backend already running on port 3000. & timeout /t 3 >nul & exit /b 0)
cd /d "%~dp0\..\backend"
if not exist node_modules call npm install
call npm start
pause
