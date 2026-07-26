# Notmuch Browser Multi-Source Validation

This directory preserves the exact privacy-limited operator evidence for the
multi-source, single-message, newest-first browser rollout.

Each numbered gate has:

- the exact executed batch under `batches/`;
- its complete privacy-reviewed terminal log under `logs/`;
- a machine-readable hash/result record under `records/`; and
- a matching summary row in `docs/WORK_VALIDATION_LEDGER.md`.

The stable runner executes only the ignored active batch at
`codex-output/notmuch-browser-operator/current.sh`. After the owner runs
`./scripts/notmuch_browser_operator_run.sh`, Codex must review the complete log,
promote it with `scripts/notmuch_browser_operator_record.sh`, manually verify
that no private mail or credential data is present, and commit/push the reviewed
success or failure before preparing the next gate.

Raw logs in this directory are deliberately limited to safe system state,
counts, hashes, HTTP statuses, and assertion results. Never record credentials,
configuration secrets, email bodies, headers, Message-IDs, capability tokens,
cookies, or private keys.

## Gate Index

| Gate | Result | Exact batch | Complete log | Record | Summary |
|---|---|---|---|---|---|
| 01 read-only preflight | success | `batches/01-read-only-preflight.sh` (`01a17773...`) | `logs/01-read-only-preflight.log` (`0b3a25a3...`) | `records/01-read-only-preflight.env` | Commit/upstream/cleanliness, scripts, XFS/free space, safe notmuch configuration, exact static source inventories/manifests, current indexed scope, installed runtime, user-runit services, localhost health, locks, and zero static temp files passed. No acknowledgement, indexing, lifecycle action, or mail/index mutation ran. |
| 02 exact-source acknowledgement | partial | `batches/02-exact-source-acknowledgement.sh` (`c1eea678...`) | `logs/02-exact-source-acknowledgement.log` (`99e549b4...`) | `records/02-exact-source-acknowledgement.env` | The intended write succeeded: exact pre/post manifests matched and private mode-600 marker `e17e3b45...` was created; config/ignore, health, locks, and services stayed healthy, with no indexing or lifecycle action. Manual review found the batch's greedy `sv status` parser labeled svlogd PIDs 2111/2110 as browser/index PIDs; actual service PIDs were 3761/3812. A corrected read-only identity audit is required before enrollment. |
| 03 corrected acknowledgement/identity audit | success | `batches/03-corrected-acknowledgement-identity-audit.sh` (`9b65bbaa...`) | `logs/03-corrected-acknowledgement-identity-audit.log` (`33c5b7c7...`) | `records/03-corrected-acknowledgement-identity-audit.env` | Read-only correction proved marker `e17e3b45...`, exact current source manifests, unchanged config/ignore, browser PID 3761 and index PID 3812 with distinct svlogd PIDs, correct executables/control command and runsv parents, provider PID 2310, loopback health, free 8876, and absent locks. No marker rewrite, indexing, lifecycle, config, or Maildir action ran. |
| 04 enrollment backup/capacity preflight | success | `batches/04-enrollment-backup-capacity-preflight.sh` (`7143b6bb...`) | `logs/04-enrollment-backup-capacity-preflight.log` (`1f4c0d3a...`) | `records/04-enrollment-backup-capacity-preflight.env` | Read-only checks proved 104,973,672 KiB free, a 36,700 KiB/six-file database with manifest `9237f034...`, zero prior enrollment backups/pointer, safe backup/log destinations, working exact config/tag/path/database backup commands, and a conservative 1,158,676 KiB requirement. Config, 1,659/2,872 health, and locks remained safe; no backup, indexing, lifecycle, config, marker, or Maildir write ran. |

Gate 01's 176-line raw log and exact batch passed automated credential-shape
scanning plus manual review for email addresses, Message-IDs, capability tokens,
cookies, credentials, private keys, headers, and message content.

Gate 02's 97-line raw log and exact batch passed the same privacy review. Its
partial result preserves a harness evidence-label defect, not a source,
configuration, service-health, or acknowledgement failure.

Gate 03's 71-line raw log and exact batch passed the same privacy review and
fully resolves Gate 02's evidence-label defect.

Gate 04's 68-line raw log and exact batch passed the same privacy review. Its
backup commands wrote only into a private temporary directory and removed that
directory before exit; the production backup destination and database were
untouched.
