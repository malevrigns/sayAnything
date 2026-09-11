$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $projectRoot 'dist'
$names = @(
  'sayanything-android.apk',
  'sayanything-android-arm64.apk',
  'sayanything-android-armv7.apk',
  'sayanything-android-x64.apk',
  'sayanything-windows.zip',
  'sayanything-server.exe'
)
$files = foreach ($name in $names) {
  $path = Join-Path $dist $name
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing release artifact: $name" }
  $item = Get-Item -LiteralPath $path
  [ordered]@{name=$name; bytes=$item.Length; sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()}
}
$manifest = [ordered]@{version='1.3.0'; channel='self-signed-test'; generatedAt=[DateTime]::UtcNow.ToString('o'); files=@($files)}
$json = $manifest | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText((Join-Path $dist 'release-manifest.json'), $json, [Text.UTF8Encoding]::new($false))
Write-Output $json
