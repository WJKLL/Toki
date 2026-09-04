# tools/rename_release_apk.ps1
# v1.26.0: rename built APK to xiangjugong-{version}-{tag}.apk
# (AGP 8 removed the outputs rename DSL; rename after build instead.)
# Usage: & .\tools\rename_release_apk.ps1 -Tag daily-quote
# Tag should match the feature label of the current CHANGELOG entry.
param(
    [Parameter(Mandatory = $true)]
    [string]$Tag
)

$ErrorActionPreference = 'Stop'
$apkDir = Join-Path $PSScriptRoot '..\build\app\outputs\flutter-apk'
$src = Join-Path $apkDir 'app-release.apk'
if (-not (Test-Path $src)) {
    Write-Error "build artifact not found: $src (run flutter build apk --release first)"
}

# Read version line from pubspec.yaml (version: X.Y.Z+N).
$pubspec = Get-Content (Join-Path $PSScriptRoot '..\pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+[0-9]+') {
    Write-Error 'no version line matched in pubspec.yaml'
}
$version = $Matches[1]

$target = Join-Path $apkDir "xiangjugong-$version-$Tag.apk"
Copy-Item $src $target -Force
Write-Host "generated: $target"
