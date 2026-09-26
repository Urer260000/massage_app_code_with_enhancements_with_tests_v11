@echo off
title Massage app - iPhone preview
REM Starts the backend, serves the Flutter web build on port 8080, and opens it in an iPhone frame.
start "" "%~dp0start_backend.bat"
start "" "%~dp0iphone_preview.html"
cd /d "%~dp0\..\frontend"
call flutter run -d web-server --web-port 8080 --web-hostname localhost
pause
