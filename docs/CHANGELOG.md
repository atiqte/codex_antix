# Changelog

This file records meaningful repository changes. Keep entries concise and newest first.

## 2026-07-12

- Added capability-gated individual attachment downloads, selected-duplicate Save All ZIP, signed inline-image delivery, bounded private temp files, concurrency/time/size limits, and expanded read-only health/status reporting to the Go notmuch browser source.
- Added structured email HTML sanitization with pinned `golang.org/x/net/html v0.57.0`, Go 1.25 module floor, blocked/embedded/remote iframe CSP modes, CID rewriting, sandboxed SVG handling, and image permission reset on reload/message/duplicate changes.
- Rebuilt the embedded frontend as an adaptive Frost/Sapphire chi/HTMX workspace with local Lucide icons, dense result/reading panes, keyboard/pointer splitter, responsive mobile reading flow, attachment controls, and compiled Tailwind CSS without runtime Node/npm/CDN dependencies.
- Added focused capability, MIME, HTML, download, ZIP, limit, timeout, and cleanup tests. Local Go 1.26.4 test/vet/build and desktop/mobile browser QA passed; antiX production rollout and final HTML/TXT guide regeneration remain pending staged operator validation.
- Installed Dunst 1.12.2 for IceWM desktop notifications, placed one marked startup block before the provider-live archive monitor, and validated a visible critical popup without changing mail or configs; reboot persistence remains to be checked.

## 2026-07-11

- Added the provider-live archive transaction engine with immutable UID/hash manifests, monthly Maildir++ copies, hard-link snapshots, verified split external backups, two approvals, cleanup canary, rollback, and 30-day snapshot retirement.
- Added the POSIX 15,000-message threshold monitor/controller, exact production mbsync policy audit, notmuch scope guard, bounded monitor logs, persistent daily alerts, IceWM startup integration, and no-clone offline payload installer/bundler.
- Added 19 focused provider-live archive tests plus chronological HTML/TXT rollout guides; antiX runtime validation is explicitly pending and starts with read-only discovery.
- Hardened external-backup validation after antiX discovery showed `/media/atiq` was backed by `/`; USB/HGFS targets must now have a real non-root mount ancestor.
- Installed and validated the provider-live archive tools and canonical empty archive layout on antiX without changing mbsync/notmuch configs or starting the archive monitor.
- Added and source-verified the separate `TAG-Mustang Local Archive` Evolution Maildir account without changing the existing live Sent destination or adding SMTP.
- Enrolled the empty provider-live archive in the controlled notmuch scope; verified the pilot remained at 650 messages/1,176 files, provider-live and the approved small delta remained indexed, the full 59G Betterbird archive remained excluded, and index/browser services restarted cleanly.
- Installed and validated the 900-second provider-live archive threshold monitor and single marked IceWM startup block; alert/transaction state stayed clear, mail/config hashes were unchanged, and all related services remained healthy.
- Confirmed after an antiX reboot that IceWM automatically restarted the provider-live archive monitor, which completed a fresh below-threshold check with mbsync/notmuch loops healthy and all relevant locks absent.
- Added persistent runtime-adjustable provider-live polling intervals to the generated loop/control scripts, including `interval`, `set-interval`, `reset-interval`, status visibility, atomic mode-600 storage, and a conservative 60-second to 24-hour range.
- Validated the dynamic interval rollout on antiX: unsafe `30s` rejection, persistent `2m` startup, live `2m -> 1m -> 2m -> 3m` changes without restarting, successful manual/automatic group syncs, final running/unpaused/lock-free state, and empty Maildir `tmp`.
- Updated the mbsync HTML/TXT guides with interval commands and clarified that the interval is measured after each completed sync, so slow syncs remain sequential and never overlap.
- Recorded the missing-mail diagnosis: the provider-live loop, TLS connection, state, disk, and repeated sync exits were healthy; another POP client had been removing server copies before IMAP/mbsync could see them.

## 2026-07-09

- Validated the installed chi/Tailwind notmuch browser on antiX and through the Windows SSH tunnel: Go tests passed on antiX, the compiled CSS/search/message/status views worked, read-only hashes stayed unchanged, the index loop stayed healthy, and the owner confirmed the UI locally and from Windows.
- Migrated the read-only Go notmuch browser source from stdlib `ServeMux` to chi routing while preserving localhost-only access, read-only notmuch behavior, control scripts, and the index-refresh loop.
- Split the browser UI into modular embedded HTML templates and added compiled local Tailwind CSS with a checked-in Tailwind source stylesheet; antiX runtime still serves only local embedded assets.
- Expanded the Go browser HTML/TXT rebuild guides with the chi/Tailwind source-bundle workflow, `go.sum`, modular template/static/style checks, and the no-full-repo antiX transfer path.

