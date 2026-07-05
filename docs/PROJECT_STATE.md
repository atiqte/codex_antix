# Project State

Last updated: 2026-07-06

## Project Identity

- Repository name: `antiX_VM_Laptop`
- Project type: local mail migration utilities plus planning/setup repository
- Primary purpose today: durable project memory, safe Betterbird/Maildir++ migration utilities, validated Evolution Flatpak setup documentation for antiX, prepared antiX helper scripts for Evolution launching, validated Betterbird archive transfer paths, dynamic post-main-archive Betterbird aggregate delta handling, a validated first mbsync INBOX test path, a validated production mbsync `provider-live` path with deletion-safe receive, narrow Sent upload, log retention, and timeout/lock-age hardened auto-sync, plus a pilot notmuch search layer with a validated read-only browser viewer fallback
- Portability target: Windows 11 and Debian Linux
- Future remote target: GitHub or GitLab, not connected by this setup task

## Current Phase

Planning/setup with approved local mail migration utility implementations.

The owner approved Python standard-library utilities for transporting a full Betterbird profile tree, converting Betterbird/Thunderbird maildir-lite to canonical Maildir++, transporting the already-converted Maildir++ archive from Fedora to antiX, and selecting/staging post-main-archive Betterbird aggregate deltas, plus small antiX setup helpers for launching Evolution Flatpak and testing deletion-safe mbsync pulls. Other application direction remains undecided.

## Current Objective

Create a professional, AI-readable memory and Git workflow system that supports future Codex sessions and cross-machine work, plus maintain the approved mail migration utilities.

## What Exists Now

- Git repository on branch `main`, tracking `origin/main`.
- `README.md` with project overview and start instructions.
- `AGENTS.md` with future Codex operating rules.
- `docs/` project memory folder.
- `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html`, an offline browser DIY guide with copy buttons for the full Fedora-to-antiX transport and conversion flow.
- `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt`, a terminal-friendly plain text version of the same guide.
- `docs/MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.html`, an offline browser DIY guide with copy buttons for transferring the already-converted Fedora Maildir++ archive to antiX, including the USB transfer workflow, Win11 host-share copy path for the verified export, and the validated all-in-one antiX restore/verify/inspect chunk.
- `docs/MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.txt`, a terminal-friendly plain text version of the same converted Maildir++ archive guide, USB transfer workflow, Win11 host-share copy path, and validated all-in-one antiX restore/verify/inspect chunk.
- `docs/BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.html`, an offline browser DIY guide with separate copy buttons for the dynamic post-main-archive Betterbird aggregate delta workflow from Fedora to antiX Evolution.
- `docs/BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.txt`, a terminal-friendly plain text version of the same dynamic post-main-archive aggregate delta workflow, including audit, mail-process shutdown, staging, converter dry-run, copy/hash verification, pack/verify, transfer, antiX restore, and Evolution GUI validation.
- `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.html`, an offline browser DIY guide with copy buttons for installing and preparing Evolution Flatpak 3.60.2 on antiX runit/IceWM.
- `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.txt`, a terminal-friendly plain text version of the same Evolution Flatpak guide.
- `docs/MBSYNC_ANTIX_GUIDE.html`, an offline browser DIY guide with copy buttons for the first deletion-safe mbsync INBOX test and the validated production `provider-live` setup with narrow Sent upload on antiX.
- `docs/MBSYNC_ANTIX_GUIDE.txt`, a terminal-friendly plain text version of the same mbsync guide.
- `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.html`, an offline browser DIY guide with visible embedded command blocks and copy buttons for retiring Astroid, installing the single-email read-only notmuch browser viewer, daily start/stop, CLI search, tag backup/restore, and pilot-safe reindexing.
- `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.txt`, a terminal-friendly plain text version of the same browser-only notmuch guide.
- `docs/NOTMUCH_ASTROID_ANTIX_GUIDE.html` and `.txt`, retained only as retired historical guides with warnings pointing to the active browser-only guide.
- `docs/WORK_VALIDATION_LEDGER.md`, a topic-neutral ledger for command chunks, pasted-output review, validation outcomes, failures, fixes, and superseded steps.
- `src/` utility folder for approved Python standard-library mail migration tools.
- `.gitignore` with language-neutral local, cache, and generated-file exclusions.
- `.gitattributes` enforcing LF line endings for shell and Python scripts.
- `src/betterbird_profile_transport.py`, a Python standard-library tool to pack, split, verify, unpack, and verify a whole Betterbird profile tree for transfer.
- `src/maildirpp_transport.py`, a Python standard-library tool to inspect, pack, split, verify, unpack, and verify an already-converted canonical Maildir++ archive.
- `src/betterbird_maildirlite_to_maildirpp.py`, a dry-run-first Python converter for staged Betterbird maildir-lite profiles.
- `src/betterbird_post_archive_delta.py`, a Python standard-library helper that audits and stages all current Betterbird source messages absent from the main converted archive baseline.
- `tests/test_betterbird_profile_transport.py`, standard-library tests for split archive transport safety.
- `tests/test_maildirpp_transport.py`, standard-library tests for converted Maildir++ transport safety.
- `tests/test_betterbird_maildirlite_to_maildirpp.py`, standard-library tests for folder mapping and portable validation.
- `tests/test_betterbird_post_archive_delta.py`, standard-library tests for dynamic post-main-archive delta selection, fallback matching, and staging safety.
- `scripts/evolution_flatpak_icewm_launcher_setup.sh`, a user-level antiX helper for adding Evolution Flatpak to IceWM menu/taskbar launch surfaces and starting `gnome-keyring-daemon`.
- `scripts/mbsync_provider_inbox_setup.sh`, an antiX helper for inspecting package/layout state, installing isync/mbsync, creating the isolated `/mail` mbsync test layout, writing a pull-only INBOX config, production `provider-live` layout/config/status, Sent-only upload channel setup, and provider-live auto-sync loop/startup setup with log retention, timeout wrapping, stale-lock proofing, and stale loop PID protection.

