param([switch]$Android, [switch]$Windows, [string]$ApiUrl = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Push-Location (Join-Path $projectRoot 'server')
try {
  go test ./... -count=1
  if ($LASTEXITCODE -ne 0) { throw 'Go tests failed' }
  go build -trimpath -ldflags '-s -w' -o (Join-Path $dist 'sayanything-server.exe') .
  if ($LASTEXITCODE -ne 0) { throw 'Go build failed' }
} finally { Pop-Location }
Push-Location (Join-Path $projectRoot 'client')
try {
  flutter analyze
  if ($LASTEXITCODE -ne 0) { throw 'Flutter analysis failed' }
  flutter test
  if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }
  $buildArgs = @()
  if ($ApiUrl) { $buildArgs += "--dart-define=API_URL=$ApiUrl" }
  if ($Android) {
    & (Join-Path $PSScriptRoot 'build-android-release.ps1') -ApiUrl $ApiUrl
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed' }
  }
  if ($Windows) {
    flutter build windows --release @buildArgs
    if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    & (Join-Path $PSScriptRoot 'pack-windows.ps1')
  }
} finally { Pop-Location }
Get-ChildItem -LiteralPath $dist -File | ForEach-Object { Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256 } | Format-Table
