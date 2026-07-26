#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 05: final read-only audit of the hardened enrollment helper and live state.
G5_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G5_COMMIT=1297797a418469db7e3ab848636d74cfc73ea5b3
G5_BRANCH=atiqte/branch-codex
G5_MAIL_ROOT=/mail
G5_MAILSTORE=/mail/Mailstore
G5_CONFIG=/home/atiq/.config/notmuch/default/config
G5_STATE=/mail/AppData/notmuch-browser/source-enrollment
G5_BACKUP_ROOT=/mail/Backups/notmuch-browser
G5_BACKUP_POINTER="$G5_STATE/current-backup"
G5_MARKER="$G5_STATE/current-sources-acknowledged.env"
G5_HELPER="$G5_REPO/scripts/notmuch_browser_source_enroll.sh"
G5_BROWSER_CONTROL=/home/atiq/.local/bin/notmuch-browser-control
G5_INDEX_CONTROL=/home/atiq/.local/bin/notmuch-browser-index-control
G5_MBSYNC_CONTROL=/home/atiq/.local/bin/mbsync-provider-live-control
G5_GATE4_BATCH="$G5_REPO/docs/validation/notmuch-browser-multisource/batches/04-enrollment-backup-capacity-preflight.sh"
G5_GATE4_LOG="$G5_REPO/docs/validation/notmuch-browser-multisource/logs/04-enrollment-backup-capacity-preflight.log"
G5_GATE4_RECORD="$G5_REPO/docs/validation/notmuch-browser-multisource/records/04-enrollment-backup-capacity-preflight.env"
G5_HELPER_SHA=c2a0dd3b19d29b0a65d43e8afd188ae7ca30866bc9ee7aab8fe956f0fdd1686e
G5_CONFIG_SHA=9fc4a9bdaf9c55c8036f8c27842a336a2198d5a6df086b2d2f9ba3d5479fabd7
G5_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G5_GATE4_BATCH_SHA=7143b6bb0c8494a523ac981d1d4e56d6afcdb3b8fd1d735b37c85a94ccbbb500
G5_GATE4_LOG_SHA=1f4c0d3adc3bc1e1f9709dff36a5772d19acc4eec54f19fa733976f7447219f1
G5_GATE4_RECORD_SHA=ee7a468497fb726c9ec742a271043c50c3c7b76b10bc042d95e671b9346a76a1
G5_MIN_FREE_KIB=83886080

