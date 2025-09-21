# wtx (PowerShell 7+)

Native PowerShell CLI for managing git worktrees on Windows and cross-platform PowerShell. Independent from the Bash `wt` tool.

## Requirements
- PowerShell 7+ (`pwsh`), `git` on PATH

## Install / Uninstall
- Install: `pwsh -File install.ps1` (default `%LOCALAPPDATA%\Programs\wtx`) or `pwsh -File install.ps1 -Prefix C:\Tools\wtx`
- Self-install: `pwsh -File wtx.ps1 self-install [-Prefix C:\Tools\wtx]`
- Reload profile: `. $PROFILE`
- Uninstall: `pwsh -File uninstall.ps1` (add `-Prefix` if customized)

## Quick Start
```
wtx init                 # run inside the repo you want to manage
wtx add 3000             # creates ../<repo>.3000, branch feat/3000, optional env/deps/dev
wtx 3000                 # jump to that worktree (via shell hook)
wtx main                 # print main repo path; with shell hook, cd there
wtx rm 3000 --yes        # remove worktree and branch
wtx clean                # remove numerically named worktrees
```

## Commands
- `wtx help` — Show help
- `wtx init [--local|--global]` — Capture `repo.path` and default branch; writes to local by default (`.wtx.kv`)
- `wtx list` — List worktrees for `repo.path`
- `wtx main` — Print configured main repo path
- `wtx path <name>` — Print absolute path `../<repo>.<name>`
- `wtx add <name>` — Create worktree and branch `<prefix><name>` (default `feat/`); optionally copy `.env*`, install deps, start dev command; `PORT` inferred when `<name>` is numeric (1-1023 and >65535 fall back to `3000` with warnings)
- `wtx rm [name] [--yes]` — Remove current or named worktree and its branch; confirm unless `--yes`. Removing the current worktree cds back to `wtx main` (via shell hook).
- `wtx clean` — Remove numerically named worktrees; if it removes the current one, cds to `wtx main` (via shell hook).
- `wtx config list|get|set|unset [--local|--global] ...` — Manage config. list/get shows merged view; set/unset writes to chosen scope (default: local).
- `wtx shell-hook pwsh [-Name wtx]` — Output auto-cd wrapper (installer appends it automatically)
- `wtx self-install [-Prefix <dir>]` — Copy `wtx.ps1` to install location and add the shell hook to your profile

## Configuration
- Global file: `%APPDATA%\wtx\config.kv` (override with env `WTX_CONFIG_FILE`)
- Local (per-repo): `<repo>\.wtx.kv` — overrides global when operating in/for that repo
- Keys:
  - `repo.path` (set by `wtx init`), `repo.branch` (auto-detected if empty)
  - `add.branch-prefix` (default `feat/`)
  - `add.copy-env.enabled` (true/false), `add.copy-env.files` (e.g., `[".env",".env.local"]`)
  - `add.install-deps.enabled` (true/false), `add.install-deps.command` (e.g., `npm ci`, `pip install -r requirements.txt`, `cargo fetch`)
  - `add.serve-dev.enabled` (true/false), `add.serve-dev.command` (e.g., `npm run dev`, `uvicorn app:app --port $env:PORT`, `cargo watch -x run`)
  - `add.serve-dev.logging-path` (default `tmp`)

Default scope
- `wtx init` and `wtx config set/unset` default to local (`.wtx.kv`). Use `--global` to write the global file.

Cleanup old global keys (optional)
- If you previously wrote `repo.path`/`repo.branch` globally, you can remove them:
```
wtx config unset repo.path --global
wtx config unset repo.branch --global
```

## Notes
- Worktree path: `../<repo>.<name>`; branch: `<prefix><name>`
- Dev logs: `<worktree>/<logging-path>/dev.log` (default `tmp`)
- Windows Terminal `wt.exe` is unrelated; this CLI uses `wtx` to avoid conflicts
