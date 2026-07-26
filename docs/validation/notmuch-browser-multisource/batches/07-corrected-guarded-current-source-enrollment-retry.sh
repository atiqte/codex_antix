#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 07: corrected guarded enrollment retry with prefix-filtered path checks.
G6_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G6_COMMIT=1ab62eed1e1b54e928c6102c616a19f3216f506d
G6_BRANCH=atiqte/branch-codex
G6_MAIL_ROOT=/mail
G6_MAILSTORE=/mail/Mailstore
G6_CONFIG=/home/atiq/.config/notmuch/default/config
G6_DB=/mail/SearchIndex/notmuch/default
G6_STATE=/mail/AppData/notmuch-browser/source-enrollment
G6_LOG_DIR=/mail/Logs/notmuch-browser/source-enrollment
G6_BACKUP_ROOT=/mail/Backups/notmuch-browser
G6_BACKUP_POINTER="$G6_STATE/current-backup"
G6_MARKER="$G6_STATE/current-sources-acknowledged.env"
G6_HELPER="$G6_REPO/scripts/notmuch_browser_source_enroll.sh"
G6_BROWSER_CONTROL=/home/atiq/.local/bin/notmuch-browser-control
G6_INDEX_CONTROL=/home/atiq/.local/bin/notmuch-browser-index-control
G6_MBSYNC_CONTROL=/home/atiq/.local/bin/mbsync-provider-live-control
G6_MBSYNC_LOCK=/mail/AppData/isync/provider-live-loop/lock
G6_REFRESH_LOCK=/mail/AppData/notmuch-browser/index-refresh.lock
G6_GATE5_BATCH="$G6_REPO/docs/validation/notmuch-browser-multisource/batches/05-hardened-enrollment-final-audit.sh"
G6_GATE5_LOG="$G6_REPO/docs/validation/notmuch-browser-multisource/logs/05-hardened-enrollment-final-audit.log"
G6_GATE5_RECORD="$G6_REPO/docs/validation/notmuch-browser-multisource/records/05-hardened-enrollment-final-audit.env"
G6_GATE6_BATCH="$G6_REPO/docs/validation/notmuch-browser-multisource/batches/06-guarded-current-source-enrollment.sh"
G6_GATE6_LOG="$G6_REPO/docs/validation/notmuch-browser-multisource/logs/06-guarded-current-source-enrollment.log"
G6_GATE6_RECORD="$G6_REPO/docs/validation/notmuch-browser-multisource/records/06-guarded-current-source-enrollment.env"
G6_HELPER_SHA=fa3e0380a7ba3a9967acd9b6ce317841a848c3469ec3378b87591cf94f919060
G6_CONFIG_BEFORE_SHA=9fc4a9bdaf9c55c8036f8c27842a336a2198d5a6df086b2d2f9ba3d5479fabd7
G6_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G6_GATE5_BATCH_SHA=28bae373813c64cbc1d9593bdf79bd8318085dbf3f94b91b92b21d2623d96dcb
G6_GATE5_LOG_SHA=92b6a2002a3cd910833ac1cff3ee79869cd95bef93cc1a4a0748315c28c3b2ca
G6_GATE5_RECORD_SHA=aa15c246a64a6792a42f4262a39a5b3d9a5d1b8d36e0d8b42bb2f350cb7020c2
G6_GATE6_BATCH_SHA=176d3edd51c403a2152fec14b873585a044b77e6faa2333f75b1ceda8ffbdf3d
G6_GATE6_LOG_SHA=224adc9bebe302a3bfa18b326cb0e7855b20b539ac09558e52deb10a1cbdb417
G6_GATE6_RECORD_SHA=e99c87990c845fb84364bcede53e5bdf7679f90d5af11e061b582f37186b2d9f
G6_PRIOR_BACKUP=/mail/Backups/notmuch-browser/source-enrollment-20260726-231044
G6_PRIOR_FAILED_DB="$G6_PRIOR_BACKUP/notmuch-database.failed-20260726-232730"
G6_PRIOR_INVENTORY_SHA=7c539d54767f7f637b3345e5e363869c56c1cee7769738240d8e422bc355aba7
G6_PRIOR_FAILED_DB_MANIFEST_SHA=5a5fc006ea75187ab0228915e00e39ed2d3791da4c24b68a25abbfc084e33188
G6_MIN_FREE_KIB=83886080
G6_STATIC_INDEXED_FILES=48963
G6_ENROLL_STARTED=no
G6_HELPER_COMPLETED=no
G6_ENROLL_SUCCEEDED=no
G6_BACKUP=

