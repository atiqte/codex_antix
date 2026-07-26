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

Gate 01's 176-line raw log and exact batch passed automated credential-shape
scanning plus manual review for email addresses, Message-IDs, capability tokens,
cookies, credentials, private keys, headers, and message content.
