#Requires -Version 5.1
<#
  CI gate for Khata Clone (college project).
  Runs: backend tests, flutter analyze (errors only), flutter tests.
  Usage: powershell -ExecutionPolicy Bypass -File scripts\ci.ps1
#>
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$failed = $false

function Step($name, $dir, $script) {
  Write-Host "`n=== $name ===" -ForegroundColor Cyan
  Push-Location $dir
  try {
    Invoke-Expression $script | Select-Object -Last 6
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $null) {
      Write-Host "$name FAILED (exit $LASTEXITCODE)" -ForegroundColor Red
      $script:failed = $true
    }
  } finally {
    Pop-Location
  }
}

Step 'backend tests' "$root\backend" 'npm test'
Step 'flutter analyze' "$root\app" 'flutter analyze --no-fatal-warnings --no-fatal-infos'
Step 'flutter tests' "$root\app" 'flutter test'

if ($failed) { Write-Host "`nCI RED." -ForegroundColor Red; exit 1 }
Write-Host "`nCI GREEN: all gates passed." -ForegroundColor Green
