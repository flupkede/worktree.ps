#!/usr/bin/env pwsh
#requires -Version 7.0

param(
  [string]$Prefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info($m){ Write-Host "[wtx] $m" -ForegroundColor Cyan }
function Write-Warn($m){ Write-Host "[wtx] $m" -ForegroundColor Yellow }
function Write-Err($m){ Write-Host "[wtx] $m" -ForegroundColor Red }

function Default-Prefix {
  if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'Programs/wtx') }
  if ($IsWindows) { return (Join-Path $HOME '.local/bin') }
  return (Join-Path $HOME '.local/bin')
}

function Ensure-Dir([string]$p){ if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null } }

try {
  $Prefix = if ($Prefix) { $Prefix } else { Default-Prefix }
  Ensure-Dir $Prefix

  $src = Join-Path $PSScriptRoot 'wtx.ps1'
  if (-not (Test-Path $src)) { throw "source not found: $src" }

  $dest = Join-Path $Prefix 'wtx.ps1'
  Copy-Item -LiteralPath $src -Destination $dest -Force
  Write-Info "Installed wtx to $dest"

  # Append shell hook to profile (auto-cd helper function `wtx`)
  $profilePath = $PROFILE
  $profileDir = Split-Path -Parent $profilePath
  Ensure-Dir $profileDir
  if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath | Out-Null }

  $startMarker = '# wtx shell integration: auto-cd after wtx add/path/main/remove/clean (PowerShell)'
  $endMarker = '# wtx shell integration: end'

  $existing = Select-String -Path $profilePath -SimpleMatch -Pattern $startMarker -ErrorAction SilentlyContinue
  if ($existing) {
    Write-Warn 'Shell hook already present in profile (skipping append)'
  } else {
    $snippet = & pwsh -NoLogo -NoProfile -File $dest shell-hook pwsh
    if (-not $snippet) { throw 'failed to generate shell-hook snippet' }
    # Append with proper newlines, one line at a time
    Add-Content -LiteralPath $profilePath -Value ""
    ($snippet -split "`r?`n") | ForEach-Object { Add-Content -LiteralPath $profilePath -Value $_ }
    Add-Content -LiteralPath $profilePath -Value ""
    Write-Info "Appended shell hook to $profilePath"
  }

  Write-Info 'Reload your profile: . $PROFILE'
  Write-Info 'Then run: wtx help'
} catch {
  Write-Err $_
  exit 1
}
