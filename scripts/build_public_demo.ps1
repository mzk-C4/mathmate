param(
  [string]$GatewayToken = $env:MATHMATE_DEMO_GATEWAY_TOKEN,
  [ValidateSet('apk', 'web')]
  [string]$Target = 'apk'
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($GatewayToken)) {
  throw 'Set MATHMATE_DEMO_GATEWAY_TOKEN before building the public demo.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $projectRoot '.env'
$templatePath = Join-Path $projectRoot 'deploy/.env.public.template'
$backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ('mathmate-env-' + [guid]::NewGuid() + '.bak')

$current = Get-Content -Raw -LiteralPath $envPath
$ocrModel = [regex]::Match($current, '(?m)^VOLC_OCR_MODEL_ID=(.*)$').Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($ocrModel)) {
  throw 'VOLC_OCR_MODEL_ID is missing from the local development environment.'
}

Copy-Item -LiteralPath $envPath -Destination $backupPath
try {
  $publicEnv = Get-Content -Raw -LiteralPath $templatePath
  $publicEnv = $publicEnv.Replace('__DEMO_GATEWAY_TOKEN__', $GatewayToken)
  $publicEnv = $publicEnv.Replace('__VOLC_OCR_MODEL_ID__', $ocrModel)
  [System.IO.File]::WriteAllText(
    $envPath,
    $publicEnv,
    [System.Text.UTF8Encoding]::new($false)
  )
  Push-Location $projectRoot
  try {
    if ($Target -eq 'web') {
      flutter build web --release --base-href /website/
    } else {
      flutter build apk --release
    }
  } finally {
    Pop-Location
  }
} finally {
  Copy-Item -LiteralPath $backupPath -Destination $envPath -Force
  Remove-Item -LiteralPath $backupPath -Force
}