g6_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g6_equal() {
  local label=$1
  local actual=$2
  local expected=$3
  if [[ "$actual" != "$expected" ]]; then
    printf 'status=blocked\nreason=%s mismatch\nactual=%s\nexpected=%s\n' \
      "$label" "$actual" "$expected" >&2
    exit 1
  fi
  printf '%s=%s\n' "$label" "$actual"
}

g6_service_summary() {
  local browser_status index_status mbsync_status
  browser_status=$("$G6_BROWSER_CONTROL" status 2>&1 || true)
  index_status=$("$G6_INDEX_CONTROL" status 2>&1 || true)
  mbsync_status=$("$G6_MBSYNC_CONTROL" status 2>&1 || true)
  if printf '%s\n' "$browser_status" | grep -Fqx 'server=running'; then
    printf '%s\n' recovery_browser_service=running
  else
    printf '%s\n' recovery_browser_service=not_running
  fi
  if printf '%s\n' "$index_status" | grep -Fqx 'loop=running'; then
    printf '%s\n' recovery_index_loop=running
  else
    printf '%s\n' recovery_index_loop=not_running
  fi
  if printf '%s\n' "$mbsync_status" | grep -Fqx 'loop=running'; then
    printf '%s\n' recovery_mbsync_loop=running
  else
    printf '%s\n' recovery_mbsync_loop=not_running
  fi
  if printf '%s\n' "$mbsync_status" | grep -Fqx 'paused=no'; then
    printf '%s\n' recovery_mbsync_paused=no
  else
    printf '%s\n' recovery_mbsync_paused=yes_or_unknown
  fi
}

g6_exit_report() {
  local rc=$?
  trap - EXIT
  if [[ "$rc" -ne 0 && "$G6_ENROLL_STARTED" == yes ]]; then
    set +e
    printf '%s\n' gate_07_failure_recovery_observation=begin
    if [[ "$G6_HELPER_COMPLETED" == yes &&
      "$G6_BACKUP" == "$G6_BACKUP_ROOT"/source-enrollment-[0-9]* &&
      -d "$G6_BACKUP/notmuch-database.before" ]]; then
      G6_ROLLBACK_STAMP=$(date +%Y%m%d-%H%M%S)
      G6_ROLLBACK_LOG="$G6_LOG_DIR/gate07-automatic-rollback-$G6_ROLLBACK_STAMP.log"
      "$G6_HELPER" rollback "$G6_BACKUP" > "$G6_ROLLBACK_LOG" 2>&1
      G6_ROLLBACK_RC=$?
      chmod 600 "$G6_ROLLBACK_LOG" 2>/dev/null || true
      printf 'automatic_postcheck_rollback_exit=%s\n' "$G6_ROLLBACK_RC"
      printf 'automatic_postcheck_rollback_log=%s\n' "$G6_ROLLBACK_LOG"
      printf 'automatic_postcheck_rollback_log_bytes=%s\n' \
        "$(wc -c < "$G6_ROLLBACK_LOG" | tr -d ' ')"
      printf 'automatic_postcheck_rollback_log_sha256=%s\n' \
        "$(sha256sum "$G6_ROLLBACK_LOG" | awk '{print $1}')"
    else
      printf '%s\n' automatic_postcheck_rollback=not_applicable
    fi
    if [[ -f "$G6_CONFIG" ]]; then
      printf 'recovery_config_sha256=%s\n' \
        "$(sha256sum "$G6_CONFIG" | awk '{print $1}')"
    fi
    if [[ -f "$G6_MARKER" ]]; then
      printf 'recovery_marker_sha256=%s\n' \
        "$(sha256sum "$G6_MARKER" | awk '{print $1}')"
    fi
    if [[ -s "$G6_BACKUP_POINTER" ]]; then
      printf 'recovery_backup_pointer_present=yes\n'
    else
      printf 'recovery_backup_pointer_present=no\n'
    fi
    g6_service_summary
    printf 'recovery_mbsync_lock=%s\n' \
      "$([[ -e "$G6_MBSYNC_LOCK" ]] && printf present || printf absent)"
    printf 'recovery_refresh_lock=%s\n' \
      "$([[ -e "$G6_REFRESH_LOCK" ]] && printf present || printf absent)"
    printf '%s\n' gate_07_failure_recovery_observation=end
  fi
  exit "$rc"
}
trap g6_exit_report EXIT

