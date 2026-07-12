# Decisions

This file records meaningful project decisions. Add a new entry when the project owner makes or approves a choice that affects architecture, tooling, workflow, dependencies, hosting, or long-term direction.

## Decision Log

### 2026-07-12: Add Capability-Gated Attachment Export and Confirmed Image Rendering

- Status: accepted
- Context: The validated chi/HTMX browser displayed attachment names and sandboxed HTML but could not save decoded MIME parts or render CID/data/SVG images under explicit privacy control. The owner approved individual downloads, Save All ZIP, and two distinct image confirmations without adding reply, send, delete, tag editing, or remote-image proxying.
- Decision: Keep Maildir files, notmuch tags, and the notmuch database non-mutating. Decode only a signed message/duplicate/part capability through `notmuch show --format=raw`, stage bounded temporary output under `/mail/AppData/notmuch-browser/download-tmp`, and remove it after every response/error. Use process-lifetime HMAC-SHA256 capabilities, selected-duplicate-only ZIP Store archives, one download slot, two inline-image slots, and explicit byte/count/time limits. Process untrusted email HTML with pinned `golang.org/x/net/html v0.57.0`, raise the module floor to Go 1.25, keep the iframe sandbox, and require separate HTMX confirmations for embedded and remote images; the Go service never fetches remote images.
- Consequence: The browser can export selected MIME content without becoming a mail client or changing the indexed source. Image permission resets on reload, message change, or duplicate change. The adaptive Frost/Sapphire UI, local Lucide subset, local HTMX, and compiled Tailwind assets remain embedded in one binary. Local Go tests and desktop/mobile browser QA passed, but the new revision is not antiX production-validated until the staged operator rollout, read-only proof, Windows tunnel check, and reboot proof finish. The final HTML/TXT DIY guide must be regenerated only from those validated chunks.

### 2026-07-12: Use Dunst for IceWM Desktop Notifications

- Status: accepted
- Context: The provider-live threshold monitor correctly persists alerts and logs, but a live `notify-send` test failed because the antiX IceWM session has no owner or D-Bus service for `org.freedesktop.Notifications`. The session bus itself is healthy, and Debian Trixie offers several daemon choices.
- Decision: Use Debian APT `dunst` as the user-session notification daemon, start it from one marked IceWM startup block before the provider-live archive monitor, retain D-Bus activation as a fallback, and validate both a visible popup and reboot persistence. Do not change the archive monitor's durable status/log fallback.
- Consequence: Threshold alerts can appear visually in the minimal IceWM desktop without installing an XFCE, MATE, or GNOME-specific notification stack. Missing popup delivery never blocks or changes mail synchronization, threshold state, or approval gates.

### 2026-07-11: Archive Provider-Live Through an Approval-Gated Local Maildir++ Controller

- Status: accepted
- Context: The provider retains mail for a limited period, so all IMAP-visible mail must remain local. A very large active Evolution INBOX can become less ergonomic, but changing the mbsync Inbox path, recreating state, or propagating disappearance would risk loss or server-side effects.
- Decision: Keep `/mail/Mailstore/mbsync/provider-live` and its mbsync state unchanged. Monitor only root INBOX `cur` plus `new` and alert at 15,000. Archive a stable cutoff into the separate Evolution Maildir++ account `/mail/Mailstore/evolution/provider-live-archive` as `Inbox/YYYY/MM`. Require a UID/hash manifest, same-disk hard-link snapshot, verified external USB/HGFS split package, Evolution attestation, notmuch verification, and a real one-message mbsync canary before manifest-selected local unlinking. Never archive or delete automatically, and never enable `MaxMessages`, `PushGone`, `PullGone`, flag sync, removal, or expunge.
- Consequence: The live INBOX can return to only post-cutoff arrivals while all cutoff mail remains available in a separate Evolution account and notmuch index. Cleanup is recoverable from the retained snapshot and external backup. The implementation is locally tested, but antiX runtime gates must be validated chunk by chunk before the first production cleanup.

### 2026-07-11: Make Provider-Live Polling Interval Persistent and Runtime-Adjustable

