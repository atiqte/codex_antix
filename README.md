# antiX VM Laptop

This repository holds project memory, workflow notes, the approved local Betterbird mail migration utilities, antiX mail setup helpers, and the first broader application objective: a read-only Go notmuch browser service for antiX.

The broader application direction is now selected for v1: a lightweight Go standard-library web service that searches/views notmuch mail over localhost, with Windows 11 access through an SSH tunnel. Evolution remains the reply/forward/send client.

## Current Status

- Git repository initialized.
- Project memory documents live in `docs/`.
- `AGENTS.md` defines rules for future Codex sessions.
- `docs/WORK_VALIDATION_LEDGER.md` records topic-neutral command-chunk validation outcomes for future terminal-guided work.
- Approved mail migration utilities live in `src/`.
- The Go notmuch browser service lives under `cmd/notmuch-browser` and `internal/notmuchbrowser`.
- Offline DIY guides now cover Betterbird profile transport, converted Maildir++ archive transport with USB and Win11 host-share transfer, the dynamic post-main-archive Betterbird aggregate delta workflow to antiX Evolution, the validated Evolution Flatpak setup on antiX, the first deletion-safe mbsync INBOX test, the validated production `provider-live` setup including narrow Sent upload plus hardened auto-sync controls, and the browser-only notmuch search/view workflow.
- AntiX helper scripts are available for Evolution Flatpak Personal menu/taskbar integration, the first mbsync INBOX test setup, the validated production `provider-live`/Sent-upload workflow, and the Go notmuch browser control workflow.
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
│   ├── NOTMUCH_GO_BROWSER_SERVICE_GUIDE.txt
│   ├── TODO.md
│   ├── WORK_VALIDATION_LEDGER.md
│   └── WORKFLOW.md
├── cmd/
│   └── notmuch-browser/
├── internal/
│   └── notmuchbrowser/
├── scripts/
│   ├── evolution_flatpak_icewm_launcher_setup.sh
│   ├── mbsync_provider_inbox_setup.sh
│   └── notmuch_browser_control.sh
├── src/
└── tests/
```

`src/` currently contains the approved Betterbird profile transport, converted Maildir++ archive transport, maildir-lite conversion, and dynamic post-main-archive delta utilities. `cmd/notmuch-browser` and `internal/notmuchbrowser` contain the Go notmuch browser service. `scripts/` contains user-level antiX setup helpers for Evolution launch integration, the first mbsync INBOX test, the validated production `provider-live` mbsync setup with receive-only normal folders, Sent-only upload, log retention, timeout visibility, stale-lock recovery, stale loop PID protection, and the notmuch browser control script.

## Development Policy

- Do not install runtimes, packages, containers, or dependencies without explicit owner approval.
- Do not delete files without explicit owner approval.
- Do not push to a remote without explicit owner approval.
- Keep changes small and commit-ready.
- Update project memory when the repository state changes.
