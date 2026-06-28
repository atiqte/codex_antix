# Work Validation Ledger

This file is the durable, topic-neutral record for terminal-guided work, validation-heavy work, and operator-run command chunks. It is not limited to mbsync.

Use this ledger when Codex gives command chunks for the owner to run on another machine, when the owner returns terminal output through `codex-input/pasted-text.txt`, or when a task needs a clear record of what succeeded, failed, was skipped, or was superseded.

## Rules

- Do not store passwords, app passwords, tokens, private keys, or unredacted configs.
- Do not paste massive terminal logs into this file. Reference the source path and summarize the important result.
- Record failed chunks and the fix that replaced them. Do not erase failures.
- Mark obsolete work as `superseded`, not deleted.
- Treat `codex-input/pasted-text.txt` as temporary input. This ledger is the durable record.

## Result Values

- `success`: command/action completed and matched expectations.
- `failed`: command/action did not complete or produced an unsafe/unusable result.
- `partial`: command/action produced useful output but required a workaround or follow-up.
- `skipped`: command/action was intentionally not run.
- `superseded`: command/action was valid earlier but later replaced by a better or final path.

## Future Session Template

For each future command chunk or validation step, add a row to the active ledger table.

| Date | Topic | Chunk/Step | Command or Action | Output Source | Result | Notes | Follow-up |
|---|---|---|---|---|---|---|---|
| YYYY-MM-DD | Short topic name | Chunk N or named step | Brief command/action summary | `codex-input/pasted-text.txt`, log path, or doc path | success/failed/partial/skipped/superseded | Key observed result, redacted if needed | Next command, fix, or none |

Recommended minimum fields for each topic:

- Work topic
- Environment
- Operator machine
- Command chunk ID
- Pasted output filename or log path
- Result value
- Decision or fix applied

## Active Ledger

Add new work here first. Move or summarize old rows only when the table becomes too large to scan.

| Date | Topic | Chunk/Step | Command or Action | Output Source | Result | Notes | Follow-up |
|---|---|---|---|---|---|---|---|
| 2026-06-28 | General workflow | Add validation ledger | Create topic-neutral ledger and wire it into project memory | `docs/WORK_VALIDATION_LEDGER.md` | success | Ledger added for all future terminal-guided work; historical exact per-chunk reconstruction remains unavailable. Path inspection, `git diff --check`, secret-oriented scan, and unit tests passed. | Use this ledger in future sessions. |

## Historical Backfill

These rows summarize confirmed milestones from existing project memory. They are not a complete verbatim reconstruction of every command chunk and pasted terminal response.