- Status: accepted
- Context: The validated provider-live loop used a fixed 180-second delay. The owner requested a quick, low-risk way to change that timing without editing scripts or weakening the overlap protections.
- Decision: Keep 180 seconds as the default and add `interval`, `set-interval VALUE`, and `reset-interval` to the generated control script. Store a validated override in `/mail/AppData/isync/provider-live-loop/interval-seconds`, accept 60 seconds through 24 hours with seconds/minutes/hours suffixes, and have the sequential loop re-read the value during its five-second sleep checks. Do not restart or interrupt an active sync when the interval changes.
- Consequence: The polling delay survives logout and reboot, appears in `status`, and can be changed while the loop runs. The next pass still begins only after the current sync completes and the configured delay elapses, so existing lock and timeout behavior remains intact.

### 2026-07-09: Migrate notmuch Browser Service to chi Router and Compiled Tailwind CSS

- Status: accepted
- Context: After the read-only Go notmuch browser service was validated, the owner requested a more modular GUI/backend structure using Go `chi`, HTMX, and Tailwind CSS while preserving the same high-performance, low-resource, read-only antiX service posture.
- Decision: Keep the notmuch command layer, localhost binding, SSH tunnel access, control scripts, IceWM startup, and index-refresh loop unchanged, but replace the stdlib `ServeMux` with `github.com/go-chi/chi/v5` and move embedded HTML templates into modular files. Use Tailwind only as a build-time CSS generator: commit the compiled local `app.css`, keep the Tailwind source stylesheet, and require no Node/npm/Tailwind runtime on antiX. Continue serving local HTMX only.
- Consequence: The runtime remains a small single Go binary serving embedded local assets, with one small Go router dependency and no frontend build step on antiX. Future UI changes can be maintained through separate template and stylesheet files. Validation must run on antiX or another machine with Go installed because the Windows workspace still lacks a local Go toolchain.

### 2026-07-09: Keep notmuch Fresh With a User-Level Index Refresh Loop

- Status: accepted
- Context: After the Go notmuch browser was validated, a later `tag:inbox` search failed because notmuch still referenced Maildir files under `/mail/Mailstore/mbsync/provider-live/new/` that had been renamed or moved by subsequent provider-live activity. A manual locked `notmuch-browser-control refresh-index` fixed the issue by detecting 12 file renames and adding 102 new messages, but manual refresh is not sufficient for an always-on browser.
- Decision: Install a small user-level `~/.local/bin/notmuch-browser-index-control` loop from the IceWM session. It calls the existing safe `notmuch-browser-control refresh-index` path every 60 seconds, skips while the provider-live mbsync lock or notmuch refresh lock exists, writes logs under `/mail/Logs/notmuch-browser`, and starts from neutral IceWM markers `# BEGIN NOTMUCH BROWSER INDEX REFRESH SERVICE` / `# END NOTMUCH BROWSER INDEX REFRESH SERVICE`.
- Consequence: New provider-live Maildir changes should be indexed automatically soon after mbsync/Evolution activity without requiring root runit supervision or tmux. Search can still briefly lag behind live Maildir changes during an active sync or until the next refresh interval, but stale paths should self-repair once the loop runs. The service remains read-only from the browser's perspective; the refresh loop only updates the notmuch sidecar database.

### 2026-07-06: Install antiX Go Toolchain Under `/mail/AppData`

- Status: accepted
- Context: The Go notmuch browser service needs antiX-side compilation and tests. The Windows workspace did not have Go installed, and the antiX VM has a large `/mail` disk intended for application data. The owner requested use of `kerolloz/go-installer`, but direct `curl | bash` was avoided in favor of a pinned, audited script.
- Decision: Use pinned `kerolloz/go-installer` v3.0.0 after audit, with installer SHA256 `1bc7a17931b0e7966c6440155752ffaf33ded7194f48eda7db844839e9e9d2fe`. Install Go under `GOROOT=/mail/AppData/go/goroot`, set `GOPATH=/mail/AppData/go/workspace`, and keep the environment in the installer-managed block in `/home/atiq/.profile`.
- Consequence: antiX now has Go 1.26.4 available for validating and building the read-only notmuch browser service without using root-owned `/usr/local/go` or consuming extra space under the home filesystem. The repository still needs to be cloned or pulled on antiX before `go test ./...` and the service build can run there.

