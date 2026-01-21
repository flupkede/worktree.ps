#!/usr/bin/env pwsh
#requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Global:WTX_Version = '0.1.0-ps1'
$Script:WTX_ScriptPath = $PSCommandPath

function Write-Info($msg) { Write-Host "[wtx] $msg" -ForegroundColor Cyan }
function Write-Warn($msg) { Write-Host "[wtx] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[wtx] $msg" -ForegroundColor Red }

<# Config and utilities #>
function Get-UserHome {
  if ($env:USERPROFILE) { return $env:USERPROFILE }
  try { return [Environment]::GetFolderPath('UserProfile') } catch { }
  return (Join-Path $env:SystemDrive 'Users\Public')
}

# Local-only configuration: values are stored in <repo>/.wtx.kv

$CONFIG_DEFAULTS = @{
  'repo.path'                    = Join-Path (Get-UserHome) 'Developer/your-project'
  'repo.branch'                  = ''
  'add.branch-prefix'            = 'feat/'
  'add.copy-env.enabled'         = 'true'
  'add.copy-env.files'           = '[".env",".env.local"]'
  'add.install-deps.enabled'     = 'true'
  'add.install-deps.command'     = ''
  'add.serve-dev.enabled'        = 'true'
  'add.serve-dev.command'        = ''
  'add.serve-dev.logging-path'   = 'tmp'
  'language'                     = 'en'
}

function Load-Config {
  $cfg = [ordered]@{}
  # Prefer repo-local config only
  $repoRoot = Repo-Root .
  if ($repoRoot) {
    $localPath = Join-Path $repoRoot '.wtx.kv'
    if (Test-Path $localPath) {
      Get-Content -LiteralPath $localPath | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $k = $line.Substring(0, $idx).Trim()
        $v = $line.Substring($idx + 1).Trim()
        $cfg[$k] = $v
      }
    }
  }
  foreach ($k in $CONFIG_DEFAULTS.Keys) {
    if ($k -in @('repo.path','repo.branch')) { continue }
    if (-not $cfg.Contains($k)) { $cfg[$k] = $CONFIG_DEFAULTS[$k] }
  }
  return $cfg
}

# Lightweight KV helpers for config mutations
function __Read-Kv([string]$path) {
  $m = [ordered]@{}
  if (-not (Test-Path $path)) { return $m }
  Get-Content -LiteralPath $path | ForEach-Object {
    $line = $_.Trim()
    if (-not $line -or $line.StartsWith('#')) { return }
    $idx = $line.IndexOf('=')
    if ($idx -lt 1) { return }
    $k = $line.Substring(0, $idx).Trim()
    $v = $line.Substring($idx + 1).Trim()
    $m[$k] = $v
  }
  return $m
}

function __Write-Kv([string]$path, [hashtable]$map) {
  $dir = Split-Path -Parent $path
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
  $lines = @()
  foreach ($k in ($map.Keys | Sort-Object)) { $lines += "$k=$($map[$k])" }
  Set-Content -LiteralPath $path -Value $lines -Encoding UTF8
}

function Config-Set([string]$key, [string]$value) {
  $root = Repo-Root .
  if (-not $root) { throw 'wtx: run inside a git repo or worktree to modify local config' }
  $p = Join-Path $root '.wtx.kv'
  $m = __Read-Kv $p
  $m[$key] = $value
  __Write-Kv $p $m
}

function Config-Unset([string]$key) {
  $root = Repo-Root .
  if (-not $root) { throw 'wtx: run inside a git repo or worktree to modify local config' }
  $p = Join-Path $root '.wtx.kv'
  $m = __Read-Kv $p
  if ($m.Contains($key)) { $null = $m.Remove($key) }
  __Write-Kv $p $m
}

function Parse-Bool([string]$val) {
  if (-not $val) { return $false }
  switch ($val.ToLowerInvariant()) {
    '1' { return $true }
    'true' { return $true }
    'yes' { return $true }
    'on' { return $true }
    '0' { return $false }
    'false' { return $false }
    'no' { return $false }
    'off' { return $false }
    default { return $false }
  }
}