| Date | Topic | Chunk/Step | Command or Action | Output Source | Result | Notes | Follow-up |
|---|---|---|---|---|---|---|---|
| 2026-06-23 | Project memory | Initial setup | Create repository memory, workflow docs, and end-of-session commit/push policy | `docs/CHANGELOG.md`, `docs/DECISIONS.md` | success | Markdown memory system established. | Keep memory current after meaningful work. |
| 2026-06-24 | Betterbird conversion | Converter implementation | Add standard-library Betterbird maildir-lite to Maildir++ converter and tests | `docs/CHANGELOG.md`, `tests/` | success | Converter remains dry-run-first and dependency-free. | Validate on antiX with staged Betterbird data. |
| 2026-06-25 | Betterbird profile transport | Transport implementation | Add pack, split, verify, unpack, and verify-tree utility plus guide | `docs/CHANGELOG.md`, `docs/BETTERBIRD_PROFILE_TRANSPORT_GUIDE.txt` | success | Tool uses split gzip tar parts and manifest/inventory verification. | Run real Fedora to antiX transfer. |
| 2026-06-26 | Evolution Flatpak | GUI mail client setup | Validate Evolution Flatpak 3.60.2, `/mail` app data, launcher, and Maildir test account | `docs/PROJECT_STATE.md`, `docs/EVOLUTION_FLATPAK_ANTIX_GUIDE.txt` | success | Evolution reads Maildir with `BackendName=maildir`; user-level IceWM launcher documented. | Use Evolution as GUI path for validated Maildir trees. |
| 2026-06-27 | mbsync INBOX test | Discovery/install/layout/config | Install/use APT `isync`/`mbsync 1.5.1`, create isolated INBOX test layout, and write deletion-safe config | `docs/PROJECT_STATE.md`, `docs/MBSYNC_ANTIX_GUIDE.txt` | success | Layout used `/mail/Mailstore/mbsync/provider-inbox-test`; config used `Sync PullNew`, `Remove None`, `Expunge None`. | Keep INBOX test tree as validation account. |
| 2026-06-27 | mbsync INBOX test | Dry-run | Run `mbsync --dry-run -V provider-inbox` on empty test Maildir | `docs/PROJECT_STATE.md` | partial | isync 1.5.1 hit an assertion on the empty test Maildir. Safety was reviewed before continuing. | Proceeded with logged real pull after confirming target was empty and deletion policy was safe. |
| 2026-06-27 | mbsync INBOX test | First real pull and Evolution read test | Pull INBOX, inspect counts/files/logs, then read/search in Evolution | `docs/PROJECT_STATE.md`, `docs/MBSYNC_ANTIX_GUIDE.txt` | success | 144 INBOX messages pulled; Evolution read the tree as `BackendName=maildir`; post-Evolution sync had no duplicate flood. | Snapshot config/logs and plan production promotion. |
| 2026-06-27 | IMAP cleanup | Remove unwanted folders | Verify empty `FARSUK` and `BASUNDHARA`, then remove them from server | `docs/PROJECT_STATE.md`, `docs/CHANGELOG.md` | success | Folder cleanup made exact seven-folder production promotion practical. | Use explicit production folder list. |
| 2026-06-27 | mbsync production | Provider-live setup | Create `/mail/Mailstore/mbsync/provider-live`, state/log paths, and explicit folder patterns | `docs/PROJECT_STATE.md`, `docs/MBSYNC_ANTIX_GUIDE.txt` | success | First provider-live pull downloaded 163 messages; second pull had zero delta and no duplicate flood; `tmp` stayed empty. | Add Evolution production account and SMTP. |
| 2026-06-27 | Evolution production | SMTP and GUI validation | Read/search provider-live in Evolution, send SMTP tests to Gmail, pull replies | `docs/PROJECT_STATE.md` | success | After SMTP/Gmail replies, provider-live reached 170 messages; Evolution used `BackendName=maildir`. | Configure Sent upload. |
| 2026-06-27 | mbsync Sent upload | Sent-only push channel | Add `provider-live-sent-upload` with `Sync PullNew PushNew` only for Sent | `docs/PROJECT_STATE.md`, `docs/DECISIONS.md` | success | Controlled Sent upload changed remote `INBOX.Sent` from 4 to 5; second Sent sync had zero delta; later auto upload reached 6. | Keep normal folders receive-only. |
| 2026-06-27 | mbsync auto-sync | Loop/startup validation | Add 180-second provider-live loop, control commands, and IceWM startup block | `docs/PROJECT_STATE.md`, `docs/MBSYNC_ANTIX_GUIDE.txt` | success | Final audit showed loop running, `provider-live-group`, exit 0, no lock left behind, and empty `tmp` directories. | Monitor with `mbsync-provider-live-control status`. |
| 2026-06-27 | mbsync log retention | Cleanup proof | Add log retention and prove compression/delete/keep behavior with fake logs | `docs/PROJECT_STATE.md`, `docs/DECISIONS.md` | success | Auto logs compress after 2 days, delete after 30 days; manual logs kept for 90 days; status shows log usage. | Use `logs` and `cleanup-logs`. |
| 2026-06-27 | mbsync slow-sync safety | Timeout and stale-lock proof | Add timeout wrapper, sync-age visibility, stale lock clearing, and stale loop PID protection | `docs/PROJECT_STATE.md`, `codex-input/pasted-text.txt` | success | Fake stale lock showed `sync_age_seconds=600` and `sync_pid_alive=no`; clear succeeded; sync-now and restarted loop exited 0. | Use `clear-stale-lock` only when pid is not alive. |
| 2026-06-28 | mbsync guide hardening | Start Here section | Add clear fresh setup command sequence and reference-only config labels | `docs/MBSYNC_ANTIX_GUIDE.txt`, `docs/MBSYNC_ANTIX_GUIDE.html` | success | Future readers start from INBOX validation, then production, Evolution checks, and auto-sync validation. | Follow guide from `Start Here: Fresh Setup`. |
