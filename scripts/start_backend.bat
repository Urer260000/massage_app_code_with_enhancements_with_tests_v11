@echo off
title Massage backend
cd /d "%~dp0\..\backend"
if not exist node_modules call npm install
call npm start
pause