## What Is Intentionally Undecided

- Broader application type beyond the approved mail migration utility
- Runtime or packaging beyond Python 3 standard library
- Framework
- Package manager
- Database or storage layer
- UI, CLI, service, automation, or library direction
- Deployment target
- Git hosting provider
- Branching model beyond keeping changes commit-ready

## Active Working Context

- The repository is in setup-only mode.
- Do not install Python, Node, npm packages, pip packages, Docker, devcontainers, or other dependencies without explicit approval.
- The current transport and converter utilities must remain Python 3 standard-library-only unless the owner approves a dependency change. User-level antiX setup helpers should remain POSIX shell; package-installing helper commands should remain explicit subcommands and only run after owner approval.
- Do not delete files without explicit approval.
- End each working session by committing changes with a clear self-explanatory message and pushing to the configured remote.
- Do not perform non-routine remote operations without explicit approval.
- Keep all documentation and future scripts portable across Windows 11 and Debian Linux.

## Completed Setup

- Git repository exists.
- End-of-session commit and push workflow approved.
- Initial documentation structure exists.
- Project memory files created or updated:
  - `AGENTS.md`
  - `README.md`
  - `docs/PROJECT_STATE.md`
  - `docs/DECISIONS.md`
  - `docs/TODO.md`
  - `docs/WORK_VALIDATION_LEDGER.md`
  - `docs/IDEAS.md`
  - `docs/WORKFLOW.md`
  - `docs/CHANGELOG.md`
  - `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html`
  - `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt`
  - `docs/MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.html`
  - `docs/MAILDIRPP_ARCHIVE_TRANSPORT_GUIDE.txt`
  - `docs/BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.html`
  - `docs/BETTERBIRD_DELTA_MAILDIRPP_TRANSFER_GUIDE.txt`
  - `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.html`
  - `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.txt`
  - `docs/MBSYNC_ANTIX_GUIDE.html`
  - `docs/MBSYNC_ANTIX_GUIDE.txt`
  - `docs/NOTMUCH_ASTROID_ANTIX_GUIDE.html`
  - `docs/NOTMUCH_ASTROID_ANTIX_GUIDE.txt`
  - `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.html`
  - `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.txt`
- `.gitignore`
- `.gitattributes`
- `src/betterbird_profile_transport.py`
- `src/maildirpp_transport.py`
- `src/betterbird_maildirlite_to_maildirpp.py`
- `src/betterbird_post_archive_delta.py`
- `scripts/evolution_flatpak_icewm_launcher_setup.sh`
- `scripts/mbsync_provider_inbox_setup.sh`
- `tests/test_betterbird_profile_transport.py`
- `tests/test_maildirpp_transport.py`
- `tests/test_betterbird_maildirlite_to_maildirpp.py`
- `tests/test_betterbird_post_archive_delta.py`

## Current Implementation Notes

