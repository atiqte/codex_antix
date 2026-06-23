# Agent Instructions

This repository is in planning/setup mode. Do not start building application features until the project type and first implementation objective are explicitly decided by the owner.

## Required Reading

Before making changes, future Codex sessions must read:

- `AGENTS.md`
- `README.md`
- `docs/PROJECT_STATE.md`
- `docs/TODO.md`
- `docs/DECISIONS.md`

Use these files as the project memory source of truth.

## Working Rules

- Never assume the project type, language, framework, runtime, or deployment target until it is explicitly decided.
- Keep changes small, focused, and commit-ready.
- Explain clearly before major changes, broad refactors, dependency installation, file deletion, or workflow changes.
- Update `docs/PROJECT_STATE.md` after meaningful work changes the repository state.
- Update `docs/DECISIONS.md` when an architectural, tooling, language, framework, hosting, or workflow choice is made.
- Update `docs/TODO.md` when tasks are added, completed, removed, or reprioritized.
- Do not install dependencies unless the owner explicitly approves.
- Do not delete files unless the owner explicitly approves.
- The owner has approved end-of-session commit and push. After each working session, run `git add .`, commit with a clear self-explanatory message, and run `git push`.
- Do not push outside the end-of-session workflow unless the owner explicitly approves.
- Keep Windows 11 and Debian Linux portability in mind for paths, scripts, line endings, tooling, and documentation.

## Repository Posture

- Current phase: planning/setup.
- Current goal: maintain an AI-readable memory and Git workflow system.
- Application implementation has not started.
- Project type is intentionally undecided.

## Portability Notes

- Prefer relative paths in documentation and scripts.
- Avoid OS-specific commands unless alternatives are provided for Windows PowerShell and Debian shell.
- Avoid committing generated caches, local environment files, logs, virtual environments, dependency folders, or editor state.
- Use Git as the synchronization layer between machines once a remote is connected.
