# Decisions

This file records meaningful project decisions. Add a new entry when the project owner makes or approves a choice that affects architecture, tooling, workflow, dependencies, hosting, or long-term direction.

## Decision Log

### 2026-06-27: Use Deletion-Safe Production mbsync Provider-Live

- Status: accepted
- Context: The first INBOX test and Evolution validation succeeded. Remote folder inventory later showed only seven desired folders after the owner deleted the empty `FARSUK` and `BASUNDHARA` folders. The owner requested production mbsync setup for `INBOX`, `Drafts`, `Trash`, `spam`, `Sent`, `Junk`, and `Archive`.
- Decision: Create `/mail/Mailstore/mbsync/provider-live` with state in `/mail/AppData/isync/state/provider-live`, logs in `/mail/Logs/mbsync-live`, exact `Patterns` for the seven folders, `PipelineDepth 1`, `UseNamespace yes`, `Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None`. Keep SMTP sending in Evolution and keep Sent upload, flag sync, GPG password migration, and notmuch/Astroid as later controlled changes.
- Consequence: The antiX VM now has a validated production receive-only mbsync tree that Evolution reads as `BackendName=maildir`, plus a 180-second user-level polling loop launched from IceWM startup. The earlier second-folder-before-live approach is superseded by the observed server cleanup and exact seven-folder production validation.

### 2026-06-27: Promote mbsync Through One Folder Before Live Tree

- Status: superseded by "Use Deletion-Safe Production mbsync Provider-Live"
- Context: The first antiX mbsync INBOX test succeeded with 144 messages pulled into `/mail/Mailstore/mbsync/provider-inbox-test`, Evolution Flatpak reading the tree as `BackendName=maildir`, and a post-Evolution mbsync run succeeding without duplicate flood or unexpected deletions.
- Decision: Treat the INBOX test tree as a validated test account, snapshot the working antiX config/logs, list remote IMAP folders read-only, test exactly one small non-INBOX folder in `/mail/Mailstore/mbsync/provider-folder-test`, and only then create `/mail/Mailstore/mbsync/provider-live`.
- Consequence: This was the conservative path before remote folder cleanup. It was superseded after the server contained only seven explicitly desired folders and the owner requested direct production promotion with exact `Patterns`.

### 2026-06-26: Use APT mbsync for First IMAP INBOX Test

- Status: accepted
- Context: After the Evolution Flatpak setup was completed, the owner wanted the next migration phase to add mbsync for new IMAP mail while preserving the Betterbird-only local archive and avoiding premature notmuch/Astroid setup.
- Decision: Use antiX/Debian APT `isync`/`mbsync` first, create an isolated INBOX-only test Maildir at `/mail/Mailstore/mbsync/provider-inbox-test`, store mbsync state under `/mail/AppData/isync/state/provider`, write logs under `/mail/Logs/mbsync`, and generate `~/.config/isyncrc` with `PassCmd` reading `~/.config/isync/provider.pass`.
- Consequence: The first mbsync workflow is explicit, reversible, and deletion-safe with `Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None`. notmuch/Astroid remain later sidecar search tests after Evolution and mbsync are proven.

### 2026-06-26: Launch Evolution Flatpak Through User-Level IceWM Helper

- Status: accepted
- Context: The owner needed Evolution Flatpak to launch from IceWM without manually running `gnome-keyring-daemon --start --components=secrets,pkcs11,ssh` and `flatpak --user run org.gnome.Evolution` in a terminal each time.
- Decision: Use a user-level wrapper at `~/.local/bin/evolution-flatpak-mail`, add marked IceWM `~/.icewm/personal` and `~/.icewm/toolbar` entries, start `gnome-keyring-daemon` from `~/.icewm/startup` with wrapper-level fallback, and point IceWM directly at the official Flatpak-exported icon `~/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/org.gnome.Evolution.svg`.
- Consequence: Evolution launch integration stays under the user account, uses no `sudo`, installs no packages, avoids the fragile main IceWM menu, uses the authentic Evolution icon instead of theme fallback, and remains reversible by removing the marked blocks or running the helper uninstall mode.

### 2026-06-26: Use Evolution Flatpak as First Validated Evolution Path on antiX

- Status: accepted
- Context: The owner wanted the latest Evolution for an antiX 26 runit VM with zzzFM/IceWM. Debian/antiX apt offered Evolution 3.56.x, while upstream/Flathub offered Evolution 3.60.2. A source build was feasible but required a large dependency set and careful Evolution Data Server matching on a 2 CPU, 3.2 GiB RAM VM.
- Decision: Use the user-level Flathub `org.gnome.Evolution` package as the preferred first Evolution path. Grant `/mail` access and symlink `~/.var/app/org.gnome.Evolution` to `/mail/AppData/flatpak-evolution/appdir` so large app data and cache live on the `/mail` XFS disk.
- Consequence: Evolution Flatpak is the documented GUI path for initial migration validation. Source-built Evolution remains a fallback, not the default next step. Production mail should still be added only after the Betterbird archive is converted and validated as canonical Maildir++.

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
