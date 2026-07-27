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
| 05 hardened enrollment final audit | success | `batches/05-hardened-enrollment-final-audit.sh` (`28bae373...`) | `logs/05-hardened-enrollment-final-audit.log` (`92b6a200...`) | `records/05-hardened-enrollment-final-audit.env` | Pushed helper `c2a0dd3b...` had the required restore/wait/complete/trap order and rollback regression. Gate 04 evidence, exact marker/config, all five source counts/manifests, XFS/free space, zero prior enrollment backups, browser/index/mbsync state, localhost health, and absent locks passed. No backup, indexing, lifecycle, config, marker, or Maildir write ran. |
| 06 guarded current-source enrollment | failed | `batches/06-guarded-current-source-enrollment.sh` (`176d3edd...`) | `logs/06-guarded-current-source-enrollment.log` (`224adc9b...`) | `records/06-guarded-current-source-enrollment.env` | The helper completed all three index stages and proved exact prefix-filtered parity for 48,564 local, 247 delta, 148 provider-test, four Evolution-test, and zero provider-archive paths; backup integrity and service/config restoration passed. The outer harness then falsely expected `notmuch count --output=files path:...` to equal source paths, but it returned 49,037 because that mode includes duplicate files outside the matching source. Automatic rollback succeeded, restoring config and the 1,659/2,872 live database/services; the 741,256 KiB enrolled database was preserved. |
| 07 corrected guarded enrollment retry | success | `batches/07-corrected-guarded-current-source-enrollment-retry.sh` (`0dcaf1ee...`) | `logs/07-corrected-guarded-current-source-enrollment-retry.log` (`107c1431...`) | `records/07-corrected-guarded-current-source-enrollment-retry.env` | The retry pinned Gate 06 failure/rollback evidence and used exact prefix-filtered file checks. All index stages, backup integrity, five source parities/counts, one-value ignore, live defaults, restored services, absent locks, and read-only health passed. Production now has 31,418 unique messages and 51,588 indexed files; rollback was not invoked and Maildir was not mutated by enrollment. |
| 08 multi-source candidate clean build and isolated validation | failed | `batches/08-multisource-candidate-clean-build-and-isolated-validation.sh` (`6643d351...`) | `logs/08-multisource-candidate-clean-build-and-isolated-validation.log` (`307828c9...`) | `records/08-multisource-candidate-clean-build-and-isolated-validation.env` | Repository, Gate 07 evidence, build script, production/config/marker identities, final ignore value, and free candidate port passed. The first production-listener assertion then stopped because backslash-escaped double quotes were invalid inside its single-quoted `awk` program. No candidate root, build, process, pointer, or production change occurred; production remained healthy and the enrolled index remained 31,418/51,588. |
| 09 corrected multi-source candidate clean build and isolated validation retry | failed | `batches/09-corrected-multisource-candidate-clean-build-and-isolated-validation-retry.sh` (`13b1abef...`) | `logs/09-corrected-multisource-candidate-clean-build-and-isolated-validation-retry.log` (`daa82e77...`) | `records/09-corrected-multisource-candidate-clean-build-and-isolated-validation-retry.env` | The clean build, deterministic generation, Go checks, 75 Python tests, binary identity, candidate start/health, four nonempty source checks, and empty archive check passed. `test-maildir` then returned zero rows even though direct path-only notmuch checks prove four logical messages/four exact indexed paths. Diagnosis showed scoped default search incorrectly changed special all-mail query `*` to `(*) and path:...`; notmuch returned zero for the untagged test messages. Failure cleanup stopped the candidate and freed 8876; production/index remained unchanged. |
| 10 scoped match-all fix candidate clean build and isolated validation | success | `batches/10-scoped-match-all-fix-candidate-clean-build-and-isolated-validation.sh` (`95e8f140...`) | `logs/10-scoped-match-all-fix-candidate-clean-build-and-isolated-validation.log` (`086c0fd5...`) | `records/10-scoped-match-all-fix-candidate-clean-build-and-isolated-validation.env` | Pinned prior evidence, complete reproducible build/tests, exact corrected binary `26967a5d...`, read-only candidate health, source catalog, individual newest-first/unique/date rows, exact four-row test-maildir result, empty archive, invalid-folder rejection, security/assets/routes/temp, and unchanged production all passed. Candidate PID 7522 is retained only on 127.0.0.1:8876 under pointer `d8e111ca...` for GUI review. |
| 11 responsive result-layout candidate clean build and isolated validation | success; manual GUI follow-up rejected | `batches/11-responsive-result-layout-candidate-clean-build-and-isolated-validation.sh` (`c83a3690...`) | `logs/11-responsive-result-layout-candidate-clean-build-and-isolated-validation.log` (`4fa2fb3b...`) | `records/11-responsive-result-layout-candidate-clean-build-and-isolated-validation.env` | The complete build/tests, exact responsive binary `5269c533...`, read-only candidate health, all approved source/search/date contracts, exact four-row test-maildir result, security/assets/routes/temp, and unchanged production passed. Candidate PID 32185 was retained only on 127.0.0.1:8876 under pointer `ae42160e...`; Gate 12 later identity-stopped it and preserved its files/pointer. The owner confirmed the corrected dates no longer overlap senders, but rejected the separate full-message new-tab scroll behavior: the relative-positioned viewport-height sidebar moved upward with the document and exposed the background below it. Gate 11 remains an automated success with a failed manual GUI follow-up; it must not be installed. |
| 12 sticky-sidebar candidate clean build and isolated validation | success; antiX GUI PASS | `batches/12-sticky-sidebar-candidate-clean-build-and-isolated-validation.sh` (`6976acdf...`) | `logs/12-sticky-sidebar-candidate-clean-build-and-isolated-validation.log` (`0d90892a...`) | `records/12-sticky-sidebar-candidate-clean-build-and-isolated-validation.env` | Pinned Gate 11 evidence, identity-stopped only its rejected process while preserving its files/pointer, and clean-built exact corrected binary `4f33c407...`. Desktop sticky/top/100dvh and mobile fixed CSS passed both repository and served-byte checks. Read-only 31,420/51,590 health, all six source/search/date contracts, exact four-row test-maildir result, empty archive, invalid-folder rejection, security/assets/routes/temp, and unchanged production passed. The owner then reported `antiX Gate 12 sticky sidebar GUI: PASS` after the prescribed hard-refresh, long-message new-tab top/middle/bottom scroll, and collapse/expand checks. PID 79328 remains retained only on 127.0.0.1:8876 under pointer `ccfc7295...` for later Windows review. |

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