## 2026-07-06

- Added the first broader application implementation: a read-only Go standard-library notmuch browser service with embedded local CSS/HTMX, notmuch JSON parsing, localhost-only bind safety, focused unit tests, and an antiX control script source.
- Added `docs/NOTMUCH_GO_BROWSER_SERVICE_GUIDE.txt` and updated project memory to record Go stdlib, SSH tunnel access, Evolution reply/send split, and deferred 59G archive expansion.
- Fixed the active notmuch browser HTML guide so command chunks are embedded directly in visible `<pre>` blocks instead of depending on JavaScript to populate initially blank blocks.

## 2026-07-05

- Retired Astroid from the antiX notmuch workflow: settings were backed up, the package and Astroid-only dependencies were purged, Astroid-only compatibility symlinks were removed, and the browser viewer was converted to validated single-email mode.
- Added `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.html` and `.txt` as the active browser-only notmuch DIY guides, and marked the older Astroid guide as retired historical context.
- Expanded the notmuch/Astroid HTML and text guides with full Chunk 8B helper creation, Chunk 8B-FIX1 corrected helper/tag validation, and Chunk 8C pilot-safe reindex validation.
- Expanded the notmuch/Astroid HTML and text guides with the full Chunk 8A browser-viewer bootstrap that writes `~/.local/bin/notmuch-browser-pilot`, plus separate daily start and stop commands.
- Added `docs/NOTMUCH_ASTROID_ANTIX_GUIDE.html` and `.txt`, documenting the validated notmuch pilot, read-only browser viewer, Astroid limitations, tag backup/restore, pilot-safe reindexing, and deferred full-archive expansion.
- Recorded successful pilot-safe notmuch reindex validation: old DB moved to backup, database rebuilt only under `/mail/SearchIndex/notmuch/default`, tags restored, 444 messages and 846 files preserved, Maildir files unchanged, `tmp` empty, mbsync resumed, and browser viewer relaunched.
- Recorded successful corrected notmuch helper validation: shell/Python syntax checks passed, tag backup/restore worked, exact Message-ID search still worked, indexed file paths stayed unchanged, and pilot Maildir `tmp` folders stayed empty.
- Recorded the notmuch/Astroid pilot outcome: notmuch indexed 444 unique messages and 846 files safely, Evolution raw-file handoff was rejected, Astroid list/search worked but body rendering stayed blank, and the read-only localhost browser viewer was validated for search, thread opening, body rendering, and exact Message-ID search.
- Updated project memory, TODO, decisions, and validation ledger to treat the browser viewer as the primary notmuch GUI path, keep Astroid experimental on this VM, and require corrected backup/restore/reindex helper validation before final guide generation or full-archive expansion.
- Recorded owner-reported Fedora Evolution GUI validation of dynamic aggregate `20260704-205827`: Inbox 242, Sent 5, November2025 2, Trash 0, message open/HTML/attachments OK, and no error popup.

## 2026-07-04

- Recorded successful Fedora Batch 7A visibility validation for dynamic aggregate `20260704-205827`: host and Evolution Flatpak sandbox both see 249 `cur`, 0 `new`, 0 `tmp`, with expected folder counts.
- Recorded owner confirmation that the old delta's missing Trash message is expected because it was manually deleted from Betterbird before the new dynamic aggregate run; the next gate is Fedora Evolution validation, not old-delta hash equality.
- Recorded the successful Fedora dynamic aggregate run `20260704-205827`: 249 post-main-archive messages selected, staged, converted, SHA256-verified, packed, and archive-verified.
- Added `src/betterbird_post_archive_delta.py`, a dynamic post-main-archive Betterbird delta helper that selects all current source messages absent from the main 48,720-message archive baseline instead of using a fixed 248-message count.
- Reworked the Betterbird delta Maildir++ HTML and text guides into a RUN_ID-based "Post-Main-Archive Aggregate Delta" workflow with separate copy buttons per batch and dynamic success checks.
- Split the Betterbird delta Maildir++ HTML guide `Start Here` section so Batch 1 through Batch 5 each have their own copy button that copies only that batch's shell commands.
- Fixed the Betterbird delta Maildir++ HTML guide code-block CSS so command text is visible in Brave/Chromium instead of inheriting the pale inline-code background.
- Revised the Betterbird delta Maildir++ HTML and text guides so the operator workflow starts at `Batch 1: Fedora VM Terminal` with read-only source/target audit, then covers mail-process shutdown, delta staging, converter dry-run, copy/hash verification, and the validated transfer phases.
- Added `docs/BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.html` and `.txt`, complete DIY guides for the validated 248-message Betterbird delta Maildir++ transfer from Fedora to antiX Evolution.
- Recorded the validated Betterbird delta workflow: Fedora conversion and Evolution validation, Fedora pack/verify, HGFS host-share verification, Google Drive ZIP transfer to antiX, antiX staging/restore/verify/inspect, Flatpak visibility, and final antiX Evolution GUI validation.
- Updated the converted Maildir++ archive HTML and text guides to replace fragmented antiX restore examples with the validated all-in-one restore, verify-tree, and inspect chunk using `~/codex-runs/maildirpp_transport.py`.

