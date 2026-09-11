param([string]$ApiUrl = '', [switch]$Online)
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$clientRoot = Join-Path $projectRoot 'client'
$registrant = Join-Path $clientRoot 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java'
$gradleWrapper = Join-Path $clientRoot 'android/gradlew.bat'

Push-Location $clientRoot
try {
    # Refresh Flutter's generated build configuration without starting Gradle.
    flutter build apk --release --no-pub --config-only
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android configuration failed' }

    # Flutter 3.44.8 registers integration_test in GeneratedPluginRegistrant.java
    # while correctly excluding the dev-only Android module from release builds.
    # Remove only that generated registration so test code is never packaged.
    $registrantText = [IO.File]::ReadAllText($registrant)
    $integrationTestBlock = '(?ms)^\s{4}try \{\r?\n\s+flutterEngine\.getPlugins\(\)\.add\(new dev\.flutter\.plugins\.integration_test\.IntegrationTestPlugin\(\)\);\r?\n\s{4}\} catch \(Exception e\) \{\r?\n\s+Log\.e\(TAG, "Error registering plugin integration_test,[^\r\n]+\r?\n\s{4}\}\r?\n'
    $releaseRegistrantText = [Text.RegularExpressions.Regex]::Replace($registrantText, $integrationTestBlock, '')
    if ($releaseRegistrantText -eq $registrantText -and $registrantText.Contains('dev.flutter.plugins.integration_test')) {
        throw 'Could not safely remove integration_test from GeneratedPluginRegistrant.java'
    }
    [IO.File]::WriteAllText($registrant, $releaseRegistrantText, [Text.UTF8Encoding]::new($false))

    Push-Location (Join-Path $clientRoot 'android')
    try {
        # Direct Gradle invocations default tree-shake-icons to false. Match
        # Flutter's release settings explicitly. Separate target builds keep the
        # same versionCode, unlike split-per-abi's architecture-based offsets.
        $gradleArgs = @(
            '--no-daemon', 'assembleRelease',
            '-Psplit-per-abi=false',
            '-Ptree-shake-icons=true', '-Pshrink=true'
        )
        if (-not $Online) { $gradleArgs += '--offline' }
        if ($ApiUrl) {
            $encodedDefine = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("API_URL=$ApiUrl"))
            $gradleArgs += "-Pdart-defines=$encodedDefine"
        }
        $apkOutput = Join-Path $clientRoot 'build/app/outputs/flutter-apk'
        $dist = Join-Path $projectRoot 'dist'
        New-Item -ItemType Directory -Path $dist -Force | Out-Null
        $variants = [ordered]@{
            'android-arm,android-arm64,android-x64' = 'sayanything-android.apk'
            'android-arm64' = 'sayanything-android-arm64.apk'
            'android-arm' = 'sayanything-android-armv7.apk'
            'android-x64' = 'sayanything-android-x64.apk'
        }
        foreach ($platforms in $variants.Keys) {
            Write-Output "Building $($variants[$platforms]) ($platforms)"
            & $gradleWrapper @gradleArgs "-Ptarget-platform=$platforms"
            if ($LASTEXITCODE -ne 0) { throw "Android release build failed: $platforms" }
            Copy-Item -LiteralPath (Join-Path $apkOutput 'app-release.apk') -Destination (Join-Path $dist $variants[$platforms]) -Force
        }
    } finally {
        Pop-Location
    }
} finally {
    Pop-Location
}
