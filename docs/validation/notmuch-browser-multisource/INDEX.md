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

No operator gate has been run for this rollout yet.
