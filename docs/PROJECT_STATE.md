# Project State

Last updated: 2026-06-27

## Project Identity

- Repository name: `antiX_VM_Laptop`
- Project type: local mail migration utilities plus planning/setup repository
- Primary purpose today: durable project memory, a safe Betterbird profile transport utility, a safe Betterbird maildir-lite to Maildir++ conversion script, validated Evolution Flatpak setup documentation for antiX, prepared antiX helper scripts for Evolution launching, and a validated first mbsync INBOX test path
- Portability target: Windows 11 and Debian Linux
- Future remote target: GitHub or GitLab, not connected by this setup task

## Current Phase

Planning/setup with approved local mail migration utility implementations.

The owner approved Python standard-library utilities for transporting a full Betterbird profile tree from Fedora to antiX staging and converting Betterbird/Thunderbird maildir-lite to canonical Maildir++, plus small antiX setup helpers for launching Evolution Flatpak and testing deletion-safe mbsync pulls. Other application direction remains undecided.

## Current Objective

Create a professional, AI-readable memory and Git workflow system that supports future Codex sessions and cross-machine work, plus maintain the approved mail migration utilities.

## What Exists Now

- Git repository on branch `main`, tracking `origin/main`.
- `README.md` with project overview and start instructions.
- `AGENTS.md` with future Codex operating rules.
- `docs/` project memory folder.
- `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html`, an offline browser DIY guide with copy buttons for the full Fedora-to-antiX transport and conversion flow.
- `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt`, a terminal-friendly plain text version of the same guide.
- `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.html`, an offline browser DIY guide with copy buttons for installing and preparing Evolution Flatpak 3.60.2 on antiX runit/IceWM.
- `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.txt`, a terminal-friendly plain text version of the same Evolution Flatpak guide.
- `docs/MBSYNC_ANTIX_GUIDE.html`, an offline browser DIY guide with copy buttons for the first deletion-safe mbsync INBOX test and the next controlled second-folder expansion on antiX.
- `docs/MBSYNC_ANTIX_GUIDE.txt`, a terminal-friendly plain text version of the same mbsync guide.
- `src/` placeholder folder for future implementation work.
- `.gitignore` with language-neutral local, cache, and generated-file exclusions.
- `.gitattributes` enforcing LF line endings for shell and Python scripts.
- `src/betterbird_profile_transport.py`, a Python standard-library tool to pack, split, verify, unpack, and verify a whole Betterbird profile tree for transfer.
- `src/betterbird_maildirlite_to_maildirpp.py`, a dry-run-first Python converter for staged Betterbird maildir-lite profiles.
- `tests/test_betterbird_profile_transport.py`, standard-library tests for split archive transport safety.
- `tests/test_betterbird_maildirlite_to_maildirpp.py`, standard-library tests for folder mapping and portable validation.
- `scripts/evolution_flatpak_icewm_launcher_setup.sh`, a user-level antiX helper for adding Evolution Flatpak to IceWM menu/taskbar launch surfaces and starting `gnome-keyring-daemon`.
- `scripts/mbsync_provider_inbox_setup.sh`, an antiX helper for inspecting package/layout state, installing isync/mbsync, creating the isolated `/mail` mbsync test layout, writing a pull-only INBOX config, dry-running, and pulling once.

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
  - `docs/IDEAS.md`
  - `docs/WORKFLOW.md`
  - `docs/CHANGELOG.md`
  - `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.html`
  - `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt`
  - `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.html`
  - `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.txt`
  - `docs/MBSYNC_ANTIX_GUIDE.html`
  - `docs/MBSYNC_ANTIX_GUIDE.txt`