- The transport utility is designed to run `pack` on Fedora against `~/Betterbird-Email`, write split `betterbird-profile.tar.gz.partNNNN` files with `manifest.json` and `inventory.jsonl`, then run `verify-archive`, `unpack`, and `verify-tree` on antiX.
- The transport utility defaults to whole-profile scope, Python stdlib gzip compression level 6, and 1900 MiB part files.
- The transport utility refuses active-looking Betterbird lock markers, output directories inside the source tree, non-empty restore destinations, unsafe archive paths, unsupported special files, and symlinks unless explicitly overridden.
- The DIY guide in `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html` and `.txt` is the operator-facing runbook for the safe pack, transfer, verify, unpack, verify-tree, and conversion sequence.
- In all transport commands, `--manifest` points to `manifest.json`.
- `inventory.jsonl` stays beside `manifest.json` and is read automatically by the transport script.
- The converter is designed to run on antiX after the Fedora Betterbird profile is restored to `/mail/import-staging/betterbird-maildir`.
- Default mode is `--dry-run`; `--copy` refuses unmarked or unsafe sources and writes through Maildir `tmp` before atomic rename.
- Duplicates are kept, but duplicate `Message-ID` and content hashes are logged.
- The full Betterbird maildir-lite archive was converted on Fedora into canonical Maildir++ at `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp`. Converter copy and full hash verification succeeded with 48,720 copied `cur` messages, 0 `new` messages, 0 target `tmp` files, and 0 verify errors.
- The owner reported Fedora Evolution GUI validation of the converted archive: `mail_tagindustries_com_sg.Inbox` opens with 14,279 emails, messages open, HTML renders correctly, and no error popup is shown.
- `src/maildirpp_transport.py` is the next transport path for the already-converted archive. It defaults to source `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp`, destination `/mail/Mailstore/evolution/local-maildir`, split gzip tar parts named `maildirpp-archive.tar.gz.partNNNN`, and Maildir++ layout checks before pack and after restore.
- Fedora manual transport preflight on 2026-07-01 validated the copied scripts in `~/codex-runs` by SHA256, compile, help, and import-location checks. It also stopped Evolution mail services and inspected `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp` successfully: 29 Maildir folders, 28 dot folders, 48,720 `cur`, 0 `new`, 0 `tmp`, no symlinks, no special files, and `status=ok`.
- Fedora pack on 2026-07-01 succeeded using the manually copied transport script. It wrote `/home/atiq/maildirpp-archive-export-20260701-215204` with 21 `maildirpp-archive.tar.gz.partNNNN` files, `manifest.json`, and `inventory.jsonl`; export size was 38G, archive size was 40,613,836,495 bytes, archive SHA256 was `23292983c9ffb3590197a534aeddd03590a2b8d9f913732573fa1637b71045fe`, and `pack_exit=0`.
- Fedora `verify-archive` on 2026-07-01 succeeded for `/home/atiq/maildirpp-archive-export-20260701-215204/manifest.json`: 21 parts, 40,613,836,495 archive bytes, `status=ok`, and `verify_archive_exit=0`.
- The Maildir++ archive guide now documents the transfer path for that verified export: run a Fedora preflight proving the USB and `/mnt/hgfs/Win11Host_Shared4VM` have enough real free space and actual write permission, copy the export and two transport scripts to USB, verify the archive on the USB, optionally copy and verify the same export in the Win11 host share, copy the USB package to `/mail/import-staging/maildirpp-archive-export-20260701-215204` on antiX, then run antiX-side `verify-archive` before any unpack. A 50 GB free USB drive is acceptable for the verified 38G split export if the byte-level preflight and write probes pass; it is not acceptable for the original uncompressed 59G Maildir++ tree.
- Fedora diagnostics on 2026-07-03 showed `/mnt/hgfs/Win11Host_Shared4VM` exists but was not mounted as a VMware shared folder: `findmnt -T` resolved it to Fedora `/` on `btrfs`, user `atiq` could not write, and `sudo` could write only into the Fedora filesystem. The guide now requires a host-share mount identity check before the Win11 host-share copy path is used.
- A later Fedora HGFS mount attempt on 2026-07-03 found `vmhgfs-fuse` and `vmware-hgfsclient` installed, but `vmware-hgfsclient` exited 1 with no visible shares and `sudo vmhgfs-fuse .host:/ /mnt/hgfs ...` failed with `Error -107 cannot open connection`; the host-share path still resolved to Fedora `/` on `btrfs` and user write remained denied. Use the USB transfer path unless VMware shared folders are fixed in the Fedora VM configuration and the mount identity/write probes pass.
- A subsequent Fedora check on 2026-07-03 showed the VMware share `Win11Host_Shared4VM` became visible and `/mnt/hgfs/Win11Host_Shared4VM` resolved to `fuse.vmhgfs-fuse`, but user `atiq` still could not create the write-test directory there. The Win11 host-share copy remains blocked until the user write probe succeeds; do not copy the 38G export there yet.
- A Fedora remount attempt with uid/gid ownership options on 2026-07-03 still left `/mnt/hgfs/Win11Host_Shared4VM` unusable: `mount_exit=0`, but the mounted options still showed `user_id=0,group_id=0`, `ls` returned `Permission denied`, and the user write probe failed. Continue to treat the Win11 host-share path as unsafe for the 38G copy unless a later probe shows normal-user read/write success.
- A later direct named-share remount on 2026-07-03 made the Win11 host-share path usable for the next copy attempt: `sudo /usr/bin/vmhgfs-fuse .host:/Win11Host_Shared4VM /mnt/hgfs/Win11Host_Shared4VM -o subtype=vmhgfs-fuse,allow_other` succeeded, `findmnt` reported `fuse.vmhgfs-fuse`, `ls -ld` showed `atiq atiq` ownership with `drwxrwxrwx`, `host_share_mount_ok=yes`, and normal-user `mkdir` and file-write probes both exited 0. The host-share copy path may be used only if the same mount identity and normal-user write probes still pass immediately before copying; the USB path remains independently safe.
- Fedora-to-Win11 host-share copy on 2026-07-03 succeeded for `/mnt/hgfs/Win11Host_Shared4VM/maildirpp-archive-export-20260701-215204`: scripts were copied with expected SHA256 values, `rsync` transferred 40,626,264,258 bytes, `copy_exit=0`, `host_manifest_exit=0`, `host_inventory_exit=0`, `host_part_count=21`, export size was 38G, and host-share `verify-archive` returned `status=ok` with 21 parts and 40,613,836,495 archive bytes. This is now a verified Win11 host-side backup or alternate transfer package; it has not yet been copied into antiX staging.
- antiX USB-to-staging transfer finished successfully across 2026-07-03 and 2026-07-04. The USB was mounted at `/media/atiq/New Volume`, `/mail` had 200G available, the transport scripts copied into `~/codex-runs` with expected SHA256 values, USB-side `verify-archive` returned `status=ok`, `rsync` copied 40,626,264,258 bytes into `/mail/import-staging/maildirpp-archive-export-20260701-215204`, `copy_exit=0`, `staging_manifest_exit=0`, `staging_inventory_exit=0`, `staging_part_count=21`, staging size was 38G, and antiX staging `verify-archive` returned `status=ok` with 21 parts, 40,613,836,495 archive bytes, and `staging_verify_archive_exit=0`.
- antiX restore of the converted Maildir++ archive succeeded on 2026-07-04. The staged archive was reverified before unpack with `status=ok`, then unpacked into `/mail/Mailstore/evolution/local-maildir` with `unpack_exit=0`, 115 directories, 48,721 regular files, 62,430,783,277 regular bytes, 29 Maildir folders, 48,720 `cur` files, 0 `new` files, and 0 `tmp` files. Restored-tree `verify-tree` returned `status=ok` and `verify_tree_exit=0`; final `inspect` returned 29 Maildir folders, 28 dot folders, 48,720 `cur`, 0 `new`, 0 `tmp`, 1 metadata file, 62,430,783,277 regular bytes, `status=ok`, and `inspect_exit=0`.
- A separate Betterbird post-conversion delta was selected on Fedora on 2026-07-04 by comparing the current Betterbird source against the original conversion state. The owner chose to include all 248 candidates, including 8 same-Message-ID but different-content variants, to prioritize data preservation over deduplication.
- The Fedora delta conversion target `/home/atiq/Evolution-Mailstore/betterbird-delta-maildirpp-20260704` was created as canonical Maildir++ and validated with converter SHA256 verification: 248 copied messages, 248 verified messages, 0 skipped/errors, 248 `cur`, 0 `new`, 0 `tmp`, 418M apparent target size, and folder counts Inbox 241, Sent 4, Local_Folders.November2025 2, Trash 1.
- The owner validated the Fedora delta target in Evolution Flatpak as a separate `Maildir-format mail directories` account: Inbox 241, Sent 4, November2025 2, Trash 1, messages opened, HTML rendered, attachments were visible, and no error popup appeared.
- The Fedora delta target was packed with `maildirpp_transport.py` into `/home/atiq/maildirpp-delta-export-20260704-151448`. Fedora `pack` and `verify-archive` succeeded with 1 part, export size 286M, archive bytes 299,189,312, and `status=ok`.
- The delta export was copied to the Fedora HGFS/Win11 host share at `/mnt/hgfs/Win11Host_Shared4VM/maildirpp-delta-export-20260704-151448` after the share resolved to `fuse.vmhgfs-fuse` and normal-user write probes passed. Host-share `verify-archive` succeeded with 1 part, 299,189,312 archive bytes, and `status=ok`.
- The owner then manually transferred the delta export to antiX through Google Drive as `/home/atiq/Downloads/maildirpp-delta-export-20260704-151448.zip`; antiX ZIP inspection succeeded with SHA256 `65ff42dd1897dad29c09a6cb666bd019c917d52031860dc63c729daa431d8f44`, exactly one top-level export folder, and expected `manifest.json`, `inventory.jsonl`, and `maildirpp-archive.tar.gz.part0001`.
- The antiX delta package was extracted to `/mail/import-staging/maildirpp-delta-export-20260704-151448` and verified with `verify-archive` before unpack. It was restored to `/mail/Mailstore/evolution/betterbird-delta-maildirpp-20260704`; `unpack`, `verify-tree`, `inspect`, independent counts, and Evolution Flatpak visibility all succeeded with 248 `cur`, 0 `new`, 0 `tmp`, and folder counts Inbox 241, Sent 4, Local_Folders.November2025 2, Trash 1.
- The owner validated the restored antiX delta target in Evolution as a separate `Maildir-format mail directories` account: Inbox 241, Sent 4, November2025 2, Trash 1, messages opened, HTML rendered, attachments were visible, and no error popup appeared.
- The Betterbird delta archive must remain separate from `/mail/Mailstore/evolution/local-maildir` and `/mail/Mailstore/mbsync/provider-live` unless a later merge is explicitly planned, backed up, and tested.
- `src/betterbird_post_archive_delta.py` is the current future-facing delta helper. It uses `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp/.conversion-state.sqlite` as the baseline for the original main archive/export `maildirpp-archive-export-20260701-215204`, expects 48,720 copied baseline rows by default, and never uses email `Date:` headers as the cutoff.
- The dynamic post-main-archive helper selects every current Betterbird source file absent from the main baseline, whether the current count is 249, 500, or another later value. It first excludes exact `(source_path, size, mtime_ns)` matches, then relative-path matches when the source root changed, then SHA256 matches to avoid falsely selecting old mail after path or mtime changes.
- The dynamic helper stages selected mail under `/home/atiq/Evolution-Mailstore/post-main-archive-work/RUN_ID/staging-betterbird-maildir`, plans converter targets as `/home/atiq/Evolution-Mailstore/betterbird-post-main-archive-maildirpp-RUN_ID`, refuses to overwrite existing staging/target directories, refuses missing baseline state, reports `status=no_post_archive_mail` when there is no delta, and blocks over 10,000 selected messages unless explicitly overridden.
- The previous 248-message delta remains validated historical data. Future post-main-archive aggregate runs supersede older post-main-archive delta Evolution accounts after the newer aggregate is validated. Disable or remove the older 248-message delta account in Evolution UI to avoid duplicate search results; do not delete old delta files until backup and cleanup are explicitly planned.
- The Betterbird delta Maildir++ guide now documents the dynamic "Post-Main-Archive Aggregate Delta" workflow. It begins with a RUN_ID-based Fedora audit, then mail-process shutdown, staging, converter dry-run, copy/hash verification, pack/verify, optional Google Drive ZIP, antiX staging, antiX restore/inspect, and Evolution GUI validation.
- Fedora dynamic aggregate run `20260704-205827` succeeded through pack/verify on 2026-07-04. It selected 249 post-main-archive messages from the current Betterbird source, all `cur`, 0 `new`, 436,492,704 selected bytes, with folder split Inbox 242, Sent 5, and Local_Folders/November2025 2. It staged 249 `cur`, converted and SHA256-verified 249 messages into `/home/atiq/Evolution-Mailstore/betterbird-post-main-archive-maildirpp-20260704-205827`, then packed and verified `/home/atiq/maildirpp-post-main-archive-export-20260704-205827` as 1 part, 299,207,989 archive bytes, 286M export, `status=ok`.
- The owner confirmed the old 248-message delta's `Trash: 1` difference is expected because that Trash email was manually deleted from Betterbird before the new dynamic aggregate run. Therefore aggregate `20260704-205827` should be treated as a current-source post-main-archive snapshot, not as a strict superset of the older 248-message delta. Do not use old-delta hash equality as a blocker for this run; keep old delta files until backup and cleanup are explicitly planned if the intentionally deleted Trash message may ever be needed.
- Fedora Batch 7A visibility check for aggregate `20260704-205827` succeeded. The host and Evolution Flatpak sandbox both saw 249 `cur`, 0 `new`, and 0 `tmp`; host folder counts were `.mail_tagindustries_com_sg.Inbox` 242, `.mail_tagindustries_com_sg.Sent` 5, and `.Local_Folders.November2025` 2.
- The owner validated dynamic aggregate `20260704-205827` in Fedora Evolution as a separate `Maildir-format mail directories` account: Inbox 242, Sent 5, November2025 2, Trash 0, messages opened, HTML rendered, attachments were visible, and no error popup appeared.
- The Betterbird delta Maildir++ HTML guide CSS was corrected after screenshot review so `pre code` command blocks no longer inherit the pale inline-code background. Brave rendering validation confirmed command text is visible on the dark code block and inline code still uses the pale style.
- The Betterbird delta Maildir++ HTML guide `Start Here` section now renders Batch 1 through Batch 9 as separate command blocks with `Copy Batch 1` through `Copy Batch 9` buttons. Each button copies only the command text inside that batch's shell block, not headings, explanations, or fenced-code markers.
- The Maildir++ archive guide now uses the validated antiX restore chunk based on `~/codex-runs/maildirpp_transport.py` instead of fragmented repo-relative restore examples. This prevents the earlier variable-only no-op pattern and keeps pre-unpack archive verification, destination-empty refusal, unpack, `verify-tree`, and final `inspect` in one logged operation.
- The converted Betterbird archive must stay separate from mbsync `provider-live`; it is a local read/archive Maildir++ account, not a live IMAP sync tree.
- Evolution Flatpak 3.60.2 from Flathub was validated on antiX 26 runit with zzzFM/IceWM. It is installed as a user Flatpak, granted `/mail:create`, and its app directory is symlinked from `~/.var/app/org.gnome.Evolution` to `/mail/AppData/flatpak-evolution/appdir`.
- Evolution Flatpak desktop launching should use `scripts/evolution_flatpak_icewm_launcher_setup.sh` on antiX. The validated setup creates `~/.local/bin/evolution-flatpak-mail`, adds marked IceWM `~/.icewm/personal` and `~/.icewm/toolbar` entries, adds a marked keyring startup block to `~/.icewm/startup`, and keeps wrapper-level keyring fallback.
- The validated IceWM launcher uses the official Flatpak-exported icon at `~/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/org.gnome.Evolution.svg`. The tested antiX VM showed SHA256 `dcda7580deebec635ff3d560795a45dd41e62ce3e7d311a170b46b4cf2a0cbb2`.
- The verified Evolution test account uses `BackendName=maildir` and reads a Maildir++ test tree at `/mail/Mailstore/evolution/test-maildir`. Selecting `MH-format mail directories` is a known wrong path because it can show folder names while hiding Maildir `cur`/`new` messages.
- The first approved mbsync path is APT `isync` on antiX/Debian, not a source build, unless target VM package discovery shows an unsuitable version.
- The first mbsync test used the isolated target `/mail/Mailstore/mbsync/provider-inbox-test`, with state in `/mail/AppData/isync/state/provider`, logs in `/mail/Logs/mbsync`, and `~/.config/isyncrc` reading `~/.config/isync/provider.pass` via `PassCmd`.
- antiX validation on 2026-06-27 confirmed `isync 1.5.1`, successful IMAP login to `mail.tagindustries.com.sg`, 144 INBOX messages pulled into `/mail/Mailstore/mbsync/provider-inbox-test`, post-Evolution mbsync succeeded, and Evolution Flatpak created a `BackendName=maildir` source pointing at the test Maildir path.
- The first mbsync channel is INBOX-only and local-preserving: `Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None`. `mbsync --dry-run` hit an isync 1.5.1 assertion on the empty test Maildir, so validation proceeded with logged real pulls after confirming the target was empty and deletion-safe policy was intact.
- The antiX mbsync config/log snapshot was saved under `/mail/Backups/mbsync` before production promotion. Empty remote folders `FARSUK` and `BASUNDHARA` were verified empty and removed from the IMAP server at the owner's request.
- Production mbsync `provider-live` was validated on 2026-06-27 with the exact remote folders `INBOX`, `Drafts`, `Trash`, `spam`, `Sent`, `Junk`, and `Archive`. It uses `/mail/Mailstore/mbsync/provider-live`, state in `/mail/AppData/isync/state/provider-live`, logs in `/mail/Logs/mbsync-live`, `PipelineDepth 1`, and `UseNamespace yes`.
- The current production mbsync config keeps normal folders receive-only in channel `provider-live` with explicit `Patterns "INBOX" "Drafts" "Trash" "spam" "Junk" "Archive"`, `Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None`. Sent mail is handled by a narrow channel `provider-live-sent-upload` mapping only `Sent <=> Sent` with `Sync PullNew PushNew`, `Create None`, `Remove None`, and `Expunge None`.
- The first `provider-live` pull downloaded 163 messages: 151 INBOX, 4 Sent, and 8 Trash. A second pull had zero delta and no duplicate flood. After Evolution SMTP testing and Gmail replies, a post-SMTP pull reached 170 messages: 158 INBOX, 4 Sent, and 8 Trash. `tmp` remained empty throughout.
- Evolution Flatpak reads the production `provider-live` tree as `BackendName=maildir` with path `/mail/Mailstore/mbsync/provider-live`. The owner verified opening/searching production messages and successfully sent two messages by SMTP to Gmail; Gmail replies were pulled back into `provider-live`.
- Evolution's production account `TAG-Mustang_mbsync-Live` now stores sent copies in `folder://ca9e0701d552924b5b13afa4b29213e130bba0bf/Sent`, which corresponds to `/mail/Mailstore/mbsync/provider-live/.Sent`.
- Sent upload was validated on 2026-06-27. A controlled Sent-only upload changed remote `INBOX.Sent` from 4 to 5 messages with `Far: +1`; a second Sent sync had zero delta. A later automatic loop test saved one new local Sent message and uploaded it to remote Sent, reaching local Sent 6 and remote `INBOX.Sent` 6 with `MaxPushedUid 6`.
- The production auto-sync loop uses `~/.local/bin/mbsync-provider-live-loop` and `~/.local/bin/mbsync-provider-live-control`, polls every 180 seconds, writes one daily auto log under `/mail/Logs/mbsync-live`, targets `provider-live-group`, supports `status`, `pause`, `resume`, `sync-now`, `logs`, `cleanup-logs`, `clear-stale-lock`, `stop-loop`, and `start`, and starts from a marked IceWM startup block. Final audit confirmed repeated automatic group runs with exit `0`, no lock left behind, and `tmp` still empty.
- The verified IceWM startup marker is uppercase `# BEGIN CODEX MBSYNC PROVIDER LIVE AUTOSYNC`; the startup block runs `~/.local/bin/mbsync-provider-live-control start`.
- The provider-live auto-sync scripts now include validated log retention: auto logs older than 2 days are compressed if `gzip` is available, auto logs older than 30 days are deleted, manual/validation logs are kept for 90 days, and `status` reports `/mail/Logs/mbsync-live` disk usage. The antiX fake-log proof compressed an old auto log, deleted expired auto/manual logs, kept a recent manual log, and removed fake leftovers.
- The provider-live auto-sync scripts were further hardened on antiX on 2026-06-27 for slow or large syncs. The loop remains sequential, so a sync that takes longer than 180 seconds delays the next pass rather than overlapping it. Generated scripts default to `MBSYNC_PROVIDER_LIVE_SYNC_TIMEOUT_SECONDS=3600`, wrap `mbsync` with `timeout` when available, write lock metadata, expose `sync_timeout_seconds`, sync age, sync channel, sync pid, and pid liveness in `status`, and add `clear-stale-lock` for non-running stale locks. The antiX proof created a fake 10-minute-old lock with pid `99999999`, showed `sync_age_seconds=600` and `sync_pid_alive=no`, cleared it successfully, then validated `sync-now` and the restarted loop with exit `0`, `sync_lock=absent`, and all provider-live `tmp` folders empty.
- The generated provider-live control script now verifies that a saved loop PID belongs to `mbsync-provider-live-loop` before reporting the loop as running or sending a stop signal. Stale loop PID files are shown as `stale_loop_pid` and ignored for process killing. The timeout wrapper uses GNU `timeout --kill-after=60s` when supported and falls back to plain `timeout` otherwise.
- `scripts/mbsync_provider_inbox_setup.sh` now includes production helper commands for the validated setup: `production-layout`, `write-production-config`, `production-list`, `production-sync`, `production-status`, `write-autosync`, `install-autosync-startup`, `autosync-status`, `autosync-preflight`, `refresh-autosync`, `autosync-stale-lock-proof`, `autosync-validate`, and `autosync-log-rotation-proof`.
- `docs/MBSYNC_ANTIX_GUIDE.html` and `.txt` now include a clear `Start Here: Fresh Setup` sequence before the production reference material. Fresh antiX runs start with the INBOX validation helper sequence, then production `provider-live`, then Evolution GUI checks, then auto-sync validation. The production mbsync config block is explicitly labeled reference-only so it is not mistaken for a terminal command.
- `docs/WORK_VALIDATION_LEDGER.md` is now the durable record for all future terminal-guided and validation-heavy work, regardless of topic. It records chunk/action, output source, result, notes, and follow-up without storing secrets or massive raw logs. Historical entries are summarized from confirmed project memory because earlier exact pasted-output pairs were not preserved.
- notmuch 0.39 is now configured on antiX as a sidecar pilot index. The config is at `~/.config/notmuch/default/config`, the disposable database is `/mail/SearchIndex/notmuch/default`, the mail root is `/mail/Mailstore`, `maildir.synchronize_flags=false`, and `index.decrypt=false`.
- The notmuch pilot currently indexes only `/mail/Mailstore/mbsync/provider-live` and the restored Betterbird delta scope, producing 457 unique messages and 867 files after the 2026-07-05 refresh. The 59G archive remains ignored because a later audit showed `/mail/Mailstore/evolution/local-maildir` at 48,564 `cur` instead of the earlier verified 48,720, and the delta count also drifted from 248 to 247.
- Astroid `0.16+20240629-1` was purged on 2026-07-05 after its settings were backed up to `/mail/Backups/notmuch/astroid-retired-20260705-232014`. Its user config/cache/helper paths were removed, and the Astroid-only compatibility symlinks under `/mail/SearchIndex/notmuch/default` were removed after being verified as symlinks.
- Evolution Flatpak must not be used as a raw notmuch file opener. `xdg-open` on a selected Maildir file opened Evolution's wrong `Import Data - Berkeley Mailbox (mbox)` flow instead of a normal message viewer or reply/forward workflow. Evolution remains the normal read/reply/send mail client for its configured Maildir accounts.
- The validated notmuch GUI path is the read-only localhost browser viewer at `~/.local/bin/notmuch-browser-pilot`, launched on `http://127.0.0.1:8765/`. It now uses single-email mode: search results are individual messages, `/message?id=<message-id>` opens one selected email body, exact `id:<message-id>` search works, and the Status page reports `Viewer mode: single-email`. This viewer is read/search/view only; reply/send stays in Evolution.
- notmuch backup/restore/reindex helper validation has passed for the pilot scope. Corrected Chunk 8B-FIX1 passed shell/Python syntax checks, tag backup/restore, exact `id:` search, indexed path stability, and zero `tmp` changes. Chunk 8C then moved the old database to `/mail/Backups/notmuch/reindex-db/default-20260705-084026`, rebuilt only `/mail/SearchIndex/notmuch/default`, restored tags from `/mail/Backups/notmuch/notmuch-tags-before-reindex-20260705-084026.batch-tag`, preserved 444 messages and 846 files at that time, kept the pilot Maildir file list unchanged, kept `tmp` folders empty, resumed mbsync, and relaunched the browser viewer.
- `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.html` and `.txt` now document the active browser-only path, including Astroid purge, single-email viewer installation, shim removal, daily browser-viewer start/stop commands, status checks, CLI search examples, tag backup/restore, pilot-safe reindex, and the deferred full-archive expansion preflight. The older `docs/NOTMUCH_ASTROID_ANTIX_GUIDE.html` and `.txt` are retained only as retired historical guides.
- Windows validation passed for syntax and portable unit tests. The copy-preserves-Maildir-flags converter test is skipped on Windows because `:2,` filenames are Linux Maildir-specific and invalid on Windows filesystems.
- Next dynamic delta validation must transfer the verified aggregate export `/home/atiq/maildirpp-post-main-archive-export-20260704-205827` to antiX, restore it as a separate Evolution Maildir account, and validate message counts, message opening, HTML rendering, attachments, and absence of error popups.

