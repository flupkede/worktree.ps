# wtx (PowerShell 7+)

Native PowerShell CLI for managing git worktrees on Windows and cross-platform PowerShell. Independent from the Bash `wt` tool.

## Requirements
- PowerShell 7+ (`pwsh`), `git` on PATH

## Install / Uninstall
- Install: `pwsh -File install.ps1` (default `%LOCALAPPDATA%\Programs\wtx`) or `pwsh -File install.ps1 -Prefix C:\Tools\wtx`
- Self-install: `pwsh -File wtx.ps1 self-install [-Prefix C:\Tools\wtx]`
- Reload profile: `. $PROFILE`
- Uninstall: `pwsh -File uninstall.ps1` (add `-Prefix` if customized)

### Shell Hook (auto-cd)
- The installer appends a PowerShell wrapper function `wtx` to your profile.
- With the wrapper:
  - `wtx add <name>` changes directory into the new worktree.
  - `wtx <name>` jumps to `../<repo>.<name>`.
  - `wtx main` cds to the main repo.
  - `wtx rm [name] --yes` from inside a worktree removes it and cds back to main.
  - `wtx clean` removes numeric worktrees and cds to main if the current one is removed.
  - After install, reload your profile: `. $PROFILE`.

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
- `wtx help` – Show help
- `wtx init` – Capture `repo.path` and default branch; writes all defaults to local `.wtx.kv`
- `wtx list` – List worktrees for `repo.path`
- `wtx main` – Print configured main repo path
- `wtx path <name>` – Print absolute path `../<repo>.<name>`
- `wtx add <name>` – Create worktree and branch `<prefix><name>` (default `feat/`); optionally copy `.env*`, install deps, start dev command; `PORT` inferred when `<name>` is numeric (1-1023 and >65535 fall back to `3000` with warnings)
- `wtx rm [name] [--yes]` – Remove current or named worktree and its branch; confirm unless `--yes`. Removing the current worktree cds back to `wtx main` (via shell hook).
- `wtx clean` – Remove numerically named worktrees; if it removes the current one, cds to `wtx main` (via shell hook).
- `wtx config list|get|set|unset` – Manage local config. `list|get` shows merged view (file + defaults); `set|unset` write to `<repo>\.wtx.kv`.
- `wtx shell-hook pwsh [-Name wtx]` – Output auto-cd wrapper (installer appends it automatically)
- `wtx self-install [-Prefix <dir>]` – Copy `wtx.ps1` to install location and add the shell hook to your profile

## Configuration
- Local (per-repo): `<repo>\.wtx.kv`
- Keys:
  - `repo.path` (set by `wtx init`), `repo.branch` (auto-detected if empty)
  - `add.branch-prefix` (default `feat/`)
  - `add.copy-env.enabled` (true/false), `add.copy-env.files` (e.g., `[".env",".env.local"]`)
  - `add.install-deps.enabled` (true/false), `add.install-deps.command` (e.g., `npm ci`, `pip install -r requirements.txt`, `cargo fetch`)
  - `add.serve-dev.enabled` (true/false), `add.serve-dev.command` (e.g., `npm run dev`, `uvicorn app:app --port $env:PORT`, `cargo watch -x run`)
  - `add.serve-dev.logging-path` (default `tmp`)

`wtx init` writes all keys (including defaults) to `.wtx.kv`. `wtx config` commands read/write only the local file.

## Notes
- Worktree path: `../<repo>.<name>`; branch: `<prefix><name>`
- Dev logs: `<worktree>/<logging-path>/dev.log` (default `tmp`)
- Windows Terminal `wt.exe` is unrelated; this CLI uses `wtx` to avoid conflicts
- Numeric clean only targets names matching `^[0-9]+$`.
- On Windows, close tools holding files in a worktree (editors, terminals) before `wtx rm/clean` to avoid deletion being blocked.

## Troubleshooting
- Auto-cd not working
  - Reload your profile: `. $PROFILE`.
  - Verify wrapper exists: open `$PROFILE` and look for the "wtx shell integration" block; or run `wtx shell-hook pwsh` to preview.
  - Use the wrapper function (`wtx ...`), not `pwsh -File wtx.ps1 ...`.
- "wtx is not configured" errors
  - Run `wtx init` inside the target repo. Check values via `wtx config list`.
- `rm`/`clean` fails or leaves the folder
  - Close processes locking the worktree (editors/terminals). Then `wtx rm <name> --yes`.
  - As a fallback: `git -C <repo.path> worktree prune -v` and retry.
- Wrong default branch
  - Set explicitly: `wtx config set repo.branch main`, or re-run `wtx init`.
- Git not found
  - Ensure `git` is on PATH: `git --version` should succeed.

