param([switch]$Android, [switch]$Windows, [switch]$PackageOnly, [string]$TestPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location (Join-Path $projectRoot 'client')
try {
  if ($TestPath) {
    flutter test --no-pub $TestPath
    if ($LASTEXITCODE -ne 0) { throw 'Selected Flutter test failed' }
    return
  }
  if (-not $PackageOnly) {
    flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
    flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
    # Flutter 3.44 can reuse a web entrypoint with stale plugin registration
    # after pubspec changes. Regenerate that entrypoint without clearing native builds.
    $webCache = Join-Path $projectRoot 'client/.dart_tool/flutter_build'
    if (Test-Path -LiteralPath $webCache) {
      Get-ChildItem -LiteralPath $webCache -Filter 'web_entrypoint.stamp' -File -Recurse |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName }
    }
    flutter build web --release --no-pub --dart-define=API_URL=http://localhost:8081 --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
  }
    if ($Android) {
        & (Join-Path $PSScriptRoot 'build-android-release.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    }
    if ($Windows) {
        flutter build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
        & (Join-Path $PSScriptRoot 'pack-windows.ps1')
    }
} finally { Pop-Location }