## Open Questions

- What should this project become?
- Which operating environments must the finished project support beyond Windows 11 and Debian Linux?
- Should the remote be GitHub or GitLab?
- Should the project use a conventional branching model, trunk-based work, or simple local commits until the direction is clearer?
- What is the first implementation milestone after planning/setup?

## Next Actions

1. Review the setup and memory files.
2. Keep the notmuch pilot scope limited to `provider-live` plus the small restored delta until the 59G archive count drift is explained or accepted.
3. Use the read-only single-email browser viewer as the validated notmuch GUI for search/view and keep Evolution Flatpak as the reply/send client.
4. Transfer the verified new aggregate export to antiX, restore it as a separate Evolution account, and validate message counts/opening/HTML/attachments.
5. After antiX validation, disable/remove older post-main-archive delta accounts from Evolution UI to avoid duplicate search results, but do not delete files until backup and cleanup are explicitly planned.
6. Keep the old delta export ZIP, antiX staging package, and restored delta target until the delta archive is included in a backup and any cleanup is explicitly planned.
7. Keep the production mbsync `provider-live` loop monitored with `mbsync-provider-live-control status` during normal antiX use.
8. Consider later hardening of mbsync credentials with GPG only after unattended polling remains stable.
9. Consider `PullFlags` or broader IMAP two-way behavior only as separate controlled changes.
10. Decide broader project type and future packaging only if needed.

## Cross-Machine Restore Instructions

Use Git to move the repository between machines once a remote is connected.

General restore flow:

1. Install Git on the target Windows 11 or Debian Linux machine.
2. Clone the repository from the chosen remote.
3. Open the repository root.
4. Read `AGENTS.md`, `README.md`, `docs/PROJECT_STATE.md`, `docs/TODO.md`, `docs/DECISIONS.md`, and `docs/WORK_VALIDATION_LEDGER.md`.
5. Run `git status --short --branch` before making changes.
6. Do not install dependencies until the project type and dependency policy are decided.

## Notes for Future Codex Sessions

- Start by reading the required memory files listed in `AGENTS.md`.
- Treat this file as the high-level state snapshot.
- Use `docs/WORK_VALIDATION_LEDGER.md` as the durable per-step record when reviewing command chunks or pasted terminal output.
- Keep documentation current as work proceeds.
- Prefer small, reviewable changes.
- Ask before dependency installation, deletion, or remote pushes.
- Preserve portability between Windows 11 and Debian Linux.
