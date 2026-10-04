param([string]$ToolRoot = 'C:\dsbuild')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$flutter = Join-Path $ToolRoot 'flutter/bin/flutter.bat'
$env:PUB_CACHE = Join-Path $ToolRoot 'pub-cache'
$env:GRADLE_USER_HOME = Join-Path $ToolRoot 'gradle-home'
$env:JAVA_HOME = Join-Path $ToolRoot 'jdk17'
$env:ANDROID_HOME = Join-Path $ToolRoot 'android-sdk'
$env:DS_OFFLINE_BUILD = 'true'
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
foreach ($required in @($flutter, $env:PUB_CACHE, $env:GRADLE_USER_HOME, $env:JAVA_HOME, $env:ANDROID_HOME)) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing local tool or cache: $required. Automatic downloads are disabled." }
}
& $flutter pub get --offline
if ($LASTEXITCODE -ne 0) { throw 'Offline dependency resolution failed' }
& $flutter analyze --no-pub
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed' }
& $flutter test --no-pub
if ($LASTEXITCODE -ne 0) { throw 'Regression tests failed' }
& $flutter build apk --release --no-pub
if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
$apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
$java = Join-Path $env:JAVA_HOME 'bin/java.exe'
$signer = Join-Path $env:ANDROID_HOME 'build-tools/36.0.0/lib/apksigner.jar'
$certificate = & $java -jar $signer verify --print-certs $apk
if ($LASTEXITCODE -ne 0 -or ($certificate -join "`n") -notmatch '566bba04384837a3d4903ce70281374412d516c74a1f3275d7ec27d34f87cbc1') {
    throw 'Signing identity differs from v1.1.6. Use the original signing environment for in-place upgrades.'
}
New-Item -ItemType Directory -Path (Join-Path $projectRoot 'dist') -Force | Out-Null
$output = Join-Path $projectRoot 'dist/wanxiang-v1.3.1.apk'
Copy-Item -LiteralPath $apk -Destination $output -Force
Get-FileHash -LiteralPath $output -Algorithm SHA256
Write-Output "Build and verification complete: $output"