## 2026-07-03

- Added a host-share mount identity guard to the Maildir++ archive transfer guide so `/mnt/hgfs/Win11Host_Shared4VM` must resolve to an HGFS/FUSE VMware shared-folder mount before any Win11 host-share copy.
- Hardened the Maildir++ archive transfer preflight with write-probe checks after the Fedora VMware host-share copy failed on `/mnt/hgfs/Win11Host_Shared4VM` due to `Permission denied`.

## 2026-07-02

- Expanded the converted Maildir++ archive HTML and text guides with a 50 GB USB suitability preflight and a Fedora-to-Win11 VMware shared-folder copy path at `/mnt/hgfs/Win11Host_Shared4VM`.

## 2026-07-01

- Expanded the converted Maildir++ archive HTML and text guides with a 64 GB USB/thumb-drive transfer workflow from the verified Fedora export to `/mail/import-staging/maildirpp-archive-export-20260701-215204`, including Fedora USB verification and antiX staging verification commands.
- Added `src/maildirpp_transport.py`, a standard-library transport utility for already-converted canonical Maildir++ archives with Maildir++ preflight, split archive verification, restore, and restored-tree validation.
- Added standard-library unit tests for converted Maildir++ archive inspection, split archive round-trip, corruption detection, unsafe extraction, hash mismatch, and non-empty destination refusal.
- Added `docs/MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.html` and `.txt`, complete DIY guides for moving `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp` to `/mail/Mailstore/evolution/local-maildir`.
- Recorded the owner-reported Fedora Evolution GUI validation of the converted archive: `mail_tagindustries_com_sg.Inbox` opens with 14,279 emails, HTML renders, and no error popup is shown.

## 2026-06-28

- Added `docs/WORK_VALIDATION_LEDGER.md` as a topic-neutral ledger for future command chunks and pasted-output validation, wired it into required reading/workflow docs, and backfilled confirmed historical milestones without raw secrets or massive logs.
- Clarified the mbsync HTML and text guides with a `Start Here: Fresh Setup` sequence, exact command order for INBOX validation, production promotion, Evolution checks, and auto-sync validation, plus reference-only labels for the production config block.

## 2026-06-27

- Hardened provider-live generated controls against stale loop PID files: `status` reports stale loop pids, `stop-loop` avoids signaling unrelated processes, and timeout handling now falls back cleanly when only a non-GNU `timeout` is available.
- Added provider-live auto-sync timeout and lock-age hardening: generated scripts default to a 3600-second `mbsync` timeout, show active sync age/pid/channel in `status`, expose `clear-stale-lock`, and include an `autosync-stale-lock-proof` helper command.
- Hardened the mbsync helper and guides so the verified provider-live auto-sync workflow can be reproduced with `autosync-preflight`, `refresh-autosync`, `autosync-validate`, and `autosync-log-rotation-proof`, including the uppercase IceWM marker.
- Added provider-live mbsync log retention to the helper-generated auto-sync scripts: daily auto logs are compressed/deleted by age, manual logs are retained longer, and `mbsync-provider-live-control` now includes `logs` and `cleanup-logs`.
- Updated `scripts/mbsync_provider_inbox_setup.sh` so it remains backward-compatible with the first INBOX test and now also supports production `provider-live` layout/config/status, Sent-only upload, provider-live group sync, auto-sync loop generation, and IceWM startup installation.
- Updated `docs/MBSYNC_ANTIX_GUIDE.html` and `.txt` so the DIY guide reflects the validated production `provider-live` setup, marks the old second-folder path as historical for this mailbox, and documents narrow Sent upload plus auto-sync controls.
- Recorded validated Sent upload for production mbsync: Evolution saves sent copies to `TAG-Mustang_mbsync-Live/Sent`, `provider-live-sent-upload` maps only `Sent <=> Sent` with `Sync PullNew PushNew`, and the 180-second loop now syncs `provider-live-group`.
- Recorded the validated production mbsync `provider-live` setup on antiX: seven exact IMAP folders, deletion-safe `Sync PullNew`, Evolution `BackendName=maildir`, SMTP send test, Gmail replies pulled back, and a 180-second IceWM-started auto-sync loop with pause/resume controls.
- Marked the earlier second-folder-before-live decision as superseded after empty `FARSUK` and `BASUNDHARA` folders were removed and the seven-folder `provider-live` tree passed production validation.
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
