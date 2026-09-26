# the20sspa - Windows dev setup
# Installs Git, Node.js LTS, JDK 17, Flutter and the Android SDK + a Pixel emulator,
# clones the app, and runs its tests. Safe to re-run: finished steps are skipped.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$src      = Join-Path $env:USERPROFILE 'source'
$repoDir  = Join-Path $src 'the20sspa'
$flutter  = Join-Path $env:USERPROFILE 'flutter'
$sdk      = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$log      = Join-Path $src 'the20sspa_setup_log.txt'
$status   = Join-Path $src 'the20sspa_setup_status.txt'
Start-Transcript -Path $log -Force | Out-Null
"RUNNING" | Set-Content $status

function Step($msg) { Write-Host "`n==== $msg" -ForegroundColor Cyan }
function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}
function Add-UserPath($p) {
  $cur = [Environment]::GetEnvironmentVariable('Path','User')
  if (-not ($cur -split ';' | Where-Object { $_ -ieq $p })) {
    [Environment]::SetEnvironmentVariable('Path', ($cur.TrimEnd(';') + ';' + $p), 'User')
  }
  Refresh-Path
}

$accepted = Join-Path $src 'the20sspa_setup_licenses_accepted.txt'
if (-not (Test-Path $accepted)) {
Write-Host @"
This will install (from their official sources):
  - Git (portable MinGit), Microsoft OpenJDK 17 if needed
  - Flutter SDK (stable)                      -> $flutter
  - Android SDK, emulator, Android 35 image   -> $sdk   (~6-8 GB)
and accept the license agreements for these packages (including the Android SDK licenses).
"@
  $ans = Read-Host "Type Y to accept those license terms and continue"
  if ($ans -notmatch '^[Yy]') { "CANCELLED" | Set-Content $status; Stop-Transcript; exit 1 }
  "Accepted $(Get-Date)" | Set-Content $accepted
} else { Write-Host "License terms already accepted earlier ($(Get-Content $accepted))." }


function Download($url, $out) {
  Write-Host "Downloading $url"
  Invoke-WebRequest -UseBasicParsing $url -OutFile $out
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Step "Git"
$gitDir = Join-Path $env:USERPROFILE 'mingit'
if (-not (Get-Command git -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $gitDir 'cmd\git.exe'))) {
  $rel = Invoke-RestMethod -UseBasicParsing 'https://api.github.com/repos/git-for-windows/git/releases/latest'
  $asset = $rel.assets | Where-Object { $_.name -match '^MinGit-[\d\.]+-64-bit\.zip$' } | Select-Object -First 1
  $zip = Join-Path $env:TEMP 'mingit.zip'
  Download $asset.browser_download_url $zip
  Expand-Archive $zip -DestinationPath $gitDir -Force
}
if (Test-Path (Join-Path $gitDir 'cmd\git.exe')) { Add-UserPath (Join-Path $gitDir 'cmd') }
git --version
# Your global git config points at a CA bundle from an old Git install; use MinGit's bundle instead.
$ca = Join-Path $gitDir 'mingw64\etc\ssl\certs\ca-bundle.crt'
if (Test-Path $ca) { $env:GIT_SSL_CAINFO = $ca }

Step "Java 17+"
$javaCandidates = @(
  'C:\Program Files\Android\Android Studio\jbr',
  'C:\Program Files\Android\Android Studio\jre'
) + (Get-ChildItem 'C:\Program Files\Microsoft','C:\Program Files\Java','C:\Program Files\Eclipse Adoptium', (Join-Path $env:USERPROFILE 'jdk17') -Directory -ErrorAction SilentlyContinue | ForEach-Object FullName)
$javaHome = $null
foreach ($j in $javaCandidates) {
  $exe = Join-Path $j 'bin\java.exe'
  if (Test-Path $exe) {
    $v = (& $exe -version 2>&1 | Select-Object -First 1) -as [string]
    if ($v -match 'version "(\d+)') { if ([int]$Matches[1] -ge 17) { $javaHome = $j; break } }
  }
}
if (-not $javaHome) {
  $zip = Join-Path $env:TEMP 'jdk17.zip'
  Download 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip' $zip
  Expand-Archive $zip -DestinationPath (Join-Path $env:USERPROFILE 'jdk17') -Force
  $javaHome = (Get-ChildItem (Join-Path $env:USERPROFILE 'jdk17') -Directory | Select-Object -First 1).FullName
}
$env:JAVA_HOME = $javaHome
$env:Path = (Join-Path $javaHome 'bin') + ';' + $env:Path
[Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, 'User')
Write-Host "JAVA_HOME = $javaHome"
& (Join-Path $javaHome 'bin\java.exe') -version

