# antiX VM Laptop

This repository holds project memory, workflow notes, the approved local Betterbird mail migration utilities, antiX mail setup helpers, and the first broader application objective: a read-only Go notmuch browser service for antiX.

The broader application direction is now selected for v1: a lightweight Go web service that searches/views notmuch mail over localhost, with chi routing, type-safe templ components, local HTMX 2.0.10, Bun-built Tailwind CSS 4.3.3, controlled decoded attachment downloads, and privacy-gated embedded/remote image rendering. Maildir, notmuch tags, and the notmuch database are not mutated by browser routes. Windows 11 access remains through an SSH tunnel, and Evolution remains the reply/forward/send client.

## Current Status

- Git repository initialized.
- Project memory documents live in `docs/`.
- `AGENTS.md` defines rules for future Codex sessions.
- `docs/WORK_VALIDATION_LEDGER.md` records topic-neutral command-chunk validation outcomes for future terminal-guided work.
- Approved mail migration utilities live in `src/`.
- The Go notmuch browser service lives under `cmd/notmuch-browser` and `internal/notmuchbrowser`.
- The repository pins templ 0.3.1020 through the Go tool directive and Tailwind CSS/CLI 4.3.3 through `package.json` plus `bun.lock`; Node and npm are not part of the workflow.
- `scripts/notmuch_browser_build.sh` reproduces dependencies, generated templ files, compiled CSS, tests, and a stripped binary. `scripts/notmuch_browser_runit_setup.sh` stages, activates, validates, or rolls back only the existing per-user runit service tree.
- Offline DIY guides now cover Betterbird profile transport, converted Maildir++ archive transport with USB and Win11 host-share transfer, the dynamic post-main-archive Betterbird aggregate delta workflow to antiX Evolution, the validated Evolution Flatpak setup on antiX, the deletion-safe production `provider-live` setup, the approval-gated provider-live local archive controller, the browser-only notmuch pilot workflow, and the complete Go chi/HTMX/Tailwind notmuch browser reconstruction workflow with attachment/Save All export, privacy-gated images, rollback, read-only proof, Windows tunnel, and reboot validation.
- AntiX helper scripts are available for Evolution Flatpak integration, production mbsync/Sent upload, provider-live archive monitoring and transactions, and Go notmuch browser control/index refresh.
- Windows 11 and Debian Linux portability is a project requirement.

## Start Here

Before doing project work, read these files:

1. `AGENTS.md`
2. `docs/PROJECT_STATE.md`
3. `docs/TODO.md`
4. `docs/DECISIONS.md`
5. `docs/WORK_VALIDATION_LEDGER.md`
6. `docs/WORKFLOW.md`

## Repository Layout

```text
.
├── AGENTS.md
├── .gitattributes
├── README.md
├── docs/
│   ├── CHANGELOG.md
│   ├── DECISIONS.md
│   ├── BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.html
│   ├── BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.txt
│   ├── EVOLUTION_FLATPAK_ANTIX_GUIDE.html
│   ├── EVOLUTION_FLATPAK_ANTIX_GUIDE.txt
│   ├── IDEAS.md
│   ├── MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.html
│   ├── MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.txt
│   ├── PROJECT_STATE.md
│   ├── MBSYNC_ANTIX_GUIDE.html
│   ├── MBSYNC_ANTIX_GUIDE.txt
│   ├── NOTMUCH_BROWSER_ANTIX_GUIDE.html
│   ├── NOTMUCH_BROWSER_ANTIX_GUIDE.txt
│   ├── NOTMUCH_GO_BROWSER_SERVICE_GUIDE.html
│   ├── NOTMUCH_GO_BROWSER_SERVICE_GUIDE.txt
│   ├── PROVIDER_LIVE_ARCHIVE_GUIDE.html
│   ├── PROVIDER_LIVE_ARCHIVE_GUIDE.txt
│   ├── TODO.md
│   ├── WORK_VALIDATION_LEDGER.md
│   └── WORKFLOW.md
├── cmd/
│   └── notmuch-browser/
├── package.json
├── bun.lock
├── internal/
│   └── notmuchbrowser/
├── scripts/
│   ├── notmuch_browser_build.sh
│   ├── evolution_flatpak_icewm_launcher_setup.sh
│   ├── mbsync_provider_inbox_setup.sh
│   ├── notmuch_browser_control.sh
│   ├── notmuch_browser_index_control.sh
│   ├── notmuch_browser_runit_setup.sh
│   ├── provider_live_archive_control.sh
│   └── provider_live_archive_setup.sh
├── src/
└── tests/
```

`src/` contains the Betterbird migration/transport tools plus the approval-gated provider-live archive engine. `cmd/notmuch-browser` and `internal/notmuchbrowser` contain the Go notmuch browser service. `scripts/` contains user-level antiX setup/control helpers for Evolution, mbsync, provider-live archiving, and notmuch browser/index services.

## Notmuch Browser Development

The approved build host uses Go 1.26.4 and Bun 1.3.14. Dependencies are exact and locked. The generated `*_templ.go` files and minified `internal/notmuchbrowser/static/app.css` are committed so antiX production still runs one self-contained Go binary with no JavaScript runtime.

```sh
BUN_BIN="$HOME/.bun/bin/bun" scripts/notmuch_browser_build.sh prepare
BUN_BIN="$HOME/.bun/bin/bun" scripts/notmuch_browser_build.sh generate
BUN_BIN="$HOME/.bun/bin/bun" scripts/notmuch_browser_build.sh verify-generated
BUN_BIN="$HOME/.bun/bin/bun" scripts/notmuch_browser_build.sh test
BUN_BIN="$HOME/.bun/bin/bun" scripts/notmuch_browser_build.sh build
```

The production installation and per-user runit cutover are deliberately separate operator gates. Do not run the runit helper until the staged candidate has passed the reviewed antiX validation chunks.

Reviewed antiX command gates use a project-local operator workspace. Codex prepares the ignored `codex-output/notmuch-browser-operator/current.sh`; the committed runner mirrors all output to the terminal and a private millisecond-stamped log:

```sh
cd /home/atiq/orca/workspaces/codex_antix/branch-codex
./scripts/notmuch_browser_operator_run.sh
```

The runner records the batch hash, start/end timestamps, exit code, and log SHA256. Logs stay under the ignored `codex-output/notmuch-browser-operator/logs/` directory and must be reviewed before the next batch is prepared.

## Development Policy

- Do not install runtimes, packages, containers, or dependencies without explicit owner approval.
- Do not delete files without explicit owner approval.
- Use the owner-approved end-of-session commit and push workflow from `AGENTS.md`.
- Keep changes small and commit-ready.
- Update project memory when the repository state changes.