- `.gitignore`
- `.gitattributes`
- `src/betterbird_profile_transport.py`
- `src/betterbird_maildirlite_to_maildirpp.py`
- `scripts/evolution_flatpak_icewm_launcher_setup.sh`
- `scripts/mbsync_provider_inbox_setup.sh`
- `tests/test_betterbird_profile_transport.py`
- `tests/test_betterbird_maildirlite_to_maildirpp.py`

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
- Evolution Flatpak 3.60.2 from Flathub was validated on antiX 26 runit with zzzFM/IceWM. It is installed as a user Flatpak, granted `/mail:create`, and its app directory is symlinked from `~/.var/app/org.gnome.Evolution` to `/mail/AppData/flatpak-evolution/appdir`.
- Evolution Flatpak desktop launching should use `scripts/evolution_flatpak_icewm_launcher_setup.sh` on antiX. The validated setup creates `~/.local/bin/evolution-flatpak-mail`, adds marked IceWM `~/.icewm/personal` and `~/.icewm/toolbar` entries, adds a marked keyring startup block to `~/.icewm/startup`, and keeps wrapper-level keyring fallback.
- The validated IceWM launcher uses the official Flatpak-exported icon at `~/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/org.gnome.Evolution.svg`. The tested antiX VM showed SHA256 `dcda7580deebec635ff3d560795a45dd41e62ce3e7d311a170b46b4cf2a0cbb2`.
- The verified Evolution test account uses `BackendName=maildir` and reads a Maildir++ test tree at `/mail/Mailstore/evolution/test-maildir`. Selecting `MH-format mail directories` is a known wrong path because it can show folder names while hiding Maildir `cur`/`new` messages.
- The first approved mbsync path is APT `isync` on antiX/Debian, not a source build, unless target VM package discovery shows an unsuitable version.
- The first mbsync test used the isolated target `/mail/Mailstore/mbsync/provider-inbox-test`, with state in `/mail/AppData/isync/state/provider`, logs in `/mail/Logs/mbsync`, and `~/.config/isyncrc` reading `~/.config/isync/provider.pass` via `PassCmd`.
- antiX validation on 2026-06-27 confirmed `isync 1.5.1`, successful IMAP login to `mail.tagindustries.com.sg`, 144 INBOX messages pulled into `/mail/Mailstore/mbsync/provider-inbox-test`, post-Evolution mbsync succeeded, and Evolution Flatpak created a `BackendName=maildir` source pointing at the test Maildir path.
- The first mbsync channel is INBOX-only and local-preserving: `Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None`. `mbsync --dry-run` hit an isync 1.5.1 assertion on the empty test Maildir, so validation proceeded with logged real pulls after confirming the target was empty and deletion-safe policy was intact.
- The next mbsync expansion must snapshot the working antiX config/logs, list remote folders read-only, and test exactly one small non-INBOX folder in `/mail/Mailstore/mbsync/provider-folder-test` before creating any `provider-live` tree.
- notmuch is installed on antiX but intentionally unconfigured; Astroid is not installed. notmuch/Astroid remain later sidecar search tests after the live Maildir layout is stable.
- Windows validation passed for syntax and portable unit tests. The copy-preserves-Maildir-flags converter test is skipped on Windows because `:2,` filenames are Linux Maildir-specific and invalid on Windows filesystems.
- Next validation must be run on Fedora/antiX with a real or representative Betterbird profile transfer before the full migration.

## Open Questions

- What should this project become?
- Which operating environments must the finished project support beyond Windows 11 and Debian Linux?
- Should the remote be GitHub or GitLab?
- Should the project use a conventional branching model, trunk-based work, or simple local commits until the direction is clearer?
- What is the first implementation milestone after planning/setup?

## Next Actions

1. Review the setup and memory files.
2. Snapshot the validated antiX mbsync config and logs to `/mail/Backups/mbsync` without copying `provider.pass`.
3. Inventory remote IMAP folders read-only with `mbsync -c ~/.config/isyncrc --list-stores provider-remote`.
4. Select exactly one small non-INBOX, non-special folder for a second isolated mbsync test.
5. Test the selected folder under `/mail/Mailstore/mbsync/provider-folder-test` with the same deletion-safe policy before creating `/mail/Mailstore/mbsync/provider-live`.
6. Create `/mail/Mailstore/mbsync/provider-live` only after the second-folder test passes and the final folder selection is known.
7. Resume the Betterbird profile transport: pack a representative Fedora Betterbird profile sample with `src/betterbird_profile_transport.py pack`.
8. Verify transferred parts on antiX with `verify-archive`.
9. Restore into `/mail/import-staging/betterbird-maildir` with `unpack`.
10. Verify the restored profile with `verify-tree`.
11. Run the converter dry-run on antiX against the staged Betterbird profile.
12. Review conversion logs before any full copy.
13. Convert validated Betterbird mail into `/mail/Mailstore/evolution/local-maildir` only after staging and dry-run checks pass.
14. Add the validated production Maildir++ tree to Evolution using `Maildir-format mail directories`.
15. Decide broader project type and future packaging only if needed.

## Cross-Machine Restore Instructions

Use Git to move the repository between machines once a remote is connected.

General restore flow:

1. Install Git on the target Windows 11 or Debian Linux machine.
2. Clone the repository from the chosen remote.
3. Open the repository root.
4. Read `AGENTS.md`, `README.md`, `docs/PROJECT_STATE.md`, `docs/TODO.md`, and `docs/DECISIONS.md`.
5. Run `git status --short --branch` before making changes.
6. Do not install dependencies until the project type and dependency policy are decided.

## Notes for Future Codex Sessions

- Start by reading the required memory files listed in `AGENTS.md`.
- Treat this file as the high-level state snapshot.
- Keep documentation current as work proceeds.
- Prefer small, reviewable changes.
- Ask before dependency installation, deletion, or remote pushes.
- Preserve portability between Windows 11 and Debian Linux.