g6_wait_health() {
  local attempt payload
  for attempt in $(seq 1 30); do
    if payload=$(curl --silent --show-error --fail --max-time 5 \
      http://127.0.0.1:8765/healthz 2>/dev/null); then
      printf '%s\n' "$payload"
      return 0
    fi
    sleep 1
  done
  return 1
}

g6_wait_locks_absent() {
  local attempt
  for attempt in $(seq 1 300); do
    if [[ ! -e "$G6_MBSYNC_LOCK" && ! -e "$G6_REFRESH_LOCK" ]]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

g6_indexed_files() {
  local relative=$1
  local prefix="$G6_MAILSTORE/$relative/"
  notmuch --config="$G6_CONFIG" search --exclude=false --output=files \
    "path:$relative/**" |
    awk -v prefix="$prefix" 'index($0, prefix) == 1 { count++ } END { print count + 0 }'
}

printf '%s\n' 'gate=07-corrected-guarded-current-source-enrollment-retry'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_approved_paths_and_statuses_only'
printf '%s\n' 'authorized_backup_write=yes'
printf '%s\n' 'authorized_notmuch_database_mutation=yes'
printf '%s\n' 'authorized_notmuch_config_mutation=yes'
printf '%s\n' 'authorized_notmuch_tag_mutation=yes'
printf '%s\n' 'authorized_service_lifecycle=yes'
printf '%s\n' 'authorized_maildir_mutation=no'
printf '%s\n' 'automatic_failure_rollback=database_config_and_services'

for tool in git bash sh find findmnt df du stat sha256sum notmuch awk sed grep sort wc tr paste curl python3 ss date tee seq; do
  command -v "$tool" >/dev/null 2>&1 || g6_die "missing required command: $tool"
done

cd "$G6_REPO"
g6_equal repository_commit "$(git rev-parse HEAD)" "$G6_COMMIT"
g6_equal repository_branch "$(git branch --show-current)" "$G6_BRANCH"
g6_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G6_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g6_die "repository is not clean"
printf '%s\n' repository_clean=yes
g6_equal gate_05_batch_sha256 \
  "$(sha256sum "$G6_GATE5_BATCH" | awk '{print $1}')" "$G6_GATE5_BATCH_SHA"
g6_equal gate_05_log_sha256 \
  "$(sha256sum "$G6_GATE5_LOG" | awk '{print $1}')" "$G6_GATE5_LOG_SHA"
g6_equal gate_05_record_sha256 \
  "$(sha256sum "$G6_GATE5_RECORD" | awk '{print $1}')" "$G6_GATE5_RECORD_SHA"
grep -Fqx result=success "$G6_GATE5_RECORD" ||
  g6_die "Gate 05 result is not success"
grep -Fqx privacy_review=automated_and_manual_review_passed "$G6_GATE5_RECORD" ||
  g6_die "Gate 05 privacy review is incomplete"
printf '%s\n' gate_05_evidence=verified
g6_equal gate_06_batch_sha256 \
  "$(sha256sum "$G6_GATE6_BATCH" | awk '{print $1}')" "$G6_GATE6_BATCH_SHA"
g6_equal gate_06_log_sha256 \
  "$(sha256sum "$G6_GATE6_LOG" | awk '{print $1}')" "$G6_GATE6_LOG_SHA"
g6_equal gate_06_record_sha256 \
  "$(sha256sum "$G6_GATE6_RECORD" | awk '{print $1}')" "$G6_GATE6_RECORD_SHA"
grep -Fqx result=failed "$G6_GATE6_RECORD" ||
  g6_die "Gate 06 result is not failed"
grep -Fqx privacy_review=automated_and_manual_review_passed "$G6_GATE6_RECORD" ||
  g6_die "Gate 06 privacy review is incomplete"
printf '%s\n' gate_06_failed_evidence=verified

g6_equal enrollment_helper_sha256 \
  "$(sha256sum "$G6_HELPER" | awk '{print $1}')" "$G6_HELPER_SHA"
sh -n "$G6_HELPER"
g6_equal mail_fstype "$(findmnt -n -o FSTYPE --target "$G6_MAIL_ROOT")" xfs
G6_FREE_KIB=$(df -Pk "$G6_MAIL_ROOT" | awk 'NR == 2 {print $4}')
[[ "$G6_FREE_KIB" =~ ^[0-9]+$ ]] || g6_die "cannot read free space"
(( G6_FREE_KIB >= G6_MIN_FREE_KIB )) || g6_die "less than 80 GiB is free"
printf 'mail_free_kib_before=%s\n' "$G6_FREE_KIB"

[[ -f "$G6_CONFIG" && ! -L "$G6_CONFIG" ]] || g6_die "unsafe notmuch config"
[[ -f "$G6_MARKER" && ! -L "$G6_MARKER" ]] || g6_die "unsafe acknowledgement marker"
g6_equal config_sha256_before \
  "$(sha256sum "$G6_CONFIG" | awk '{print $1}')" "$G6_CONFIG_BEFORE_SHA"
g6_equal marker_sha256_before \
  "$(sha256sum "$G6_MARKER" | awk '{print $1}')" "$G6_MARKER_SHA"
g6_equal marker_mode_before "$(stat -c '%a' "$G6_MARKER")" 600
g6_equal new_ignore_before \
  "$(notmuch --config="$G6_CONFIG" config get new.ignore | LC_ALL=C sort | paste -sd' ' -)" \
  'betterbird-post-main-archive-maildirpp-20260704-205827 local-maildir provider-inbox-test test-maildir'
g6_equal new_tags_before \
  "$(notmuch --config="$G6_CONFIG" config get new.tags | LC_ALL=C sort | paste -sd' ' -)" \
  'inbox unread'
g6_equal prior_enrollment_backup_directories \
  "$(find "$G6_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'source-enrollment-*' -print | wc -l | tr -d ' ')" \
  1
g6_equal prior_enrollment_backup_pointer \
  "$(sed -n '1p' "$G6_BACKUP_POINTER")" "$G6_PRIOR_BACKUP"
g6_equal prior_enrollment_backup_mode "$(stat -c '%a' "$G6_PRIOR_BACKUP")" 700
g6_equal prior_enrollment_backup_pointer_mode \
  "$(stat -c '%a' "$G6_BACKUP_POINTER")" 600
g6_equal prior_enrollment_inventory_sha256 \
  "$(sha256sum "$G6_PRIOR_BACKUP/inventory.sha256" | awk '{print $1}')" \
  "$G6_PRIOR_INVENTORY_SHA"
(
  cd "$G6_PRIOR_BACKUP"
  sha256sum -c --status inventory.sha256
) || g6_die "prior enrollment backup checksum inventory failed"
[[ -d "$G6_PRIOR_FAILED_DB" ]] || g6_die "preserved Gate 06 enrolled database is missing"
G6_PRIOR_FAILED_DB_MANIFEST=$(
  (
    cd "$G6_PRIOR_FAILED_DB"
    find . -type f -printf '%P\t%s\t%T@\t%m\n' |
      LC_ALL=C sort |
      sha256sum |
      awk '{print $1}'
  )
)
g6_equal prior_failed_database_manifest_sha256 \
  "$G6_PRIOR_FAILED_DB_MANIFEST" "$G6_PRIOR_FAILED_DB_MANIFEST_SHA"
g6_equal prior_failed_database_regular_files \
  "$(find "$G6_PRIOR_FAILED_DB" -type f -print | wc -l | tr -d ' ')" 6
printf 'prior_failed_database_kib=%s\n' \
  "$(du -sk "$G6_PRIOR_FAILED_DB" | awk '{print $1}')"
printf '%s\n' prior_gate_06_backup_and_rollback_state=verified
[[ ! -e "$G6_MBSYNC_LOCK" ]] || g6_die "mbsync lock is active at preflight"
[[ ! -e "$G6_REFRESH_LOCK" ]] || g6_die "index refresh lock is active at preflight"
printf '%s\n' preflight_locks=absent

G6_BROWSER_STATUS=$("$G6_BROWSER_CONTROL" status)
printf '%s\n' "$G6_BROWSER_STATUS" | grep -Fqx server=running ||
  g6_die "browser service is not running"
G6_INDEX_STATUS=$("$G6_INDEX_CONTROL" status)
printf '%s\n' "$G6_INDEX_STATUS" | grep -Fqx loop=running ||
  g6_die "index loop is not running"
G6_MBSYNC_STATUS=$("$G6_MBSYNC_CONTROL" status)
printf '%s\n' "$G6_MBSYNC_STATUS" | grep -Fqx loop=running ||
  g6_die "mbsync loop is not running"
printf '%s\n' "$G6_MBSYNC_STATUS" | grep -Fqx paused=no ||
  g6_die "mbsync loop is paused"
printf '%s\n' preflight_browser_service=running
printf '%s\n' preflight_index_loop=running
printf '%s\n' preflight_mbsync_loop=running
printf '%s\n' preflight_mbsync_paused=no
G6_MESSAGES_BEFORE=$(notmuch --config="$G6_CONFIG" count '*')
G6_FILES_BEFORE=$(notmuch --config="$G6_CONFIG" count --output=files '*')
printf 'notmuch_messages_before=%s\n' "$G6_MESSAGES_BEFORE"
printf 'notmuch_files_before=%s\n' "$G6_FILES_BEFORE"

install -d -m 700 "$G6_LOG_DIR"
G6_STAMP=$(date +%Y%m%d-%H%M%S)
G6_HELPER_TRANSCRIPT="$G6_LOG_DIR/gate07-helper-$G6_STAMP.log"
G6_ENROLL_STARTED=yes
printf '%s\n' enrollment_execution=begin
printf 'enrollment_helper_transcript=%s\n' "$G6_HELPER_TRANSCRIPT"
set +e
"$G6_HELPER" enroll 2>&1 | tee "$G6_HELPER_TRANSCRIPT"
G6_PIPE=("${PIPESTATUS[@]}")
set -e
G6_HELPER_RC=${G6_PIPE[0]}
G6_TEE_RC=${G6_PIPE[1]}
chmod 600 "$G6_HELPER_TRANSCRIPT"
printf 'enrollment_helper_exit=%s\n' "$G6_HELPER_RC"
printf 'enrollment_helper_tee_exit=%s\n' "$G6_TEE_RC"
printf 'enrollment_helper_transcript_bytes=%s\n' \
  "$(wc -c < "$G6_HELPER_TRANSCRIPT" | tr -d ' ')"
printf 'enrollment_helper_transcript_sha256=%s\n' \
  "$(sha256sum "$G6_HELPER_TRANSCRIPT" | awk '{print $1}')"
[[ "$G6_TEE_RC" -eq 0 ]] || g6_die "enrollment helper transcript write failed"
[[ "$G6_HELPER_RC" -eq 0 ]] || g6_die "enrollment helper failed; automatic rollback was requested"
grep -Fqx status=source_enrollment_complete "$G6_HELPER_TRANSCRIPT" ||
  g6_die "enrollment completion marker is missing"
printf '%s\n' enrollment_execution=complete

G6_BACKUP=$(sed -n 's/^backup=//p' "$G6_HELPER_TRANSCRIPT" | tail -n 1)
G6_EVIDENCE=$(sed -n 's/^evidence=//p' "$G6_HELPER_TRANSCRIPT" | tail -n 1)
case "$G6_BACKUP" in
  "$G6_BACKUP_ROOT"/source-enrollment-[0-9]*) ;;
  *) g6_die "unsafe enrollment backup path" ;;
