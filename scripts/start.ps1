param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath (Join-Path $projectRoot 'server')
$env:PORT = "$Port"
$env:WEB_DIR = Join-Path $projectRoot 'server/web'
$env:DOWNLOAD_DIR = Join-Path $projectRoot 'dist'
if (-not $env:DB_PATH) { $env:DB_PATH = Join-Path $projectRoot 'sayanything.db' }
Write-Host "SayAnything: http://localhost:$Port"
Write-Host 'Keep this terminal open. Press Ctrl+C to stop.'
$serverExe = Join-Path $projectRoot 'dist/sayanything-server.exe'
if (Test-Path -LiteralPath $serverExe) { & $serverExe } else { go run . }
if ($LASTEXITCODE -ne 0) { throw "Server exited with code $LASTEXITCODE" }
