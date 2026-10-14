param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath (Join-Path $projectRoot 'server')
$env:PORT = "$Port"
$env:WEB_DIR = Join-Path $projectRoot 'server/web'
$env:DOWNLOAD_DIR = Join-Path $projectRoot 'dist'
if (-not $env:DB_PATH) { $env:DB_PATH = Join-Path $projectRoot 'sayanything.db' }
if (-not $env:FFMPEG_PATH) {
    $localFFmpeg = Join-Path $projectRoot '.tools/ffmpeg/bin/ffmpeg.exe'
    if (-not (Test-Path -LiteralPath $localFFmpeg)) {
        $ffmpegRoot = Join-Path $projectRoot '.tools/ffmpeg'
        if (Test-Path -LiteralPath $ffmpegRoot) {
            $ffmpegBuild = Get-ChildItem -LiteralPath $ffmpegRoot -Directory | Sort-Object Name -Descending | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin/ffmpeg.exe') } | Select-Object -First 1
            if ($ffmpegBuild) { $localFFmpeg = Join-Path $ffmpegBuild.FullName 'bin/ffmpeg.exe' }
        }
    }
    if (Test-Path -LiteralPath $localFFmpeg) { $env:FFMPEG_PATH = $localFFmpeg }
}
Write-Host "SayAnything: http://localhost:$Port"
Write-Host 'Keep this terminal open. Press Ctrl+C to stop.'

# Prefer the packaged binary only while it is at least as new as the Go sources.
# A stale dist/sayanything-server.exe silently serves an old API, so fall back to
# `go run .` (and say so) whenever any non-test source or go.mod is newer.
$serverExe = Join-Path $projectRoot 'dist/sayanything-server.exe'
$useExe = $false
if (Test-Path -LiteralPath $serverExe) {
    $exeTime = (Get-Item -LiteralPath $serverExe).LastWriteTimeUtc
    $sources = Get-ChildItem -LiteralPath (Join-Path $projectRoot 'server') -File |
        Where-Object { ($_.Extension -eq '.go' -and $_.Name -notlike '*_test.go') -or $_.Name -in @('go.mod', 'go.sum') }
    $newer = $sources | Where-Object { $_.LastWriteTimeUtc -gt $exeTime }
    $hasGo = [bool](Get-Command go -ErrorAction SilentlyContinue)
    if (-not $newer) {
        $useExe = $true
    } elseif ($hasGo) {
        Write-Host "dist/sayanything-server.exe is older than server sources ($($newer[0].Name) changed later); running 'go run .' instead. Run scripts/build.ps1 to refresh the binary."
    } else {
        Write-Warning 'dist/sayanything-server.exe is older than server sources and Go is not installed; starting the stale binary anyway.'
        $useExe = $true
    }
}
if ($useExe) { & $serverExe } else { go run . }
if ($LASTEXITCODE -ne 0) { throw "Server exited with code $LASTEXITCODE" }
