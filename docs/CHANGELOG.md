# Changelog

This file records meaningful repository changes. Keep entries concise and newest first.

## 2026-06-27

- Recorded the successful antiX mbsync INBOX validation: `isync 1.5.1`, 144 messages pulled, Evolution Flatpak reads the test tree as `BackendName=maildir`, and post-Evolution mbsync succeeds without duplicate flood or unexpected deletions.
- Updated the mbsync guide with the next controlled promotion path: snapshot config/logs, inventory remote folders read-only, test exactly one second folder, then create a separate live tree only after validation.
- Marked the first mbsync INBOX setup tasks complete and added active tasks for the second-folder mbsync test.

## 2026-06-26

- Added `docs/MBSYNC_ANTIX_GUIDE.html` and `.txt`, complete DIY guides for the first deletion-safe mbsync INBOX test on antiX.
- Added `scripts/mbsync_provider_inbox_setup.sh`, an antiX helper for mbsync inspection, APT install, isolated `/mail` layout creation, pull-only config generation, dry-run, sync-once, and status checks.
- Recorded the accepted first mbsync path: APT `isync`/`mbsync`, INBOX-only pull into `/mail/Mailstore/mbsync/provider-inbox-test`, and notmuch/Astroid deferred as a later sidecar search layer.
- Added `.gitattributes` to keep shell and Python scripts LF-only across Windows and antiX checkouts.
- Updated the Evolution IceWM launcher helper and guides to use `~/.icewm/personal` for the Personal menu and the official Flatpak-exported `org.gnome.Evolution.svg` icon after VM validation.
- Added `scripts/evolution_flatpak_icewm_launcher_setup.sh`, a user-level antiX helper for Evolution Flatpak IceWM menu/taskbar integration with keyring startup fallback.
- Updated the Evolution Flatpak HTML and text guides with an IceWM launcher phase, validation commands, transfer notes, and troubleshooting for menu/toolbar/keyring issues.
- Added `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.html` and `.txt`, complete DIY guides for installing and validating Evolution Flatpak 3.60.2 on antiX runit/IceWM with app data symlinked to `/mail`.
- Recorded the accepted Evolution Flatpak path as the preferred first GUI mail-client setup for the constrained antiX VM, with source-build kept as fallback.
- Added `codex-input/` to `.gitignore` so local pasted terminal logs are not committed.

## 2026-06-25

- Added `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html` and `.txt`, complete DIY guides for Fedora packing, transfer, antiX verification/restoration, and post-restore Maildir++ conversion.
- Added `src/betterbird_profile_transport.py`, a standard-library utility for packing, splitting, verifying, unpacking, and verifying a whole Betterbird profile tree.
- Added standard-library unit tests for profile transport part splitting, corruption detection, safe extraction, round-trip restore, lock-marker refusal, and non-empty destination refusal.
- Recorded the whole-profile transport workflow and defaults: gzip level 6, 1900 MiB parts, and antiX staging at `/mail/import-staging/betterbird-maildir`.

## 2026-06-24

- Added `src/betterbird_maildirlite_to_maildirpp.py`, a dry-run-first Betterbird maildir-lite to canonical Maildir++ converter.
- Added standard-library unit tests for converter folder mapping and portable validation.
- Recorded the Python standard-library mail migration utility as the first approved implementation artifact.

## 2026-06-23

- Recorded approved end-of-session commit and push workflow.
- Created project memory and workflow documentation.
- Added future Codex session instructions.
- Documented language-neutral setup posture.
- Expanded `.gitignore` for portable local development.