g5_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g5_equal() {
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

g5_message_count() {
  find "$G5_MAILSTORE/$1" -type f \
    \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    wc -l |
    tr -d ' '
}

g5_source_manifest() {
  (
    cd "$G5_MAILSTORE/$1"
    find . -type f \( -path '*/cur/*' -o -path '*/new/*' \) \
      -printf '%P\t%s\t%T@\t%m\n' |
      LC_ALL=C sort |
      sha256sum |
      awk '{print $1}'
  )
}

g5_source_key() {
  printf '%s' "$1" | tr '/.-' '___'
}

g5_check_source() {
  local relative=$1
  local expected_count=$2
  local expected_manifest=$3
  local key count manifest links
  key=$(g5_source_key "$relative")
  [[ -d "$G5_MAILSTORE/$relative" && ! -L "$G5_MAILSTORE/$relative" ]] ||
    g5_die "unsafe source: $relative"
  count=$(g5_message_count "$relative")
  manifest=$(g5_source_manifest "$relative")
  links=$(find "$G5_MAILSTORE/$relative" -type l -print | wc -l | tr -d ' ')
  g5_equal "source_${key}_message_paths" "$count" "$expected_count"
  g5_equal "source_${key}_manifest_sha256" "$manifest" "$expected_manifest"
  g5_equal "source_${key}_symlinks" "$links" 0
  grep -Fqx "${key}_message_paths=$expected_count" "$G5_MARKER" ||
    g5_die "acknowledgement count missing for $relative"
  grep -Fqx "${key}_manifest_sha256=$expected_manifest" "$G5_MARKER" ||
    g5_die "acknowledgement manifest missing for $relative"
}

printf '%s\n' 'gate=05-read-only-hardened-enrollment-final-audit'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_paths_and_statuses_only'
printf '%s\n' 'authorized_production_write=none'

for tool in git bash sh find findmnt df stat sha256sum notmuch awk sed grep sort wc tr paste curl python3 ss date; do
  command -v "$tool" >/dev/null 2>&1 || g5_die "missing required command: $tool"
done

cd "$G5_REPO"
g5_equal repository_commit "$(git rev-parse HEAD)" "$G5_COMMIT"
g5_equal repository_branch "$(git branch --show-current)" "$G5_BRANCH"
g5_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G5_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g5_die "repository is not clean"
printf '%s\n' repository_clean=yes
g5_equal gate_04_batch_sha256 \
  "$(sha256sum "$G5_GATE4_BATCH" | awk '{print $1}')" "$G5_GATE4_BATCH_SHA"
g5_equal gate_04_log_sha256 \
  "$(sha256sum "$G5_GATE4_LOG" | awk '{print $1}')" "$G5_GATE4_LOG_SHA"
g5_equal gate_04_record_sha256 \
  "$(sha256sum "$G5_GATE4_RECORD" | awk '{print $1}')" "$G5_GATE4_RECORD_SHA"
grep -Fqx 'result=success' "$G5_GATE4_RECORD" ||
  g5_die "Gate 04 result is not success"
grep -Fqx 'privacy_review=automated_and_manual_review_passed' "$G5_GATE4_RECORD" ||
  g5_die "Gate 04 privacy review is incomplete"
printf '%s\n' gate_04_evidence=verified

g5_equal enrollment_helper_sha256 \
  "$(sha256sum "$G5_HELPER" | awk '{print $1}')" "$G5_HELPER_SHA"
sh -n "$G5_HELPER"
g5_equal restoration_wait_function_count \
  "$(grep -c '^wait_for_restored_service_state() {$' "$G5_HELPER")" 1
g5_equal restoration_status_function_count \
  "$(grep -c '^service_state_matches_capture() {$' "$G5_HELPER")" 1
G5_RESTORE_LINE=$(grep -n '^  restore_service_state$' "$G5_HELPER" | tail -n 1 | cut -d: -f1)
G5_WAIT_LINE=$(grep -n '^  wait_for_restored_service_state ||$' "$G5_HELPER" | cut -d: -f1)
G5_COMPLETE_LINE=$(grep -n '^  ENROLL_COMPLETE=yes$' "$G5_HELPER" | tail -n 1 | cut -d: -f1)
G5_TRAP_OFF_LINE=$(grep -n '^  trap - EXIT HUP INT TERM$' "$G5_HELPER" | cut -d: -f1)
for value in "$G5_RESTORE_LINE" "$G5_WAIT_LINE" "$G5_COMPLETE_LINE" "$G5_TRAP_OFF_LINE"; do
  [[ "$value" =~ ^[0-9]+$ ]] || g5_die "cannot resolve restoration contract ordering"
done
(( G5_RESTORE_LINE < G5_WAIT_LINE &&
   G5_WAIT_LINE < G5_COMPLETE_LINE &&
   G5_COMPLETE_LINE < G5_TRAP_OFF_LINE )) ||
  g5_die "restoration contract order is unsafe"
grep -Fq 'die "background service state did not recover after enrollment"' "$G5_HELPER" ||
  g5_die "restoration failure is not fail-closed"
grep -Fq 'def test_failed_service_restore_rolls_back_database' \
  "$G5_REPO/tests/test_notmuch_browser_source_enroll.py" ||
  g5_die "service restoration rollback regression is missing"
printf '%s\n' restoration_contract=restore_then_wait_then_complete_then_disable_trap
printf '%s\n' restoration_failure_policy=database_and_config_rollback

g5_equal mail_fstype "$(findmnt -n -o FSTYPE --target "$G5_MAIL_ROOT")" xfs
G5_FREE_KIB=$(df -Pk "$G5_MAIL_ROOT" | awk 'NR == 2 {print $4}')
[[ "$G5_FREE_KIB" =~ ^[0-9]+$ ]] || g5_die "cannot read free space"
(( G5_FREE_KIB >= G5_MIN_FREE_KIB )) || g5_die "less than 80 GiB is free"
printf 'mail_free_kib=%s\n' "$G5_FREE_KIB"

[[ -f "$G5_CONFIG" && ! -L "$G5_CONFIG" ]] || g5_die "unsafe notmuch config"
[[ -f "$G5_MARKER" && ! -L "$G5_MARKER" ]] || g5_die "unsafe acknowledgement marker"
g5_equal config_sha256 "$(sha256sum "$G5_CONFIG" | awk '{print $1}')" "$G5_CONFIG_SHA"
g5_equal marker_sha256 "$(sha256sum "$G5_MARKER" | awk '{print $1}')" "$G5_MARKER_SHA"
g5_equal marker_mode "$(stat -c '%a' "$G5_MARKER")" 600
g5_equal marker_owner "$(stat -c '%U' "$G5_MARKER")" atiq
g5_equal database_path \
  "$(notmuch --config="$G5_CONFIG" config get database.path)" \
  /mail/SearchIndex/notmuch/default
g5_equal database_mail_root \
  "$(notmuch --config="$G5_CONFIG" config get database.mail_root)" \
  "$G5_MAILSTORE"
g5_equal synchronize_flags \
  "$(notmuch --config="$G5_CONFIG" config get maildir.synchronize_flags)" false
g5_equal index_decrypt \
  "$(notmuch --config="$G5_CONFIG" config get index.decrypt)" false
g5_equal new_tags_sorted \
  "$(notmuch --config="$G5_CONFIG" config get new.tags | LC_ALL=C sort | paste -sd' ' -)" \
  'inbox unread'
G5_IGNORE=$(
  notmuch --config="$G5_CONFIG" config get new.ignore |
    LC_ALL=C sort |
    paste -sd' ' -
)
g5_equal new_ignore_sorted "$G5_IGNORE" \
  'betterbird-post-main-archive-maildirpp-20260704-205827 local-maildir provider-inbox-test test-maildir'

g5_check_source \
  evolution/local-maildir 48564 \
  e4e78a9bff9bbdca5b5c8ea4ab4703aa34bcb6cb4069e2ef6834fe935619c6d6
g5_check_source \
  evolution/betterbird-delta-maildirpp-20260704 247 \
  ec57b539cc6d577ef7162d88ee448ee7db6e1655b5eb583b00cd11a81985c6bb
g5_check_source \
  mbsync/provider-inbox-test 148 \
  d2084a07ea826428d0171a033b5774cd1bf29866ac0f583501fec4a81e400b7a
g5_check_source \
  evolution/test-maildir 4 \
  8f66b42eb7b9d6f858254492aaaab7ea66ffb38c71e6ec39999787da3e361014
g5_check_source \
  evolution/provider-live-archive 0 \
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
printf '%s\n' acknowledgement_matches_current_sources=yes

[[ ! -e "$G5_BACKUP_POINTER" ]] || g5_die "enrollment backup pointer already exists"
g5_equal prior_enrollment_backup_directories \
  "$(find "$G5_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'source-enrollment-*' -print | wc -l | tr -d ' ')" \
  0