esac
G6_HELPER_COMPLETED=yes
g6_equal enrollment_backup_pointer "$(sed -n '1p' "$G6_BACKUP_POINTER")" "$G6_BACKUP"
g6_equal enrollment_backup_mode "$(stat -c '%a' "$G6_BACKUP")" 700
g6_equal enrollment_backup_pointer_mode "$(stat -c '%a' "$G6_BACKUP_POINTER")" 600
[[ -d "$G6_BACKUP/notmuch-database.before" ]] ||
  g6_die "backup database is missing"
[[ -f "$G6_BACKUP/notmuch-config.before" ]] ||
  g6_die "backup config is missing"
[[ -f "$G6_BACKUP/tags.before.batch-tag" ]] ||
  g6_die "backup tags are missing"
[[ -f "$G6_BACKUP/paths.before.txt" ]] ||
  g6_die "backup path inventory is missing"
[[ -f "$G6_BACKUP/inventory.sha256" ]] ||
  g6_die "backup checksum inventory is missing"
[[ -d "$G6_EVIDENCE" ]] || g6_die "enrollment evidence directory is missing"
[[ ! -e "$G6_BACKUP/notmuch-database.failed-enrollment" ]] ||
  g6_die "failed enrollment database exists after reported success"
(
  cd "$G6_BACKUP"
  sha256sum -c --status inventory.sha256
) || g6_die "backup checksum inventory failed"
g6_equal backup_config_sha256 \
  "$(sha256sum "$G6_BACKUP/notmuch-config.before" | awk '{print $1}')" \
  "$G6_CONFIG_BEFORE_SHA"