### 2026-07-06: Build Read-Only notmuch Browser as a Go Standard-Library Service

- Status: accepted
- Context: The owner requested an extremely lightweight, robust, always-available notmuch browser for antiX runit/IceWM that can be reached from Windows 11. Gin, Flask, uv-managed Python, and tmux were considered. The existing Python localhost browser viewer proved the workflow, but the next version needs a smaller permanent service posture.
- Decision: Implement the v1 service in Go using `net/http`, `html/template`, embedded local CSS/HTMX, and direct notmuch CLI execution with argument arrays. Do not use Gin or Flask for v1. Keep the service read-only: search and view only; Evolution remains reply/forward/send. Bind to `127.0.0.1:8765` by default and use an SSH tunnel from Windows 11. Use a POSIX control script and later IceWM startup or reviewed runit supervision; do not use tmux as the service supervisor.
- Consequence: The first broader application objective is now explicitly selected. The implementation lives under `cmd/notmuch-browser` and `internal/notmuchbrowser`, with `scripts/notmuch_browser_control.sh` as the antiX control source. Go compilation and `go test ./...` still need validation on antiX or another machine with Go installed because the Windows workspace used for implementation did not have Go available.

### 2026-07-05: Retire Astroid and Use Browser-Only Single-Email notmuch Viewer

- Status: accepted
- Context: Astroid 0.16 could list/search the pilot notmuch database only after compatibility symlinks, but message bodies stayed blank on this antiX/IceWM/VMware setup. The owner decided not to use Astroid anymore and requested a normal single-email browser view instead of the earlier thread-based browser view.
- Decision: Purge Astroid and its user settings after backing them up, remove the Astroid-only notmuch database compatibility symlinks, and make `~/.local/bin/notmuch-browser-pilot` the only supported notmuch GUI viewer. The browser viewer lists individual emails from `notmuch search --output=messages`, opens `/message?id=<message-id>`, and remains read-only.
- Consequence: notmuch remains the search backend and Evolution remains the reply/forward/send client. The active guide is now `docs/NOTMUCH_BROWSER_ANTIX_GUIDE.html` and `.txt`; the old Astroid guide is retained only as historical context with a retired warning. The 59G archive remains excluded until count drift is reviewed.

### 2026-07-05: Use notmuch Pilot Index with Read-Only Browser Viewer as the Primary Search GUI

- Status: superseded by "Retire Astroid and Use Browser-Only Single-Email notmuch Viewer"
- Context: The owner requested notmuch plus Astroid as a fast search layer for millions of Maildir++ messages, with Evolution used for viewing/replying/sending when practical. The pilot notmuch index succeeded for `provider-live` plus the restored small delta, but the 59G archive count drift made full expansion unsafe. Evolution raw-file handoff through `xdg-open` opened the wrong `Import Data - Berkeley Mailbox (mbox)` workflow. Astroid 0.16 could list/search after a compatibility symlink shim, but its message body pane remained blank on antiX/IceWM/VMware despite valid `notmuch show` output and WebKitGTK workarounds.
- Decision: Keep notmuch as the fast, lightweight sidecar search backend with database `/mail/SearchIndex/notmuch/default`, mail root `/mail/Mailstore`, `maildir.synchronize_flags=false`, and `index.decrypt=false`. Use the read-only localhost browser viewer `~/.local/bin/notmuch-browser-pilot` as the validated notmuch GUI for search/view in the pilot phase. At the time, Astroid was kept installed/configured as experimental only until its blank-body rendering issue was fixed or superseded.
- Consequence: This decision was later superseded the same day after the owner chose to retire Astroid entirely and replace the thread-oriented browser viewer with single-email mode. The notmuch backend, Evolution reply/send split, data-safety posture, and deferred 59G archive expansion remain in effect.

### 2026-07-04: Use Dynamic Post-Main-Archive Aggregate Delta for Future Betterbird Runs