Step "Flutter SDK"
if (-not (Test-Path (Join-Path $flutter 'bin\flutter.bat'))) {
  $rel = Invoke-RestMethod -UseBasicParsing 'https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json'
  $cur = $rel.releases | Where-Object { $_.hash -eq $rel.current_release.stable } | Select-Object -First 1
  $zip = Join-Path $env:TEMP 'flutter.zip'
  Download ($rel.base_url + '/' + $cur.archive) $zip
  Expand-Archive $zip -DestinationPath $env:USERPROFILE -Force
}
Add-UserPath (Join-Path $flutter 'bin')
flutter config --no-analytics | Out-Null
flutter --version

Step "Android SDK"
$cmdline = Join-Path $sdk 'cmdline-tools\latest\bin'
if (-not (Test-Path (Join-Path $cmdline 'sdkmanager.bat'))) {
  New-Item -ItemType Directory -Force -Path (Join-Path $sdk 'cmdline-tools') | Out-Null
  $zip = Join-Path $env:TEMP 'cmdline-tools.zip'
  Invoke-WebRequest 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' -OutFile $zip
  Expand-Archive $zip -DestinationPath (Join-Path $sdk 'cmdline-tools\tmp') -Force
  Move-Item (Join-Path $sdk 'cmdline-tools\tmp\cmdline-tools') (Join-Path $sdk 'cmdline-tools\latest') -Force
  Remove-Item (Join-Path $sdk 'cmdline-tools\tmp') -Recurse -Force
}
$env:ANDROID_HOME = $sdk
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
Add-UserPath $cmdline
Add-UserPath (Join-Path $sdk 'platform-tools')
Add-UserPath (Join-Path $sdk 'emulator')
$image = 'system-images;android-35;google_apis;x86_64'
(1..30 | ForEach-Object { 'y' }) | & (Join-Path $cmdline 'sdkmanager.bat') --licenses | Out-Null
& (Join-Path $cmdline 'sdkmanager.bat') 'platform-tools' 'emulator' 'platforms;android-35' 'platforms;android-36' 'build-tools;35.0.0' 'build-tools;36.0.0' 'build-tools;28.0.3' $image
(1..30 | ForEach-Object { 'y' }) | & (Join-Path $cmdline 'sdkmanager.bat') --licenses | Out-Null
flutter config --android-sdk $sdk | Out-Null

Step "Pixel emulator"
$avds = & (Join-Path $sdk 'emulator\emulator.exe') -list-avds
if ($avds -notcontains 'Pixel_7_API_35') {
  'no' | & (Join-Path $cmdline 'avdmanager.bat') create avd -n Pixel_7_API_35 -k $image -d pixel_7
}
Write-Host "Hardware acceleration check:"
& (Join-Path $sdk 'emulator\emulator.exe') -accel-check

Step "the20sspa code"
if (-not (Test-Path (Join-Path $repoDir '.git'))) {
  git clone -b fix/runnable-app https://github.com/Urer260000/massage_app_code_with_enhancements_with_tests_v11.git $repoDir
} else {
  git -C $repoDir pull
}
if (-not (Test-Path (Join-Path $repoDir 'frontend\pubspec.yaml'))) {
  Write-Host "ERROR: could not download the app code. Stopping." -ForegroundColor Red
  "FAILED clone" | Set-Content $status; Stop-Transcript | Out-Null; Read-Host "Press Enter to close"; exit 1
}

Step "Backend: install + tests"
Push-Location (Join-Path $repoDir 'backend')
npm install
npm test
$backendOk = $LASTEXITCODE -eq 0
Pop-Location

Step "Frontend: platform folders + tests"
Push-Location (Join-Path $repoDir 'frontend')
flutter create --platforms=android,ios,web --org com.the20sspa --project-name the20sspa .
powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoDir 'scripts\apply_branding.ps1')
flutter pub get
flutter analyze
flutter test
$frontendOk = $LASTEXITCODE -eq 0
Pop-Location

Step "flutter doctor"
flutter doctor -v

Step "Summary"
Write-Host "Backend tests passed:  $backendOk"
Write-Host "Frontend tests passed: $frontendOk"
"DONE backend=$backendOk frontend=$frontendOk" | Set-Content $status
Stop-Transcript | Out-Null
Write-Host "`nAll done. You can close this window."
Read-Host "Press Enter to close"