printf 'backup_database_kib=%s\n' \
  "$(du -sk "$G6_BACKUP/notmuch-database.before" | awk '{print $1}')"
printf 'backup_tag_dump_bytes=%s\n' "$(wc -c < "$G6_BACKUP/tags.before.batch-tag" | tr -d ' ')"
printf 'backup_tag_dump_sha256=%s\n' \
  "$(sha256sum "$G6_BACKUP/tags.before.batch-tag" | awk '{print $1}')"
printf 'backup_indexed_path_count=%s\n' "$(wc -l < "$G6_BACKUP/paths.before.txt" | tr -d ' ')"
printf 'backup_inventory_sha256=%s\n' \
  "$(sha256sum "$G6_BACKUP/inventory.sha256" | awk '{print $1}')"
printf '%s\n' backup_integrity=pass

g6_wait_locks_absent || g6_die "background locks did not settle after enrollment"
printf '%s\n' post_enrollment_locks=absent
G6_BROWSER_STATUS=$("$G6_BROWSER_CONTROL" status)
printf '%s\n' "$G6_BROWSER_STATUS" | grep -Fqx server=running ||
  g6_die "browser service was not restored"
G6_INDEX_STATUS=$("$G6_INDEX_CONTROL" status)
printf '%s\n' "$G6_INDEX_STATUS" | grep -Fqx loop=running ||
  g6_die "index loop was not restored"