function Parse-StringArray([string]$val) {
  if (-not $val) { return @() }
  $val = $val.Trim()
  if ($val.StartsWith('[') -and $val.EndsWith(']')) {
    try {
      $parsed = $val | ConvertFrom-Json -AsArray
      if ($parsed) { return ,(@($parsed | ForEach-Object { "$_" })) }
    } catch { }
  }
  return ,(@($val.Split(',') | ForEach-Object { $_.Trim(' ', '"', "'", '[', ']', "`t") } | Where-Object { $_ }))
}

function Require-Git {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git is required' }
}

function Repo-Root([string]$start) {
  Require-Git
  $start = if ($start) { $start } else { (Get-Location).Path }
  $p = & git -C $start rev-parse --show-toplevel 2>$null
  if ($LASTEXITCODE -ne 0 -or -not $p) { return $null }
  return $p.Trim()
}

function Default-Branch([string]$repoPath) {
  Require-Git
  $branch = (& git -C $repoPath rev-parse --abbrev-ref origin/HEAD 2>$null).Trim()
  if ($LASTEXITCODE -eq 0 -and $branch) {
    if ($branch -match 'origin/(.+)$') { return $Matches[1] }
  }
  foreach ($b in @('main','master')) {
    $exists = (& git -C $repoPath rev-parse --verify --quiet "$b" 2>$null)
    if ($LASTEXITCODE -eq 0) { return $b }
  }
  return 'main'
}

function Validate-WorktreeName([string]$name) {
  if (-not $name) { return $false }
  if ($name -eq '.' -or $name -eq '..') { return $false }
  if ($name -match '[\\/\s]') { return $false }
  if ($name -match '^[~]') { return $false }
  return $true
}

function Compute-WorktreePath([string]$repoPath, [string]$name) {
  $repoDir = Split-Path -Leaf $repoPath
  $parent = Split-Path -Parent $repoPath
  return Join-Path $parent ("$repoDir.$name")
}

function Get-Worktrees([string]$repoPath) {
  if (-not $repoPath) { throw 'Get-Worktrees: repoPath is required' }
  if (-not (Test-Path $repoPath)) { throw "Get-Worktrees: not found: $repoPath" }
  Require-Git
  $lines = & git -C $repoPath worktree list --porcelain 2>$null
  $raw = @()
  if ($LASTEXITCODE -ne 0 -or -not $lines) {
    # Fallback: parse non-porcelain output (less reliable)
    $fallback = & git -C $repoPath worktree list 2>$null
    foreach ($ln in $fallback) {
      $p = ($ln -split '\s+')[0]
      if ($p) { $raw += [pscustomobject]@{ Path = $p; Branch = ''; Head = '' } }
    }
  } else {
    $cur = @{}
    foreach ($ln in $lines) {
      $t = $ln.Trim()
      if (-not $t) { continue }
      if ($t.StartsWith('worktree ')) {
        if ($cur.ContainsKey('Path')) { $raw += [pscustomobject]$cur; $cur = @{} }
        $cur['Path'] = $t.Substring(9).Trim()
        continue
      }
      if ($t.StartsWith('branch ')) {
        $br = $t.Substring(7).Trim()
        if ($br -and $br.StartsWith('refs/heads/')) { $br = $br.Substring(11) }
        $cur['Branch'] = $br
        continue
      }
      if ($t.StartsWith('HEAD ')) { $cur['Head'] = $t.Substring(5).Trim(); continue }
    }
    if ($cur.ContainsKey('Path')) { $raw += [pscustomobject]$cur }
  }

  # Derive Name from path convention: <parent>/<repo>.<name>
  $repoDir = Split-Path -Leaf $repoPath
  $parent = Split-Path -Parent $repoPath
  $prefix = Join-Path $parent ($repoDir + '.')
  $prefixFwd = $prefix -replace '\\','/'
  $repoPathFwd = ([IO.Path]::GetFullPath($repoPath)) -replace '\\','/'
  $results = @()
  foreach ($it in $raw) {
    $p = ("" + $it.Path)
    $pFwd = $p -replace '\\','/'
    $name = $null
    if (([IO.Path]::GetFullPath($p) -replace '\\','/').TrimEnd('/') -eq $repoPathFwd.TrimEnd('/')) {
      $name = ''
    } elseif ($pFwd.StartsWith($prefixFwd)) {
      $name = $pFwd.Substring($prefixFwd.Length)
    } else {
      $leaf = Split-Path -Leaf $p
      $prefixLeaf = "$repoDir."
      if ($leaf.StartsWith($prefixLeaf)) { $name = $leaf.Substring($prefixLeaf.Length) } else { $name = $leaf }
    }
    $results += [pscustomobject]@{ Path = $p; Name = $name; Branch = $it.Branch; Head = $it.Head }
  }
  return ,$results
}

