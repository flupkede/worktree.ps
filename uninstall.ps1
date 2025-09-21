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

try {
  $Prefix = if ($Prefix) { $Prefix } else { Default-Prefix }
  $dest = Join-Path $Prefix 'wtx.ps1'
  if (Test-Path $dest) { Remove-Item -LiteralPath $dest -Force; Write-Info "Removed $dest" } else { Write-Warn "Not found: $dest" }

  # Remove shell hook from profile
  $profilePath = $PROFILE
  if (Test-Path $profilePath) {
    $start = '# wtx shell integration: auto-cd after wtx add/path/main/remove/clean (PowerShell)'
    $finish = '# wtx shell integration: end'
    $lines = Get-Content -LiteralPath $profilePath
    $mode = 0
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
      if ($mode -eq 0) {
        if ($line -eq $start) { $mode = 1; continue }
        $out.Add($line) | Out-Null
        continue
      }
      if ($mode -eq 1) {
        if ($line -eq $finish) { $mode = 2; continue }
        continue
      }
      if ($mode -eq 2) {
        if ([string]::IsNullOrWhiteSpace($line)) { $mode = 0; continue }
        $mode = 0
        $out.Add($line) | Out-Null
      }
    }
    $removedByLines = $false
    if ($mode -ne 0 -or ($lines -join "`n") -ne ($out -join "`n")) { $removedByLines = $true }
    if ($removedByLines) {
      Set-Content -LiteralPath $profilePath -Value $out -Encoding UTF8
      Write-Info "Removed wtx shell hook from $profilePath"
    } else {
      # Fallback: remove single-line collapsed hook
      $raw = Get-Content -LiteralPath $profilePath -Raw
      $pattern = [regex]::Escape($start) + '.*?' + [regex]::Escape($finish)
      $new = [regex]::Replace($raw, $pattern, '', 'Singleline')
      if ($new -ne $raw) {
        Set-Content -LiteralPath $profilePath -Value $new -Encoding UTF8
        Write-Info "Removed collapsed wtx shell hook from $profilePath"
      } else {
        Write-Warn "No wtx shell hook found in $profilePath"
      }
    }
  } else {
    Write-Warn "Profile not found: $profilePath"
  }

  Write-Info 'Uninstallation complete.'
} catch {
  Write-Err $_
  exit 1
}
