# antiX VM Laptop

This repository is currently in the planning/setup phase. Its immediate purpose is to hold project memory, workflow notes, and the approved local Betterbird mail migration utilities in a form that is easy for humans and AI coding sessions to resume.

No broader application type, framework, package manager, or deployment target has been chosen yet. The approved implementation work is limited to Python 3 standard-library mail migration utilities plus small user-level antiX setup helpers.

## Current Status

- Git repository initialized.
- Project memory documents live in `docs/`.
- `AGENTS.md` defines rules for future Codex sessions.
- Approved mail migration utilities live in `src/`.
- Offline DIY guides now cover Betterbird profile transport and the validated Evolution Flatpak setup on antiX.
- An IceWM launcher helper is available for Evolution Flatpak menu/taskbar integration.
- Windows 11 and Debian Linux portability is a project requirement.

## Start Here

Before doing project work, read these files:

1. `AGENTS.md`
2. `docs/PROJECT_STATE.md`
3. `docs/TODO.md`
4. `docs/DECISIONS.md`
5. `docs/WORKFLOW.md`

## Repository Layout

```text
.
├── AGENTS.md
├── README.md
├── docs/
│   ├── CHANGELOG.md
│   ├── DECISIONS.md
│   ├── EVOLUTION_FLATPAK_ANTIX_GUIDE.html
│   ├── EVOLUTION_FLATPAK_ANTIX_GUIDE.txt
│   ├── IDEAS.md
│   ├── PROJECT_STATE.md
│   ├── TODO.md
│   └── WORKFLOW.md
├── scripts/
│   └── evolution_flatpak_icewm_launcher_setup.sh
├── src/
└── tests/
```

`src/` currently contains the approved Betterbird profile transport and maildir-lite conversion utilities. `scripts/` contains user-level antiX setup helpers. Broader application work should remain undecided until the project type is explicitly chosen.

## Development Policy

- Do not install runtimes, packages, containers, or dependencies without explicit owner approval.
- Do not delete files without explicit owner approval.
- Do not push to a remote without explicit owner approval.
- Keep changes small and commit-ready.
- Update project memory when the repository state changes.