G6_MBSYNC_STATUS=$("$G6_MBSYNC_CONTROL" status)
printf '%s\n' "$G6_MBSYNC_STATUS" | grep -Fqx loop=running ||
  g6_die "mbsync loop was not restored"
printf '%s\n' "$G6_MBSYNC_STATUS" | grep -Fqx paused=no ||
  g6_die "mbsync pause state was not restored"
printf '%s\n' post_browser_service=running
printf '%s\n' post_index_loop=running
printf '%s\n' post_mbsync_loop=running
printf '%s\n' post_mbsync_paused=no

g6_equal new_ignore_after \
  "$(notmuch --config="$G6_CONFIG" config get new.ignore | paste -sd' ' -)" \
  'betterbird-post-main-archive-maildirpp-20260704-205827'
g6_equal new_tags_after \
  "$(notmuch --config="$G6_CONFIG" config get new.tags | LC_ALL=C sort | paste -sd' ' -)" \
  'inbox unread'
g6_equal marker_sha256_after \
  "$(sha256sum "$G6_MARKER" | awk '{print $1}')" "$G6_MARKER_SHA"
printf 'config_sha256_after=%s\n' "$(sha256sum "$G6_CONFIG" | awk '{print $1}')"

g6_equal indexed_evolution_local_maildir_files \
  "$(g6_indexed_files evolution/local-maildir)" 48564
