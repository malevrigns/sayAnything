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
        $gradleArgs = @('--no-daemon', 'assembleRelease')
        if (-not $Online) { $gradleArgs += '--offline' }
        if ($ApiUrl) {
            $encodedDefine = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("API_URL=$ApiUrl"))
            $gradleArgs += "-Pdart-defines=$encodedDefine"
        }
        & $gradleWrapper @gradleArgs
        if ($LASTEXITCODE -ne 0) { throw 'Android release build failed' }
    } finally {
        Pop-Location
    }

    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination (Join-Path $projectRoot 'dist/sayanything-android.apk') -Force
} finally {
    Pop-Location
}
