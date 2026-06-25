# Decisions

This file records meaningful project decisions. Add a new entry when the project owner makes or approves a choice that affects architecture, tooling, workflow, dependencies, hosting, or long-term direction.

## Decision Log

### 2026-06-23: Commit and Push After Each Working Session

- Status: accepted
- Context: The owner wants repository state preserved at the end of each working session.
- Decision: Run `git add .`, commit with a clear self-explanatory message, and run `git push` after each working session.
- Consequence: Future sessions should expect recent work to be available from the configured remote. Non-routine remote operations still require explicit owner approval.

### 2026-06-23: Keep Repository Language-Neutral During Setup

- Status: accepted
- Context: The project type has not been decided.
- Decision: Do not add runtime dependencies, package managers, framework files, Docker files, devcontainers, or application features during setup.
- Consequence: The repository remains portable and low-commitment until the first implementation objective is chosen.

### 2026-06-23: Use Markdown Project Memory

- Status: accepted
- Context: Future Codex sessions need immediate project context.
- Decision: Maintain project memory in Markdown files under `docs/`, with `AGENTS.md` as the operating guide for AI sessions.
- Consequence: Memory is Git-native, easy to diff, and portable across Windows 11 and Debian Linux.

### 2026-06-24: Implement Maildir-Lite to Maildir++ Converter as Python Standard-Library Utility

- Status: accepted
- Context: The owner needs a safe migration path from Betterbird/Thunderbird maildir-lite storage on Fedora to canonical Maildir++ storage for Evolution on antiX.
- Decision: Implement `src/betterbird_maildirlite_to_maildirpp.py` as a Python 3 standard-library-only utility with dry-run default, copy mode, resume support, logs, duplicate auditing, and verification support.
- Consequence: The repository now has one approved implementation artifact while broader project type and packaging remain undecided. The converter should be validated on antiX before production use.

### 2026-06-25: Implement Betterbird Profile Transport as Python Standard-Library Utility

- Status: accepted
- Context: The owner needs to move a 59-60 GB Fedora Betterbird profile/mail tree intact to antiX staging before running the maildir-lite to Maildir++ converter.
- Decision: Implement `src/betterbird_profile_transport.py` as a Python 3 standard-library-only utility that packs the whole profile root contents into a gzip-compressed tar stream, splits it into verified 1900 MiB parts by default, writes `manifest.json` and `inventory.jsonl`, restores to `/mail/import-staging/betterbird-maildir`, and verifies the restored tree.
- Consequence: Profile transfer remains dependency-free and portable across Fedora, antiX, and Windows repository validation. The safest full migration flow is now pack, transfer all parts and metadata, verify archive, unpack, verify tree, then run the existing converter dry-run and copy modes.

## Pending Decisions

- Broader project type beyond the mail migration utility
- Packaging/runtime policy beyond Python 3 standard library
- Framework or no-framework direction
- Git hosting provider: GitHub or GitLab
- First implementation milestone
- Dependency installation policy after project type is chosen