- Status: accepted
- Context: The earlier 248-message delta guard became stale after new mail arrived; a later Fedora audit reported 249 post-main-archive candidates. The owner wants future runs to include every Betterbird source message absent from the original main archive/export, even if the commands are run days later. Email `Date:` headers are not reliable enough for this baseline because headers can be wrong, missing, duplicated, or timezone-shifted.
- Decision: Use `src/betterbird_post_archive_delta.py` for future delta work. The baseline is `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp/.conversion-state.sqlite`, corresponding to `maildirpp-archive-export-20260701-215204`, with 48,720 copied rows expected by default. Each run creates a timestamped RUN_ID aggregate snapshot, stages selected files under `post-main-archive-work/RUN_ID`, and converts to `betterbird-post-main-archive-maildirpp-RUN_ID`. Selection excludes baseline messages by exact source path/size/mtime, then relative path/size/mtime, then SHA256 fallback.
- Consequence: Future aggregate runs are not tied to a fixed count such as 248. A newer aggregate supersedes older post-main-archive delta accounts after validation, so older delta accounts should be disabled or removed from Evolution UI to avoid duplicate search results. Old delta files should not be deleted until backup and cleanup are explicitly planned.

### 2026-07-04: Keep Betterbird Post-Conversion Delta as a Separate Maildir++ Archive

- Status: accepted
- Context: After the first full Betterbird conversion, 248 newer Betterbird source messages were found outside the original conversion state. The owner chose to include all 248 candidates, including 8 same-Message-ID but different-content variants, to avoid losing potentially meaningful message variants. The original converted archive and the production mbsync `provider-live` tree were already separate validated objects.
- Decision: Convert the 248-message delta into its own canonical Maildir++ tree, transfer it independently with `maildirpp_transport.py`, restore it on antiX at `/mail/Mailstore/evolution/betterbird-delta-maildirpp-20260704`, and add it to Evolution as a separate `Maildir-format mail directories` account. Do not merge it into `/mail/Mailstore/evolution/local-maildir` or `/mail/Mailstore/mbsync/provider-live` during this phase.
- Consequence: The delta is usable in Evolution and fully reversible without modifying the 59G archive or live IMAP sync tree. Duplicate Message-ID variants may appear in search or folder views, but data preservation is prioritized. Any future merge must be a separate backed-up and tested task.

### 2026-07-01: Use Dedicated Maildir++ Archive Transport for Converted Betterbird Archive

- Status: accepted
- Context: The Betterbird maildir-lite archive was converted on Fedora into canonical Maildir++ at `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp`, hash verification passed, and the owner reported Evolution GUI validation including `mail_tagindustries_com_sg.Inbox` opening with 14,279 emails, successful HTML rendering, and no error popup.
- Decision: Implement `src/maildirpp_transport.py` as the official Python 3 standard-library-only transport for already-converted canonical Maildir++ archives. It uses split gzip tar parts, `manifest.json`, `inventory.jsonl`, per-part and whole-archive SHA256 verification, restored-tree hash verification, and Maildir++ layout inspection before packing and after restore.
- Consequence: The converted archive can be transferred to antiX directly into `/mail/Mailstore/evolution/local-maildir` without rerunning the maildir-lite converter on antiX. This archive remains separate from the live mbsync tree at `/mail/Mailstore/mbsync/provider-live`.

### 2026-06-28: Use a General Work Validation Ledger

- Status: accepted
- Context: Terminal-guided work often happens through command chunks that the owner runs in antiX, Fedora, or Windows, with output returned through `codex-input/pasted-text.txt`. Earlier mbsync work preserved important validated outcomes, but not every exact command-output pair.
- Decision: Maintain `docs/WORK_VALIDATION_LEDGER.md` as a topic-neutral durable ledger for future command chunks, pasted-output review, validation outcomes, failures, fixes, skipped steps, and superseded paths. The ledger must reference output/log sources and summarize key results without storing secrets or massive raw logs.
- Consequence: Future work on any topic can be audited by chunk/step and result, while historical work is backfilled only as honest summaries from confirmed project memory.

### 2026-06-27: Protect Provider-Live Controls from Stale Loop PID Files