G5_BROWSER_STATUS=$("$G5_BROWSER_CONTROL" status)
printf '%s\n' "$G5_BROWSER_STATUS" | grep -Fqx 'server=running' ||
  g5_die "browser service is not running"
G5_INDEX_STATUS=$("$G5_INDEX_CONTROL" status)
printf '%s\n' "$G5_INDEX_STATUS" | grep -Fqx 'loop=running' ||
  g5_die "index loop is not running"
G5_MBSYNC_STATUS=$("$G5_MBSYNC_CONTROL" status)
printf '%s\n' "$G5_MBSYNC_STATUS" | grep -Fqx 'loop=running' ||
  g5_die "mbsync loop is not running"
printf '%s\n' "$G5_MBSYNC_STATUS" | grep -Fqx 'paused=no' ||
  g5_die "mbsync loop is paused"
printf '%s\n' browser_service=running
printf '%s\n' index_loop=running
printf '%s\n' mbsync_loop=running
printf '%s\n' mbsync_paused=no
g5_equal loopback_listener_count \
  "$(ss -H -ltnp 'sport = :8765' | awk '$4 == "127.0.0.1:8765" {count++} END {print count+0}')" \
  1

G5_HEALTH=$(curl --silent --show-error --fail --max-time 10 http://127.0.0.1:8765/healthz)
python3 - "$G5_HEALTH" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
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
if not isinstance(files, int) or files < messages:
    raise SystemExit("status=blocked\nreason=invalid health file count")
print("health_ok=true")
print("health_read_only=true")
print("health_mail_mutation=false")
print(f"health_messages={messages}")
print(f"health_files={files}")
PY

for lock in \
  /mail/AppData/notmuch-browser/index-refresh.lock \
  /mail/AppData/isync/provider-live-loop/lock; do
  [[ ! -e "$lock" ]] || g5_die "active lock: $lock"
  printf 'lock_state=%s:absent\n' "$lock"
done

g5_equal config_sha256_after \
  "$(sha256sum "$G5_CONFIG" | awk '{print $1}')" "$G5_CONFIG_SHA"
g5_equal marker_sha256_after \
  "$(sha256sum "$G5_MARKER" | awk '{print $1}')" "$G5_MARKER_SHA"
printf '%s\n' backup_created=no
printf '%s\n' acknowledgement_marker_rewritten=no
printf '%s\n' notmuch_new_executed_by_gate=no
printf '%s\n' notmuch_config_changed=no
printf '%s\n' service_lifecycle_action_executed=no
printf '%s\n' maildir_mutation_executed=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_05_read_only_hardened_enrollment_final_audit_pass