function Cmd-Help {
  @'
Usage: wtx.ps1 <command> [args]

Commands:
  help          Show this help
  init          Capture repo.path and default branch for current repo;
                writes all defaults to local repo .wtx.kv
  list          List git worktrees
  main          Print configured main repo path
  path <name>   Print absolute path for a worktree name
  add <name>    Create worktree (branch, copy .env*, install deps, start dev)
  rm [name]     Remove current or named worktree and its branch
  clean         Remove numerically named worktrees (feat/<digits>)
  config list|get|set|unset  Manage local config (list/get shows merged view)
  shell-hook    Print PowerShell profile snippet with auto-cd
  self-install [-Prefix <dir>]  Copy wtx to install location and add shell hook
'@ | Write-Host
}

function Cmd-Init {
  param([string[]]$argv)
  Require-Git
  $repoPath = Repo-Root .
  if (-not $repoPath) { throw 'wtx: not inside a git repository' }
  $userHome = [IO.Path]::GetFullPath((Get-UserHome))
  $repoFull = [IO.Path]::GetFullPath($repoPath)
  if ($repoFull -eq $userHome) { throw 'wtx: refusing to target home directory; choose a project repository' }

  $branch = Default-Branch $repoPath
  $p = Join-Path $repoPath '.wtx.kv'
  $m = __Read-Kv $p
  # Always set core keys to current repo/branch
  $m['repo.path'] = $repoPath
  $m['repo.branch'] = $branch
  # Materialize all default keys if missing
  foreach ($k in $CONFIG_DEFAULTS.Keys) {
    if (-not $m.Contains($k)) { $m[$k] = $CONFIG_DEFAULTS[$k] }
  }
  __Write-Kv $p $m
  Write-Info "Wrote local config: $p"
  Write-Info "repo.path=$repoPath; repo.branch=$branch"
  Write-Info 'wtx init complete; future commands will use these defaults'
}

function Cmd-List {
  $cfg = Load-Config
  $repoPath = $cfg['repo.path']
  if (-not $repoPath) { throw 'wtx is not configured; run "wtx init" inside your repository first' }
  if (-not (Test-Path $repoPath)) { throw "project directory not found: $repoPath" }
  Require-Git
  & git -C $repoPath worktree list
}

function Cmd-Main {
  $cfg = Load-Config
  $repoPath = $cfg['repo.path']
  if (-not $repoPath) { throw 'wtx is not configured yet; run "wtx.ps1 init" inside your repository first' }
  Write-Output $repoPath
}

function Cmd-Path([string]$name) {
  if (-not $name) { throw 'path requires exactly one worktree name' }
  $cfg = Load-Config
  $repoPath = $cfg['repo.path']
  if (-not $repoPath) { throw 'wtx is not configured; run "wtx init" inside your repository first' }
  if (-not (Test-Path $repoPath)) { throw "project directory not found: $repoPath" }
  Write-Output (Compute-WorktreePath $repoPath $name)
}

function Start-BackgroundCommand([string]$command, [string]$cwd, [string]$logDir) {
  if (-not (Test-Path $cwd)) { throw "missing directory: $cwd" }
  if (-not $logDir) { $logDir = 'tmp' }
  $absLogDir = if ([IO.Path]::IsPathRooted($logDir)) { $logDir } else { Join-Path $cwd $logDir }
  if (-not (Test-Path $absLogDir)) { New-Item -ItemType Directory -Path $absLogDir | Out-Null }
  $logFile = Join-Path $absLogDir 'dev.log'
  $ps = (Get-Process -Id $PID).Path
  $p = Start-Process -FilePath $ps -ArgumentList @('-NoLogo','-NoProfile','-Command', $command) -WorkingDirectory $cwd -RedirectStandardOutput $logFile -RedirectStandardError $logFile -WindowStyle Hidden -PassThru
  return $p.Id
}

