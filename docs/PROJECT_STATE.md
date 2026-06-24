# Project State

Last updated: 2026-06-24

## Project Identity

- Repository name: `antiX_VM_Laptop`
- Project type: local mail migration utility plus planning/setup repository
- Primary purpose today: durable project memory and a safe Betterbird maildir-lite to Maildir++ conversion script
- Portability target: Windows 11 and Debian Linux
- Future remote target: GitHub or GitLab, not connected by this setup task

## Current Phase

Planning/setup with one approved utility implementation.

The owner approved implementation of a Python standard-library converter for Betterbird/Thunderbird maildir-lite to canonical Maildir++ migration. Other application direction remains undecided.

## Current Objective

Create a professional, AI-readable memory and Git workflow system that supports future Codex sessions and cross-machine work, plus maintain the approved mail migration utility.

## What Exists Now

- Git repository on branch `main`, tracking `origin/main`.
- `README.md` with project overview and start instructions.
- `AGENTS.md` with future Codex operating rules.
- `docs/` project memory folder.
- `src/` placeholder folder for future implementation work.
- `.gitignore` with language-neutral local, cache, and generated-file exclusions.
- `src/betterbird_maildirlite_to_maildirpp.py`, a dry-run-first Python converter for staged Betterbird maildir-lite profiles.
- `tests/test_betterbird_maildirlite_to_maildirpp.py`, standard-library tests for folder mapping and portable validation.

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
- The current converter must remain Python 3 standard-library-only unless the owner approves a dependency change.
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
- `.gitignore`
- `src/betterbird_maildirlite_to_maildirpp.py`
- `tests/test_betterbird_maildirlite_to_maildirpp.py`

## Current Implementation Notes

- The converter is designed to run on antiX after the Fedora Betterbird profile is copied to `/mail/import-staging/betterbird-maildir`.
- Default mode is `--dry-run`; `--copy` refuses unmarked or unsafe sources and writes through Maildir `tmp` before atomic rename.
- Duplicates are kept, but duplicate `Message-ID` and content hashes are logged.
- Windows validation passed for syntax and portable unit tests. The copy-preserves-Maildir-flags test is skipped on Windows because `:2,` filenames are Linux Maildir-specific and invalid on Windows filesystems.
- Next validation must be run on antiX against a staged sample profile.

## Open Questions

- What should this project become?
- Which operating environments must the finished project support beyond Windows 11 and Debian Linux?
- Should the remote be GitHub or GitLab?
- Should the project use a conventional branching model, trunk-based work, or simple local commits until the direction is clearer?
- What is the first implementation milestone after planning/setup?

## Next Actions

1. Review the setup and memory files.
2. Commit and push the setup using the approved end-of-session workflow.
3. Run the converter dry-run on antiX against a staged Betterbird sample profile.
4. Review conversion logs before any full copy.
5. Decide broader project type and future packaging only if needed.

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
