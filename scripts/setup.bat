@echo off
REM One-time setup: installs backend packages, generates Flutter platform folders, runs tests.
cd /d "%~dp0\..\backend"
call npm install || goto :err
call npm test || goto :err
cd /d "%~dp0\..\frontend"
call flutter create --platforms=android,ios,web --org com.massageapp --project-name massage_app . || goto :err
powershell -NoProfile -Command "$m='android\app\src\main\AndroidManifest.xml'; $c=Get-Content $m -Raw; if($c -notmatch 'usesCleartextTraffic'){ $c=$c -replace '<application','<application android:usesCleartextTraffic=\"true\"'; if($c -notmatch 'android.permission.INTERNET'){ $c=$c -replace '(<manifest[^>]*>)','$1`n    <uses-permission android:name=\"android.permission.INTERNET\"/>' }; Set-Content $m $c }"
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
