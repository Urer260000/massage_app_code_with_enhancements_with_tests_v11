# Applies the20sspa branding to the generated Android project:
# app name shown under the launcher icon, cleartext HTTP to the local backend, and launcher icons.
param([string]$Frontend = (Join-Path $PSScriptRoot '..\frontend'))
$manifest = Join-Path $Frontend 'android\app\src\main\AndroidManifest.xml'
if (-not (Test-Path $manifest)) { Write-Host "No Android project yet - run flutter create first."; exit 0 }
$c = Get-Content $manifest -Raw
$c = $c -replace 'android:label="[^"]*"', 'android:label="the20sspa"'
if ($c -notmatch 'usesCleartextTraffic') {
  $c = $c -replace '<application', '<application android:usesCleartextTraffic="true"'
}
if ($c -notmatch 'android.permission.INTERNET') {
  $c = $c -replace '(<manifest[^>]*>)', "`$1`r`n    <uses-permission android:name=`"android.permission.INTERNET`"/>"
}
Set-Content $manifest $c -NoNewline
$res = Join-Path $Frontend 'android\app\src\main\res'
Get-ChildItem (Join-Path $PSScriptRoot '..\branding\android') -Directory | ForEach-Object {
  $dest = Join-Path $res $_.Name
  New-Item -ItemType Directory -Force $dest | Out-Null
  Copy-Item (Join-Path $_.FullName 'ic_launcher.png') $dest -Force
}
Write-Host "Applied the20sspa branding to the Android app."