Gate 05's 78-line raw log and exact batch passed the same privacy review. It
validated the fail-closed restoration order against unchanged production state
and exact acknowledged sources.

Gate 06's 125-line raw log and exact batch passed the same privacy review. Its
failure is a post-enrollment harness assertion defect, not an indexing/parity
failure. The automatic rollback and later direct audit restored and verified
the original live state before any retry.

Gate 07's 142-line raw log and exact batch passed the same privacy review. It
completed the corrected retry and left the enrolled database, exact final
configuration, rollback backups, and background services healthy.

Gate 08's complete 36-line raw log and exact batch passed the same privacy
review. It preserves a command-harness quoting failure: the malformed `awk`
program stopped before candidate directory creation, clean build, candidate
start, HTTP validation, or pointer creation. Direct post-failure checks found no
candidate root or pointer, zero port-8876 listeners, healthy production, and the
unchanged enrolled 31,418-message/51,588-file index.

Gate 09's complete 182-line raw log and exact batch passed the same privacy
review. It exposed a real source-search defect after the build and candidate
runtime passed: wrapping notmuch's special top-level `*` as `(*)` changed its
meaning when combined with a path term. The four indexed, untagged test messages
therefore produced an empty GUI result. The retained failed candidate files are
private; its process was identity-stopped, no pointer was published, and port
8876 was freed.

Gate 10's complete 209-line raw log and exact batch passed the same privacy
review. It proved the correction against every approved source and retained the
exact candidate for manual antiX and Windows GUI acceptance. The previous failed
candidate directory remains preserved, the shared candidate root was tightened
to mode 700, production stayed on 8765 with its old binary, and no mail, tags,
index, or configuration were mutated.

Gate 11's complete 216-line raw log and exact 534-line batch passed automated
credential-shape scanning plus manual review for email addresses, Message-IDs,
message URLs, capability tokens, cookies, credentials, private keys, headers,
and message content. The automated gate proved the responsive result layout and
retained the candidate without production mutation. Subsequent owner screenshot
review exposed a different full-message scroll defect, so this candidate is
preserved as rejected manual-GUI evidence and must be superseded by a new
isolated candidate.

Gate 12's complete 248-line raw log and exact 643-line batch passed the same
automated and manual privacy review. It stopped only the exact Gate 11 process,
preserved that rejected candidate's files and pointer, clean-built and retained
the sticky-sidebar correction, and repeated the complete source, ordering, date,
security, route, temp, production-isolation, and read-only contracts. No mail,
tags, notmuch index, configuration, or production binary was changed.