function Cmd-Add([string]$name) {
  if (-not (Validate-WorktreeName $name)) { throw "invalid worktree name: $name" }
  $cfg = Load-Config
  $repoPath = $cfg['repo.path']
  if (-not $repoPath) { throw 'wtx is not configured; run "wtx init" inside your repository first' }
  if (-not (Test-Path $repoPath)) { throw "project directory not found: $repoPath" }
  Require-Git

  $worktreePath = Compute-WorktreePath $repoPath $name
  if (Test-Path $worktreePath) { throw "worktree path already exists: $worktreePath" }

  $branchPrefix = $cfg['add.branch-prefix']; if (-not $branchPrefix) { $branchPrefix = 'feat/' }
  $branchName = "$branchPrefix$name"
  $baseBranch = $cfg['repo.branch']; if (-not $baseBranch) { $baseBranch = Default-Branch $repoPath }

  Write-Info "Creating worktree: $worktreePath (branch $branchName)"
   
  # Check if branch already exists (try with prefix first, then without prefix)
  $existingBranch = & git -C $repoPath branch --list $branchName
  $existingBranch = if ($existingBranch) { $existingBranch.Trim() } else { $null }

  if (!$existingBranch) {
    # Try without prefix (just the name)
    $branchWithoutPrefix = & git -C $repoPath branch --list $name
    $branchWithoutPrefix = if ($branchWithoutPrefix) { $branchWithoutPrefix.Trim() } else { $null }

    if ($branchWithoutPrefix) {
      $existingBranch = $name
      $branchName = $name  # Use the branch without prefix
    }
  }

  if ($existingBranch) {
    # Branch exists: create worktree from existing branch
    Write-Info "Using existing branch: $branchName"
    & git -C $repoPath worktree add $worktreePath $branchName | Out-Host
  } else {
    # Branch doesn't exist: create new branch from base
    & git -C $repoPath worktree add -b $branchName $worktreePath $baseBranch | Out-Host
  }
  Write-Info 'Worktree created'

  if (Parse-Bool $cfg['add.copy-env.enabled']) {
    $files = Parse-StringArray $cfg['add.copy-env.files']
    foreach ($f in $files) {
      $src = Join-Path $repoPath $f
      $matchingFiles = @(Get-ChildItem -Path $src -Recurse -ErrorAction SilentlyContinue)
      foreach ($file in $matchingFiles) {
        # Calculate relative path from repo root to preserve directory structure
        $relativePath = $file.FullName.Substring($repoPath.Length + 1)
        $dest = Join-Path $worktreePath $relativePath

        # Ensure destination directory exists
        $destDir = Split-Path $dest -Parent
        if ($destDir -and !(Test-Path $destDir)) {
          New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $file.FullName -Destination $dest -Force
        Write-Info ("Copy $relativePath")
      }
    }
  }
  # Copy repo-local wtx config so commands inside the worktree still know the main repo
  $localCfgSrc = Join-Path $repoPath '.wtx.kv'
  if (Test-Path $localCfgSrc) {
    try { Copy-Item -LiteralPath $localCfgSrc -Destination (Join-Path $worktreePath '.wtx.kv') -Force } catch { }
  }

  if (Parse-Bool $cfg['add.install-deps.enabled']) {
    $installCmd = $cfg['add.install-deps.command']
    if ($installCmd) {
      Write-Info "Installing dependencies ($installCmd)"
      Push-Location $worktreePath
      try { & pwsh -NoLogo -NoProfile -Command $installCmd } finally { Pop-Location }
    } else {
      Write-Warn 'Dependencies skipped (no command configured)'
    }
  }

  $port = 3000
  if ($name -match '^[0-9]+$') {
    $candidate = [int]$name
    if ($candidate -lt 1024) {
      Write-Warn ("{0} is a reserved port (1-1023); the dev command will not use it." -f $candidate)
      Write-Info 'Using default port 3000 for the dev command.'
    } elseif ($candidate -gt 65535) {
      Write-Warn ("{0} is outside the valid port range (65535); falling back to default port." -f $candidate)
      Write-Info 'Using default port 3000 for the dev command.'
    } else {
      $port = $candidate
    }
  }

  if (Parse-Bool $cfg['add.serve-dev.enabled']) {
    $serveCmd = $cfg['add.serve-dev.command']
    if ($serveCmd) {
      Write-Info (if ($port) { "Starting dev command (port $port)" } else { 'Starting dev command' })
      $env:PORT = "$port"
      $pid = Start-BackgroundCommand -command $serveCmd -cwd $worktreePath -logDir $cfg['add.serve-dev.logging-path']
      Write-Info "Dev command PID: $pid"
    } else {
      Write-Warn 'Dev command skipped (no command configured)'
    }
  }

  Write-Info "Worktree ready: $worktreePath"
  Write-Output $worktreePath
}

function Cmd-Rm {
  param([string]$name, [switch]$yes)
  $cfg = Load-Config
  $repoPath = $cfg['repo.path']
  if (-not $repoPath) { throw 'wtx is not configured; run "wtx init" inside your repository first' }
  if (-not (Test-Path $repoPath)) { throw "project directory not found: $repoPath" }
  Require-Git

  $worktreePath = $null
  if ($name) {
    if (-not (Validate-WorktreeName $name)) { throw "invalid worktree name: $name" }
    $worktreePath = Compute-WorktreePath $repoPath $name
  } else {
    $cur = Repo-Root .
    if (-not $cur) { throw 'not inside a worktree; provide a name' }
    if ($cur -eq $repoPath) { throw 'current directory is the main repo; provide a name' }
    $worktreePath = $cur
    $repoDir = Split-Path -Leaf $repoPath
    $parent = Split-Path -Parent $repoPath
    $prefix = Join-Path $parent ($repoDir + '.')
    if ($worktreePath.StartsWith($prefix)) { $name = $worktreePath.Substring($prefix.Length) }
  }

  if (-not (Test-Path $worktreePath)) { throw "worktree not found: $worktreePath" }
  $branchPrefix = $cfg['add.branch-prefix']; if (-not $branchPrefix) { $branchPrefix = 'feat/' }
  $branchName = if ($name) { "$branchPrefix$name" } else { '' }

  if (-not $yes) {
    $resp = Read-Host ("Remove worktree {0}? [Y/n]" -f $worktreePath)
    if ($resp -and $resp.Trim().ToLowerInvariant().StartsWith('n')) { Write-Info 'Aborted'; return }
  }

  Write-Info "Removing worktree: $worktreePath"
  # If we're currently inside the worktree being removed, change to main repo
  $pushedFromWorktree = $false
  try {
    $curRoot = Repo-Root .
    if ($curRoot) {
      $curRootN = ([IO.Path]::GetFullPath($curRoot) -replace '\\','/').TrimEnd('/')
      $worktreeN = ([IO.Path]::GetFullPath($worktreePath) -replace '\\','/').TrimEnd('/')
      if ($curRootN -eq $worktreeN) { Push-Location $repoPath; $pushedFromWorktree = $true }
    }
  } catch { }

  $removed = $false
  try {
    # Try Git removal first; if it prompts or fails, we'll fall back
    $p = Start-Process -FilePath 'git' -ArgumentList @('-C', $repoPath, 'worktree','remove','--force', $worktreePath) -NoNewWindow -Wait -PassThru -RedirectStandardOutput ([IO.Path]::GetTempFileName()) -RedirectStandardError ([IO.Path]::GetTempFileName())
    if ($p.ExitCode -eq 0 -and -not (Test-Path $worktreePath)) { $removed = $true }
  } catch { }

  if (-not $removed) {
    # Fallback: clear attributes and remove directory manually, then prune metadata
    if (Test-Path $worktreePath) {
      try { Get-ChildItem -LiteralPath $worktreePath -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Attributes = 'Normal' } catch { } } } catch { }
      try { Remove-Item -LiteralPath $worktreePath -Recurse -Force -ErrorAction SilentlyContinue } catch { }
      if (Test-Path $worktreePath) {
        # Normalize path separators for cmd.exe rmdir
        $winPath = $worktreePath -replace '/', "\" 
        try { cmd /c "rmdir /s /q \"$winPath\"" | Out-Null } catch { }
      }
      try { & git -C $repoPath worktree prune -v | Out-Null } catch { }
    }
  }

  if ($pushedFromWorktree) { try { Pop-Location } catch { } }
  if ($branchName) {
    $exists = (& git -C $repoPath branch --list $branchName).Trim()
    if ($exists) {
      & git -C $repoPath branch -D $branchName | Out-Null
      Write-Info "Deleted branch $branchName"
    }
  }
  if (-not (Test-Path $worktreePath)) { Write-Info "Removed worktree $worktreePath" } else { Write-Warn "Worktree still present: $worktreePath" }
}

