# Repository Guidelines

## Project Structure & Module Organization
- Root CLI: `wtx.ps1` — primary PowerShell entrypoint.
- Installers: `install.ps1`, `uninstall.ps1` — add/remove `wtx` and shell hook.
- Config file (generated at runtime): `<repo>\.wtx.kv` (local-only).
- No separate modules/assets yet; keep the script self‑contained and cross‑platform.

## Build, Test, and Development Commands
- Run locally: `pwsh -File .\wtx.ps1 help` (or any command).
- Install: `pwsh -File .\install.ps1 [-Prefix <dir>]`; Uninstall: `pwsh -File .\uninstall.ps1`.
- Self‑install: `pwsh -File .\wtx.ps1 self-install` then reload profile (`. $PROFILE`).
- Lint (optional): `Invoke-ScriptAnalyzer -Path .\wtx.ps1`.
- Format (optional): `Invoke-Formatter -Path .\wtx.ps1`.

## Coding Style & Naming Conventions
- PowerShell 7+, 4‑space indent, UTF‑8, Unix‑friendly where possible.
- Verb‑Noun functions using approved verbs (e.g., `Get-Config`, `Set-Config`).
- PascalCase for functions/parameters; lowerCamelCase for locals; ALL_CAPS for constants.
- Prefer built‑in cmdlets and `git` CLI; avoid external module dependencies.
- Use `Write-Verbose`/`Write-Error`; return data (not strings) from helpers where feasible.

## Testing Guidelines
- If adding tests, use Pester 5 in `tests/` with files named `*.Tests.ps1`.
- Run tests: `Invoke-Pester -Path .\tests -Output Detailed`.
- Cover: argument parsing, config read/write, and git interactions (mock external calls).

## Commit & Pull Request Guidelines
- Use Conventional Commits: `feat:`, `fix:`, `docs:`, `refactor:`, `chore:`.
- PRs include: concise summary, validation steps, linked issues; add screenshots or transcript for UX changes.
- Keep changes focused; avoid mixing refactors with features/bugfixes.

## Security & Configuration Tips
- Validate inputs; pass arguments explicitly to `git`/process calls (no string eval).
- Config is local-only (`.wtx.kv`); do not commit it. Guard file operations and path joins.

## Agent‑Specific Instructions
- Limit edits to `wtx.ps1`, `install.ps1`, `uninstall.ps1`, tests, and docs.
- Keep behavior consistent with `README.md`; update docs when CLI surface changes.
- Preserve cross‑platform behavior; avoid Windows‑only APIs unless gated with fallbacks.
