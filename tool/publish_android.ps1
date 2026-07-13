[CmdletBinding()]
param(
    [string]$Server = "mathmate.top",
    [string]$IdentityFile = "$HOME/.ssh/mathmate_server",
    [string]$RemoteRoot = "/var/www/mathmate",
    [string]$BaseUrl = "https://mathmate.top",
    [string]$ReleaseNotes = "",
    [switch]$ForceUpdate,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$apkPath = Join-Path $repoRoot "build/app/outputs/flutter-apk/app-release.apk"
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mathmate-release-" + [guid]::NewGuid().ToString("N"))

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Command failed with exit code $LASTEXITCODE"
    }
}

try {
    $localProperties = Get-Content -LiteralPath (Join-Path $repoRoot "android/local.properties")
    $sdkLine = $localProperties | Where-Object { $_ -like "sdk.dir=*" } | Select-Object -First 1
    $flutterLine = $localProperties | Where-Object { $_ -like "flutter.sdk=*" } | Select-Object -First 1
    if (-not $sdkLine -or -not $flutterLine) {
        throw "android/local.properties must contain sdk.dir and flutter.sdk"
    }
    $androidSdk = $sdkLine.Substring("sdk.dir=".Length).Replace("\\", "\")
    $flutterSdk = $flutterLine.Substring("flutter.sdk=".Length).Replace("\\", "\")
    $flutterCommand = Join-Path $flutterSdk "bin/flutter.bat"

    if (-not $SkipBuild) {
        Invoke-Checked $flutterCommand @("build", "apk", "--release")
    }
    if (-not (Test-Path -LiteralPath $apkPath)) {
        throw "APK not found: $apkPath"
    }

    $apkAnalyzer = Get-ChildItem -LiteralPath (Join-Path $androidSdk "cmdline-tools") `
        -Recurse -Filter "apkanalyzer.bat" | Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $apkAnalyzer) {
        throw "apkanalyzer.bat was not found in $androidSdk"
    }

    $version = (& $apkAnalyzer manifest version-name $apkPath).Trim()
    $buildNumber = [int64]((& $apkAnalyzer manifest version-code $apkPath).Trim())
    if ($LASTEXITCODE -ne 0 -or -not $version -or $buildNumber -le 0) {
        throw "Unable to read APK version metadata"
    }

    $apkInfo = Get-Item -LiteralPath $apkPath
    $sha256 = (Get-FileHash -LiteralPath $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $remoteFileName = "mathmate-$version-$buildNumber.apk"
    $apkUrl = "$BaseUrl/app/$remoteFileName"
    if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
        $ReleaseNotes = "MathMate v$version update. See the in-app changelog for details."
    }

    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $manifestPath = Join-Path $tempDir "version.json"
    $manifestJson = [ordered]@{
        version = $version
        buildNumber = $buildNumber
        apkUrl = $apkUrl
        apkSizeBytes = $apkInfo.Length
        apkSha256 = $sha256
        forceUpdate = [bool]$ForceUpdate
        releaseNotes = $ReleaseNotes
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText(
        $manifestPath,
        $manifestJson,
        [System.Text.UTF8Encoding]::new($false)
    )

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $remoteStage = "/tmp/mathmate-android-$timestamp"
    Invoke-Checked "ssh" @("-o", "BatchMode=yes", "-i", $IdentityFile, "root@$Server", "mkdir -p '$remoteStage'")
    Invoke-Checked "scp" @("-i", $IdentityFile, $apkPath, "root@${Server}:$remoteStage/$remoteFileName")
    Invoke-Checked "scp" @("-i", $IdentityFile, $manifestPath, "root@${Server}:$remoteStage/version.json")

    $remoteCommand = @'
set -euo pipefail
stage='{{STAGE}}'
root='{{ROOT}}'
apk='{{APK}}'
expected_size='{{SIZE}}'
expected_sha='{{SHA}}'
actual_size=$(stat -c%s "$stage/$apk")
actual_sha=$(sha256sum "$stage/$apk" | awk '{print $1}')
test "$actual_size" = "$expected_size"
test "$actual_sha" = "$expected_sha"
python3 -m json.tool "$stage/version.json" >/dev/null
mkdir -p "$root/app" "/root/backups/mathmate-android/{{TIMESTAMP}}"
if [ -f "$root/version.json" ]; then cp -a "$root/version.json" "/root/backups/mathmate-android/{{TIMESTAMP}}/version.json"; fi
install -m 0644 "$stage/$apk" "$root/app/$apk"
install -m 0644 "$stage/version.json" "$root/version.json.new"
mv -f "$root/version.json.new" "$root/version.json"
rm -rf "$stage"
'@
    $remoteCommand = $remoteCommand.Replace("{{STAGE}}", $remoteStage).
        Replace("{{ROOT}}", $RemoteRoot).
        Replace("{{APK}}", $remoteFileName).
        Replace("{{SIZE}}", $apkInfo.Length.ToString()).
        Replace("{{SHA}}", $sha256).
        Replace("{{TIMESTAMP}}", $timestamp)
    Invoke-Checked "ssh" @("-o", "BatchMode=yes", "-i", $IdentityFile, "root@$Server", $remoteCommand)

    $published = Invoke-RestMethod -Uri "$BaseUrl/version.json?t=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
    if ([int64]$published.buildNumber -ne $buildNumber -or $published.apkSha256 -ne $sha256) {
        throw "Public version.json does not match the uploaded APK"
    }
    $head = Invoke-WebRequest -Uri $apkUrl -Method Head
    if ($head.StatusCode -ne 200 -or [int64]$head.Headers["Content-Length"] -ne $apkInfo.Length) {
        throw "Public APK verification failed"
    }

    Write-Host "Published MathMate $version+$buildNumber"
    Write-Host "APK: $apkUrl"
    Write-Host "SHA-256: $sha256"
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force
    }
}
