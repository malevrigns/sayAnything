$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$release = Join-Path $projectRoot 'client/build/windows/x64/runner/Release'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio locator is missing; install the C++ desktop build workload.' }
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$redistRoot = Join-Path $vs 'VC/Redist/MSVC'
$version = Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object Name -Match '^\d+\.\d+\.\d+$' | Sort-Object { [Version]$_.Name } | Select-Object -Last 1
if (-not $version) { throw 'Microsoft C++ redistributable files were not found.' }
$crt = Join-Path $version.FullName 'x64/Microsoft.VC143.CRT'
if (-not (Test-Path -LiteralPath $crt)) { throw "Missing x64 redistributable directory: $crt" }
Get-ChildItem -LiteralPath $crt -Filter '*.dll' -File | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $release -Force }
Copy-Item -LiteralPath (Join-Path $projectRoot 'client/assets/fonts/OFL.txt') -Destination (Join-Path $release 'NotoSansSC-LICENSE.txt') -Force
$dist = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
Compress-Archive -Path (Join-Path $release '*') -DestinationPath (Join-Path $dist 'sayanything-windows.zip') -Force
Write-Host 'Windows package includes the Microsoft C++ runtime DLLs.'
