# Changelog

This file records meaningful repository changes. Keep entries concise and newest first.

## 2026-06-26

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