function Cmd-Clean {
  $cfg = Load-Config
  $repoPath = $cfg['repo.path']
  if (-not $repoPath) { throw 'wtx is not configured; run "wtx init" inside your repository first' }
  if (-not (Test-Path $repoPath)) { throw "project directory not found: $repoPath" }
  Require-Git

  # Remove numerically named worktrees only
  $items = Get-Worktrees $repoPath | Where-Object { $_.Name -and ($_.Name -match '^[0-9]+$') }
  $count = 0
  foreach ($it in $items) {
    try { Cmd-Rm -name $it.Name -yes; $count += 1 } catch { Write-Warn $_ }
  }
  Write-Info "Cleaned $count worktree(s)"
}

function Cmd-ShellHookPwsh {
  param([string]$Name = 'wtx')
  $thisScript = if ($Script:WTX_ScriptPath) { $Script:WTX_ScriptPath } else { $MyInvocation.PSCommandPath }
  $escaped = $thisScript.Replace("'","''")
  $snippet = @"
# wtx shell integration: auto-cd after wtx add/path/main/remove/clean (PowerShell)
function $Name {
  param(
    [Parameter(ValueFromRemainingArguments = 
      `$true)]
    [string[]] `$Args
  )
  if (-not `$Args -or `$Args.Count -eq 0) { & pwsh -NoLogo -NoProfile -File '$escaped' help; return }
  if (`$Args[0] -in @('help','list','config','shell-hook','init','self-install')) { & pwsh -NoLogo -NoProfile -File '$escaped' @Args; return }
  if (`$Args[0] -eq 'main') { 
    `$p = (& pwsh -NoLogo -NoProfile -File '$escaped' main | Select-Object -Last 1)
    if (`$LASTEXITCODE -eq 0 -and `$p) { Set-Location `$p }
    return
  }
  if (`$Args[0] -eq 'add' -and `$Args.Count -ge 2) {
    `$p = (& pwsh -NoLogo -NoProfile -File '$escaped' add `$Args[1] | Select-Object -Last 1)
    if (`$LASTEXITCODE -eq 0 -and `$p) { Set-Location `$p }
    return
  }
  if (`$Args[0] -eq 'path' -and `$Args.Count -ge 2) {
    `$p = (& pwsh -NoLogo -NoProfile -File '$escaped' path `$Args[1] | Select-Object -Last 1)
    if (`$LASTEXITCODE -eq 0 -and `$p) { Set-Location `$p }
    return
  }
  if (`$Args[0] -eq 'rm') {
    `$prevRoot = (git rev-parse --show-toplevel 2>`$null)
    # Resolve main repo path before making changes (worktree may disappear)
    `$prevMain = (& pwsh -NoLogo -NoProfile -File '$escaped' main | Select-Object -Last 1)
    `$nameArg = `$null
    if (`$Args.Count -ge 2) { foreach (`$a in `$Args[1..(`$Args.Count-1)]) { if (`$a -notlike '--*' -and -not `$nameArg) { `$nameArg = `$a } } }
    `$targetPath = `$null
    if (`$nameArg) { `$targetPath = (& pwsh -NoLogo -NoProfile -File '$escaped' path `$nameArg | Select-Object -Last 1) }
    & pwsh -NoLogo -NoProfile -File '$escaped' @Args | Out-Host
    `$shouldCdMain = `$false
    if (-not `$nameArg) { `$shouldCdMain = `$true }
    elseif (`$targetPath -and `$prevRoot -and (`$prevRoot -eq `$targetPath)) { `$shouldCdMain = `$true }
    elseif (`$prevRoot -and -not (Test-Path `$prevRoot)) { `$shouldCdMain = `$true }
    if (`$shouldCdMain) { if (`$prevMain) { Set-Location `$prevMain } }
    return
  }
  if (`$Args[0] -eq 'clean') {
    `$prevRoot = (git rev-parse --show-toplevel 2>`$null)
    # Resolve main repo path before cleaning, in case current dir is removed during operation
    `$prevMain = (& pwsh -NoLogo -NoProfile -File '$escaped' main | Select-Object -Last 1)
    # If current is a numeric worktree, preemptively move to main so removal isn't blocked by the shell's CWD lock
    if (`$prevRoot -and `$prevMain) {
      try {
        `$leaf = [IO.Path]::GetFileName(`$prevRoot)
        if (`$leaf -and (`$leaf -match '\.[0-9]+$')) { Set-Location `$prevMain }
      } catch { }
    }
    & pwsh -NoLogo -NoProfile -File '$escaped' @Args | Out-Host
    if (`$prevRoot -and -not (Test-Path `$prevRoot)) {
      if (`$prevMain) { Set-Location `$prevMain }
    }
    return
  }
  if (`$Args.Count -eq 1) {
    `$p = (& pwsh -NoLogo -NoProfile -File '$escaped' path `$Args[0] | Select-Object -Last 1)
    if (`$LASTEXITCODE -eq 0 -and `$p) { Set-Location `$p }
    return
  }
  & pwsh -NoLogo -NoProfile -File '$escaped' @Args | Out-Host
}
# wtx shell integration: end
"@
  Write-Output $snippet
}