- Status: accepted
- Context: The provider-live loop stores its process ID so the control command can report status and stop the loop. After a crash, reboot, or abnormal exit, an old PID file could theoretically point at an unrelated future process.
- Decision: Generated provider-live controls must verify that a saved PID belongs to `mbsync-provider-live-loop` before treating the loop as running or sending a stop signal. Stale PID files are reported as `stale_loop_pid` and ignored for process killing. The timeout wrapper also supports GNU `timeout --kill-after` with a fallback to plain `timeout`.
- Consequence: Future runs keep the same validated behavior while avoiding false running status and avoiding accidental signals to unrelated processes.

### 2026-06-27: Add Timeout and Stale-Lock Visibility to Provider-Live Auto-Sync

- Status: accepted
- Context: The owner asked what happens if a mailbox sync takes longer than the 180-second poll interval because of many emails or slow internet. The validated loop already runs sequentially and uses a lock to prevent overlap, but a hung `mbsync` could leave a stale lock or make status unclear.
- Decision: Keep the sequential loop, add a conservative default one-hour `timeout` wrapper around `mbsync` when the `timeout` command is available, write lock metadata at sync start, show `sync_timeout_seconds`, sync age, channel, pid, and pid liveness in `status`, and add `clear-stale-lock` for locks whose pid is no longer alive.
- Consequence: Slow syncs will not overlap with later loop passes or manual `sync-now`; long but healthy syncs can continue up to the timeout. Operators can distinguish an active sync from a stale lock and clear only the stale case.

### 2026-06-27: Preserve Exact Provider-Live Auto-Sync Reproduction Workflow

- Status: accepted
- Context: The provider-live auto-sync, Sent upload, log retention, and IceWM startup flow were validated through terminal chunks on antiX. The owner wanted the HTML guide, text guide, and helper script to reproduce the same result without rediscovering marker, backup, stop/start, or log-proof details.
- Decision: Default the provider marker to uppercase `PROVIDER`, make block replacement tolerate both old lowercase and verified uppercase markers, and add helper commands for preflight, refresh, validation, and log-rotation proof.
- Consequence: Future runs can use the helper or guide to reach the same final state: `provider-live-group` running, `paused=no`, `sync_lock=absent`, bounded logs, empty `tmp` directories, and the uppercase IceWM startup marker.

### 2026-06-27: Add Log Retention to Production mbsync Auto-Sync

- Status: accepted
- Context: The provider-live loop writes one daily auto log every time the VM runs. The owner wanted to prevent `/mail/Logs/mbsync-live` from growing indefinitely while preserving useful troubleshooting history.
- Decision: Keep the one-file-per-day auto log design, compress auto logs older than 2 days when `gzip` is available, delete auto logs older than 30 days, keep manual/validation logs for 90 days, and expose `logs` plus `cleanup-logs` through `mbsync-provider-live-control`.
- Consequence: Auto-sync remains lightweight and receive/send policy is unchanged, while log growth is bounded and visible through `status`.

### 2026-06-27: Enable Narrow Sent Upload for Production mbsync

- Status: accepted
- Context: The production `provider-live` setup was stable as receive-only, but the owner needed every outgoing Evolution sent/reply/forward copy uploaded back to IMAP Sent.
- Decision: Keep normal folders receive-only in `provider-live`, remove `Sent` from that channel's patterns, add `provider-live-sent-upload` mapping only `Sent <=> Sent` with `Sync PullNew PushNew`, `Create None`, `Remove None`, and `Expunge None`, and run both channels through `provider-live-group`. Configure Evolution's production identity to save sent copies into `TAG-Mustang_mbsync-Live/Sent`.
- Consequence: Sent copies now upload to remote `INBOX.Sent` while INBOX, Drafts, Trash, spam, Junk, and Archive remain protected from local-to-server push behavior. The auto-sync loop now targets `provider-live-group`.

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

- Git hosting provider: GitHub or GitLab
- Whether the Go browser service should start through IceWM startup or reviewed root-level runit service after antiX validation
- Packaging/install workflow for the Go browser service after antiX validation
- Next implementation milestone after the read-only Go notmuch browser service is validated
- Dependency installation policy beyond the current approved Python standard-library utilities, Go chi notmuch browser service, local vendored HTMX asset, and build-time compiled Tailwind CSS workflow