g6_equal indexed_evolution_betterbird_delta_files \
  "$(g6_indexed_files evolution/betterbird-delta-maildirpp-20260704)" 247
g6_equal indexed_mbsync_provider_inbox_test_files \
  "$(g6_indexed_files mbsync/provider-inbox-test)" 148
g6_equal indexed_evolution_test_maildir_files \
  "$(g6_indexed_files evolution/test-maildir)" 4
g6_equal indexed_evolution_provider_live_archive_files \
  "$(g6_indexed_files evolution/provider-live-archive)" 0
G6_PROVIDER_LIVE_FILES=$(g6_indexed_files mbsync/provider-live)
printf 'indexed_mbsync_provider_live_files=%s\n' "$G6_PROVIDER_LIVE_FILES"
G6_MESSAGES_AFTER=$(notmuch --config="$G6_CONFIG" count '*')
G6_FILES_AFTER=$(notmuch --config="$G6_CONFIG" count --output=files '*')
[[ "$G6_MESSAGES_AFTER" =~ ^[0-9]+$ && "$G6_FILES_AFTER" =~ ^[0-9]+$ ]] ||
  g6_die "invalid post-enrollment notmuch counts"
(( G6_FILES_AFTER >= G6_STATIC_INDEXED_FILES )) ||
  g6_die "post-enrollment file count is below the required static source total"
printf 'notmuch_messages_after=%s\n' "$G6_MESSAGES_AFTER"
printf 'notmuch_files_after=%s\n' "$G6_FILES_AFTER"

G6_HEALTH=$(g6_wait_health) || g6_die "browser health did not recover"
python3 - "$G6_HEALTH" "$G6_STATIC_INDEXED_FILES" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
minimum_files = int(sys.argv[2])
if payload.get("ok") is not True:
    raise SystemExit("status=blocked\nreason=health ok is not true")
if payload.get("read_only") is not True:
    raise SystemExit("status=blocked\nreason=health read_only is not true")
if payload.get("mail_mutation") is not False:
    raise SystemExit("status=blocked\nreason=health mail_mutation is not false")
messages = payload.get("messages")
files = payload.get("files")
if not isinstance(messages, int) or messages < 1:
    raise SystemExit("status=blocked\nreason=invalid health message count")
if not isinstance(files, int) or files < minimum_files:
    raise SystemExit("status=blocked\nreason=health file count is below enrolled sources")
print("health_ok=true")
print("health_read_only=true")
print("health_mail_mutation=false")
print(f"health_messages={messages}")
print(f"health_files={files}")
PY

G6_ENROLL_SUCCEEDED=yes
printf '%s\n' rollback_invoked=no
printf '%s\n' backup_created=yes
printf '%s\n' acknowledgement_marker_rewritten=no
printf '%s\n' notmuch_new_executed_by_gate=yes
printf '%s\n' notmuch_config_changed=yes
printf '%s\n' notmuch_tags_changed=yes
printf '%s\n' service_lifecycle_action_executed=yes
printf '%s\n' maildir_mutation_by_enrollment=no
printf 'mail_free_kib_after=%s\n' "$(df -Pk "$G6_MAIL_ROOT" | awk 'NR == 2 {print $4}')"
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_07_corrected_guarded_current_source_enrollment_retry_pass