function Cmd-Config {
  param([string[]]$argv)
  if (-not $argv -or $argv.Count -lt 1) { throw 'config requires an action' }
  $action = $argv[0]
  $rest = @()
  for ($i=1; $i -lt $argv.Count; $i++) { $rest += $argv[$i] }
  $cfg = Load-Config
  switch ($action) {
    'list' { foreach ($k in ($cfg.Keys | Sort-Object)) { Write-Host "$k=$($cfg[$k])" } }
    'get'  { if ($rest.Count -lt 1) { throw 'config get requires a key' }; $key=$rest[0]; if (-not $cfg.Contains($key)) { throw "config key not found: $key" }; Write-Host $cfg[$key] }
    'set'  { if ($rest.Count -lt 2) { throw 'config set requires <key> <value>' }; Config-Set -key $rest[0] -value $rest[1] }
    'unset'{ if ($rest.Count -lt 1) { throw 'config unset requires a key' }; Config-Unset -key $rest[0] }
    default { throw "unknown config action: $action" }
  }
}

function Main {
  param([string[]]$argv)
  if (-not $argv -or $argv.Count -eq 0) { Cmd-Help; return }
  switch ($argv[0]) {
    'help' { Cmd-Help }
    'init' { if ($argv.Count -gt 1) { Cmd-Init -argv $argv[1..($argv.Count-1)] } else { Cmd-Init -argv @() } }
    'list' { Cmd-List }
    'main' { Cmd-Main }
    'path' { Cmd-Path -name $argv[1] }
    'add'  { Cmd-Add -name $argv[1] }
    'rm'   {
              $yes = $false; $nm = $null
              if ($argv.Count -ge 2) { foreach ($a in $argv[1..($argv.Count-1)]) { if ($a -eq '--yes') { $yes = $true } elseif (-not $nm) { $nm = $a } } }
              Cmd-Rm -name $nm -yes:$yes
           }
    'clean' { Cmd-Clean }
    'self-install' {
                     $prefix = $null
                     if ($argv.Count -ge 3 -and $argv[1] -eq '-Prefix') { $prefix = $argv[2] }
                     $installer = Join-Path $PSScriptRoot 'install.ps1'
                     if (-not (Test-Path $installer)) { throw "installer not found: $installer" }
                     if ($prefix) { & pwsh -NoLogo -NoProfile -File $installer -Prefix $prefix } else { & pwsh -NoLogo -NoProfile -File $installer }
                   }
    'config' {
                if ($argv.Count -lt 2) { throw 'config requires an action' }
                Cmd-Config -argv $argv[1..($argv.Count-1)]
             }
    'shell-hook' {
                   if ($argv.Count -lt 2 -or $argv[1] -ne 'pwsh') { throw 'shell-hook requires "pwsh"' }
                   $name = $null
                   if ($argv.Count -ge 4 -and $argv[2] -eq '-Name') { $name = $argv[3] }
                   if (-not $name) { $name = 'wtx' }
                   Cmd-ShellHookPwsh -Name $name
                 }
    default { Cmd-Help }
  }
}

try { Main -argv $args } catch { Write-Err $_; exit 1 }
