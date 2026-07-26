#!/bin/sh
set -eu

MAIL_ROOT=${NOTMUCH_ENROLL_MAIL_ROOT:-/mail}
MAILSTORE=${NOTMUCH_ENROLL_MAILSTORE:-"$MAIL_ROOT/Mailstore"}
CONFIG=${NOTMUCH_ENROLL_CONFIG:-"$HOME/.config/notmuch/default/config"}
DB_PATH=${NOTMUCH_ENROLL_DB_PATH:-"$MAIL_ROOT/SearchIndex/notmuch/default"}
STATE_DIR=${NOTMUCH_ENROLL_STATE_DIR:-"$MAIL_ROOT/AppData/notmuch-browser/source-enrollment"}
LOG_DIR=${NOTMUCH_ENROLL_LOG_DIR:-"$MAIL_ROOT/Logs/notmuch-browser/source-enrollment"}
BACKUP_ROOT=${NOTMUCH_ENROLL_BACKUP_ROOT:-"$MAIL_ROOT/Backups/notmuch-browser"}
MBSYNC_CONTROL=${NOTMUCH_ENROLL_MBSYNC_CONTROL:-"$HOME/.local/bin/mbsync-provider-live-control"}
BROWSER_CONTROL=${NOTMUCH_ENROLL_BROWSER_CONTROL:-"$HOME/.local/bin/notmuch-browser-control"}
INDEX_CONTROL=${NOTMUCH_ENROLL_INDEX_CONTROL:-"$HOME/.local/bin/notmuch-browser-index-control"}
MBSYNC_LOCK_DIR=${NOTMUCH_ENROLL_MBSYNC_LOCK_DIR:-"$MAIL_ROOT/AppData/isync/provider-live-loop/lock"}
REFRESH_LOCK_DIR=${NOTMUCH_ENROLL_REFRESH_LOCK_DIR:-"$MAIL_ROOT/AppData/notmuch-browser/index-refresh.lock"}

LOCAL_REL=evolution/local-maildir
DELTA_REL=evolution/betterbird-delta-maildirpp-20260704
PROVIDER_ARCHIVE_REL=evolution/provider-live-archive
TEST_REL=evolution/test-maildir
PROVIDER_TEST_REL=mbsync/provider-inbox-test
LIVE_REL=mbsync/provider-live
UNAVAILABLE_IGNORE=betterbird-post-main-archive-maildirpp-20260704-205827

EXPECTED_LOCAL=${NOTMUCH_ENROLL_EXPECTED_LOCAL:-48564}
EXPECTED_DELTA=${NOTMUCH_ENROLL_EXPECTED_DELTA:-247}
EXPECTED_PROVIDER_TEST=${NOTMUCH_ENROLL_EXPECTED_PROVIDER_TEST:-148}
EXPECTED_TEST=${NOTMUCH_ENROLL_EXPECTED_TEST:-4}
EXPECTED_PROVIDER_ARCHIVE=${NOTMUCH_ENROLL_EXPECTED_PROVIDER_ARCHIVE:-0}
MIN_FREE_KIB=${NOTMUCH_ENROLL_MIN_FREE_KIB:-83886080}
RESTORE_WAIT_ATTEMPTS=${NOTMUCH_ENROLL_RESTORE_WAIT_ATTEMPTS:-20}
QUIESCE_WAIT_ATTEMPTS=${NOTMUCH_ENROLL_QUIESCE_WAIT_ATTEMPTS:-120}

ACK_MARKER="$STATE_DIR/current-sources-acknowledged.env"
BACKUP_POINTER="$STATE_DIR/current-backup"

say() {
  printf '%s\n' "$*"
}

die() {
  say "status=blocked"
  say "reason=$*"
  exit 1
}

source_path() {
  printf '%s/%s\n' "$MAILSTORE" "$1"
}

message_count() {
  source=$(source_path "$1")
  [ -d "$source" ] || {
    printf '%s\n' -1
    return
  }
  find "$source" -type f \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    wc -l | tr -d ' '
}

source_bytes() {
  source=$(source_path "$1")
  [ -d "$source" ] || {
    printf '%s\n' -1
    return
  }
  find "$source" -type f -printf '%s\n' |
    awk '{ total += $1 } END { printf "%.0f\n", total + 0 }'
}

source_manifest_sha() {
  source=$(source_path "$1")
  [ -d "$source" ] || {
    printf '%s\n' missing
    return
  }
  (
    cd "$source"
    find . -type f \( -path '*/cur/*' -o -path '*/new/*' \) \
      -printf '%P\t%s\t%T@\t%m\n' |
      LC_ALL=C sort |
      sha256sum |
      awk '{ print $1 }'
  )
}

source_symlinks() {
  source=$(source_path "$1")
  [ -d "$source" ] || {
    printf '%s\n' -1
    return
  }
  find "$source" -type l -print | wc -l | tr -d ' '
}

expected_for_source() {
  case "$1" in
    "$LOCAL_REL") printf '%s\n' "$EXPECTED_LOCAL" ;;
    "$DELTA_REL") printf '%s\n' "$EXPECTED_DELTA" ;;
    "$PROVIDER_TEST_REL") printf '%s\n' "$EXPECTED_PROVIDER_TEST" ;;
    "$TEST_REL") printf '%s\n' "$EXPECTED_TEST" ;;
    "$PROVIDER_ARCHIVE_REL") printf '%s\n' "$EXPECTED_PROVIDER_ARCHIVE" ;;
    *) return 1 ;;
  esac
}

all_sources() {
  printf '%s\n' \
    "$LOCAL_REL" \
    "$DELTA_REL" \
    "$PROVIDER_TEST_REL" \
    "$TEST_REL" \
    "$PROVIDER_ARCHIVE_REL"
}

check_source_inventory() {
  rel=$1
  expected=$(expected_for_source "$rel")
  actual=$(message_count "$rel")
  [ "$actual" = "$expected" ] ||
    die "$rel has $actual message paths; expected $expected"
  links=$(source_symlinks "$rel")
  [ "$links" = 0 ] || die "$rel contains $links symlinks"
}

check_platform() {
  case "$RESTORE_WAIT_ATTEMPTS" in
    ''|*[!0-9]*|0) die "service restore wait attempts must be a positive integer" ;;
  esac
  case "$QUIESCE_WAIT_ATTEMPTS" in
    ''|*[!0-9]*|0) die "quiesce wait attempts must be a positive integer" ;;
  esac
  [ "$(findmnt -n -o FSTYPE --target "$MAIL_ROOT" 2>/dev/null || true)" = xfs ] ||
    die "$MAIL_ROOT is not an XFS mount"
  available=$(df -Pk "$MAIL_ROOT" | awk 'NR == 2 { print $4 }')
  case "$available" in ''|*[!0-9]*) die "cannot read free space" ;; esac
  [ "$available" -ge "$MIN_FREE_KIB" ] ||
    die "only $available KiB free; at least $MIN_FREE_KIB KiB is required"
  [ -f "$CONFIG" ] && [ ! -L "$CONFIG" ] || die "unsafe notmuch config"
  [ "$(notmuch --config="$CONFIG" config get database.path)" = "$DB_PATH" ] ||
    die "unsafe database.path"
  [ "$(notmuch --config="$CONFIG" config get database.mail_root)" = "$MAILSTORE" ] ||
    die "unsafe database.mail_root"
  [ "$(notmuch --config="$CONFIG" config get maildir.synchronize_flags)" = false ] ||
    die "maildir.synchronize_flags must be false"
  [ "$(notmuch --config="$CONFIG" config get index.decrypt)" = false ] ||
    die "index.decrypt must be false"
  tags=$(notmuch --config="$CONFIG" config get new.tags | paste -sd' ' -)
  [ "$tags" = "unread inbox" ] || [ "$tags" = "inbox unread" ] ||
    die "new.tags must contain only unread and inbox"
}

inspect_sources() {
  check_platform
  all_sources | while IFS= read -r rel; do
    count=$(message_count "$rel")
    bytes=$(source_bytes "$rel")
    links=$(source_symlinks "$rel")
    manifest=$(source_manifest_sha "$rel")
    say "source=$rel message_paths=$count bytes=$bytes symlinks=$links manifest_sha256=$manifest"
  done
  notmuch --config="$CONFIG" config get new.ignore | sed 's/^/new.ignore=/'
  say "free_kib=$(df -Pk "$MAIL_ROOT" | awk 'NR == 2 { print $4 }')"
  say "status=inspection_complete"
}

acknowledge_sources() {
  check_platform
  install -d -m 700 "$STATE_DIR"
  all_sources | while IFS= read -r rel; do
    check_source_inventory "$rel"
  done
  marker=$(mktemp "$STATE_DIR/.acknowledgement.XXXXXX")
  {
    all_sources | while IFS= read -r rel; do
      key=$(printf '%s' "$rel" | tr '/.-' '___')
      say "${key}_message_paths=$(message_count "$rel")"
      say "${key}_bytes=$(source_bytes "$rel")"
      say "${key}_manifest_sha256=$(source_manifest_sha "$rel")"
    done
    say "acknowledged_at=$(date -Is 2>/dev/null || date)"
  } > "$marker"
  chmod 600 "$marker"
  mv "$marker" "$ACK_MARKER"
  say "status=current_sources_acknowledged"
  say "marker=$ACK_MARKER"
  say "marker_sha256=$(sha256sum "$ACK_MARKER" | awk '{print $1}')"
}

acknowledgement_valid() {
  [ -s "$ACK_MARKER" ] || return 1
  all_sources | while IFS= read -r rel; do
    key=$(printf '%s' "$rel" | tr '/.-' '___')
    expected=$(expected_for_source "$rel")
    count=$(message_count "$rel")
    manifest=$(source_manifest_sha "$rel")
    grep -Fqx "${key}_message_paths=$expected" "$ACK_MARKER" || exit 1
    [ "$count" = "$expected" ] || exit 1
    grep -Fqx "${key}_manifest_sha256=$manifest" "$ACK_MARKER" || exit 1
  done
}

capture_service_state() {
  MBSYNC_WAS_RUNNING=no
  MBSYNC_WAS_PAUSED=yes
  INDEX_WAS_RUNNING=no
  BROWSER_WAS_RUNNING=no
  if [ -x "$MBSYNC_CONTROL" ]; then
    status=$("$MBSYNC_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" | grep -Eq 'loop=(running|alive)|loop_status=running' &&
      MBSYNC_WAS_RUNNING=yes
    printf '%s\n' "$status" | grep -Eq 'paused=(no|false)' &&
      MBSYNC_WAS_PAUSED=no
  fi
  if [ -x "$INDEX_CONTROL" ]; then
    status=$("$INDEX_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" | grep -Eq 'loop=(running|alive)|loop_status=running' &&
      INDEX_WAS_RUNNING=yes
  fi
  if [ -x "$BROWSER_CONTROL" ]; then
    status=$("$BROWSER_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" | grep -Fqx 'server=running' &&
      BROWSER_WAS_RUNNING=yes
  fi
  export MBSYNC_WAS_RUNNING MBSYNC_WAS_PAUSED INDEX_WAS_RUNNING BROWSER_WAS_RUNNING
}

quiesce_services() {
  [ ! -x "$MBSYNC_CONTROL" ] || "$MBSYNC_CONTROL" pause
  [ ! -x "$MBSYNC_CONTROL" ] || "$MBSYNC_CONTROL" stop-loop
  [ ! -x "$INDEX_CONTROL" ] || "$INDEX_CONTROL" stop
  [ ! -x "$BROWSER_CONTROL" ] || "$BROWSER_CONTROL" stop
}

restore_service_state() {
  [ "${BROWSER_WAS_RUNNING:-no}" != yes ] || [ ! -x "$BROWSER_CONTROL" ] ||
    "$BROWSER_CONTROL" start >/dev/null 2>&1 || true
  [ "${INDEX_WAS_RUNNING:-no}" != yes ] || [ ! -x "$INDEX_CONTROL" ] ||
    "$INDEX_CONTROL" start >/dev/null 2>&1 || true
  [ "${MBSYNC_WAS_RUNNING:-no}" != yes ] || [ ! -x "$MBSYNC_CONTROL" ] ||
    "$MBSYNC_CONTROL" start >/dev/null 2>&1 || true
  [ "${MBSYNC_WAS_PAUSED:-yes}" != no ] || [ ! -x "$MBSYNC_CONTROL" ] ||
    "$MBSYNC_CONTROL" resume >/dev/null 2>&1 || true
}

service_state_matches_capture() {
  if [ "${BROWSER_WAS_RUNNING:-no}" = yes ]; then
    [ -x "$BROWSER_CONTROL" ] || return 1
    status=$("$BROWSER_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" | grep -Fqx 'server=running' || return 1
  fi
  if [ "${INDEX_WAS_RUNNING:-no}" = yes ]; then
    [ -x "$INDEX_CONTROL" ] || return 1
    status=$("$INDEX_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" |
      grep -Eq 'loop=(running|alive)|loop_status=running' || return 1
  fi
  if [ "${MBSYNC_WAS_RUNNING:-no}" = yes ]; then
    [ -x "$MBSYNC_CONTROL" ] || return 1
    status=$("$MBSYNC_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" |
      grep -Eq 'loop=(running|alive)|loop_status=running' || return 1
  fi
  if [ "${MBSYNC_WAS_PAUSED:-yes}" = no ]; then
    [ -x "$MBSYNC_CONTROL" ] || return 1
    status=$("$MBSYNC_CONTROL" status 2>&1 || true)
    printf '%s\n' "$status" | grep -Eq 'paused=(no|false)' || return 1
  fi
}

wait_for_restored_service_state() {
  attempts=0
  while [ "$attempts" -lt "$RESTORE_WAIT_ATTEMPTS" ]; do
    service_state_matches_capture && return 0
    attempts=$((attempts + 1))
    sleep 1
  done
  return 1
}

wait_for_quiescent_locks() {
  attempts=0
  while [ "$attempts" -lt "$QUIESCE_WAIT_ATTEMPTS" ]; do
    if [ ! -e "$MBSYNC_LOCK_DIR" ] && [ ! -e "$REFRESH_LOCK_DIR" ]; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  return 1
}

run_prebackup_refresh() {
  stamp=$1
  log="$LOG_DIR/prebackup-refresh-$stamp.log"
  say "prebackup_refresh_log=$log"
  if "$BROWSER_CONTROL" refresh-index > "$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  chmod 600 "$log"
  say "prebackup_refresh_exit=$rc"
  say "prebackup_refresh_log_bytes=$(wc -c < "$log" | tr -d ' ')"
  say "prebackup_refresh_log_sha256=$(sha256sum "$log" | awk '{print $1}')"
  [ "$rc" -eq 0 ] || return "$rc"
  grep -Eq '^status=refresh[_-]index[_-]complete$|^status=refresh-complete$' "$log" ||
    return 1
}

set_ignore() {
  notmuch --config="$CONFIG" config set new.ignore "$@"
}

run_notmuch_new() {
  label=$1
  stamp=$2
  log="$LOG_DIR/notmuch-new-$stamp-$label.log"
  say "notmuch_new_stage=$label"
  say "notmuch_new_log=$log"
  if notmuch --config="$CONFIG" new > "$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  chmod 600 "$log"
  say "notmuch_new_exit=$rc"
  say "notmuch_new_log_bytes=$(wc -c < "$log" | tr -d ' ')"
  say "notmuch_new_log_sha256=$(sha256sum "$log" | awk '{print $1}')"
  return "$rc"
}

tag_source_unique_messages() {
  rel=$1
  tag=$2
  shift 2
  query="path:$(printf '%s/**' "$rel")"
  for other in "$@"; do
    query="$query and not path:$(printf '%s/**' "$other")"
  done
  notmuch --config="$CONFIG" tag "+$tag" -- "$query"
}

write_path_list() {
  rel=$1
  output=$2
  source=$(source_path "$rel")
  find "$source" -type f \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    LC_ALL=C sort > "$output"
}

write_indexed_path_list() {
  rel=$1
  output=$2
  prefix=$(source_path "$rel")/
  notmuch --config="$CONFIG" search --output=files "path:$rel/**" |
    awk -v prefix="$prefix" 'index($0, prefix) == 1 { print }' |
    LC_ALL=C sort > "$output"
}

verify_source_parity() {
  rel=$1
  evidence=$2
  key=$(printf '%s' "$rel" | tr '/.-' '___')
  expected="$evidence/$key.expected.txt"
  actual="$evidence/$key.indexed.txt"
  write_path_list "$rel" "$expected"
  write_indexed_path_list "$rel" "$actual"
  if ! cmp -s "$expected" "$actual"; then
    diff -u "$expected" "$actual" > "$evidence/$key.diff.txt" || true
    die "$rel indexed path parity failed"
  fi
  say "source_parity=$rel paths=$(wc -l < "$actual" | tr -d ' ') sha256=$(sha256sum "$actual" | awk '{print $1}')"
}

create_backup() {
  stamp=$1
  backup="$BACKUP_ROOT/source-enrollment-$stamp"
  [ ! -e "$backup" ] || die "backup already exists: $backup"
  install -d -m 700 "$backup"
  cp -p "$CONFIG" "$backup/notmuch-config.before"
  notmuch --config="$CONFIG" dump --format=batch-tag > "$backup/tags.before.batch-tag"
  notmuch --config="$CONFIG" search --exclude=false --output=files '*' > "$backup/paths.before.txt"
  cp -a "$DB_PATH" "$backup/notmuch-database.before"
  all_sources | while IFS= read -r rel; do
    key=$(printf '%s' "$rel" | tr '/.-' '___')
    write_path_list "$rel" "$backup/$key.maildir-before.txt"
  done
  (
    cd "$backup"
    find . -type f ! -name inventory.sha256 -print |
      LC_ALL=C sort |
      while IFS= read -r file; do sha256sum "$file"; done > inventory.sha256
    sha256sum -c --status inventory.sha256
  )
  printf '%s\n' "$backup" > "$BACKUP_POINTER"
  chmod 600 "$BACKUP_POINTER"
  printf '%s\n' "$backup"
}

rollback_backup() {
  backup=${1:-}
  [ -n "$backup" ] || [ ! -s "$BACKUP_POINTER" ] || backup=$(sed -n '1p' "$BACKUP_POINTER")
  [ -n "$backup" ] || die "no enrollment backup selected"
  [ -d "$backup/notmuch-database.before" ] || die "backup database missing"
  [ -f "$backup/notmuch-config.before" ] || die "backup config missing"
  capture_service_state
  quiesce_services
  stamp=$(date +%Y%m%d-%H%M%S)
  failed="$backup/notmuch-database.failed-$stamp"
  [ ! -e "$failed" ] || die "failed database preservation path already exists"
  mv "$DB_PATH" "$failed"
  cp -a "$backup/notmuch-database.before" "$DB_PATH"
  cp -p "$backup/notmuch-config.before" "$CONFIG"
  restore_service_state
  say "status=rollback_complete"
  say "backup=$backup"
  say "failed_database_preserved=$failed"
}

enroll_sources() {
  check_platform
  acknowledgement_valid || die "current source acknowledgement is missing or stale"
  install -d -m 700 "$STATE_DIR" "$LOG_DIR" "$BACKUP_ROOT"
  capture_service_state
  backup=
  MUTATION_STARTED=no
  ENROLL_COMPLETE=no
  cleanup_enrollment() {
    if [ "${ENROLL_COMPLETE:-no}" != yes ] &&
      [ "${MUTATION_STARTED:-no}" = yes ] &&
      [ -n "${backup:-}" ] &&
      [ -d "$backup/notmuch-database.before" ]; then
      current_failed="$backup/notmuch-database.failed-enrollment"
      if [ -d "$DB_PATH" ] && [ ! -e "$current_failed" ]; then
        mv "$DB_PATH" "$current_failed"
        cp -a "$backup/notmuch-database.before" "$DB_PATH"
      fi
      cp -p "$backup/notmuch-config.before" "$CONFIG"
    fi
    restore_service_state
  }
  trap cleanup_enrollment EXIT HUP INT TERM

  [ ! -x "$MBSYNC_CONTROL" ] || "$MBSYNC_CONTROL" pause
  [ ! -x "$INDEX_CONTROL" ] || "$INDEX_CONTROL" stop
  wait_for_quiescent_locks ||
    die "mbsync or index refresh lock did not quiesce"
  stamp=$(date +%Y%m%d-%H%M%S)
  if [ -x "$BROWSER_CONTROL" ]; then
    run_prebackup_refresh "$stamp" ||
      die "pre-backup index refresh did not complete"
  fi
  wait_for_quiescent_locks ||
    die "index refresh lock remained after pre-backup refresh"
  [ ! -x "$BROWSER_CONTROL" ] || "$BROWSER_CONTROL" stop

  backup=$(create_backup "$stamp")
  evidence="$backup/enrollment-evidence"
  install -d -m 700 "$evidence"

  MUTATION_STARTED=yes
  notmuch --config="$CONFIG" config set new.tags

  set_ignore "$UNAVAILABLE_IGNORE" provider-inbox-test test-maildir
  run_notmuch_new local "$stamp"
  tag_source_unique_messages "$LOCAL_REL" historical-archive "$LIVE_REL" "$DELTA_REL"

  set_ignore "$UNAVAILABLE_IGNORE" test-maildir
  run_notmuch_new provider-test "$stamp"
  tag_source_unique_messages "$PROVIDER_TEST_REL" provider-inbox-test "$LIVE_REL" "$DELTA_REL" "$LOCAL_REL"

  set_ignore "$UNAVAILABLE_IGNORE"
  run_notmuch_new evolution-test "$stamp"
  tag_source_unique_messages "$TEST_REL" test-mail "$LIVE_REL" "$DELTA_REL" "$LOCAL_REL" "$PROVIDER_TEST_REL"

  notmuch --config="$CONFIG" config set new.tags unread inbox
  chmod 600 "$CONFIG"

  all_sources | while IFS= read -r rel; do
    verify_source_parity "$rel" "$evidence"
    key=$(printf '%s' "$rel" | tr '/.-' '___')
    current_manifest=$(source_manifest_sha "$rel")
    grep -Fqx "${key}_manifest_sha256=$current_manifest" "$ACK_MARKER" ||
      die "$rel Maildir metadata changed during enrollment"
  done

  [ "$(notmuch --config="$CONFIG" config get new.ignore | paste -sd' ' -)" = "$UNAVAILABLE_IGNORE" ] ||
    die "final new.ignore is not exact"
  [ "$(notmuch --config="$CONFIG" config get new.tags | paste -sd' ' -)" = "unread inbox" ] ||
    die "new.tags were not restored"

  restore_service_state
  wait_for_restored_service_state ||
    die "background service state did not recover after enrollment"
  ENROLL_COMPLETE=yes
  trap - EXIT HUP INT TERM
  say "status=source_enrollment_complete"
  say "backup=$backup"
  say "evidence=$evidence"
}

validate_enrollment() {
  check_platform
  [ "$(notmuch --config="$CONFIG" config get new.ignore | paste -sd' ' -)" = "$UNAVAILABLE_IGNORE" ] ||
    die "new.ignore is not exact"
  tmp=$(mktemp -d "$STATE_DIR/.validate.XXXXXX")
  all_sources | while IFS= read -r rel; do
    check_source_inventory "$rel"
    verify_source_parity "$rel" "$tmp"
  done
  say "status=source_enrollment_valid"
  say "validation_evidence=$tmp"
}

usage() {
  say "Usage: $0 {inspect|acknowledge-current|enroll|validate|rollback [BACKUP]}"
}

command=${1:-help}
case "$command" in
  inspect) inspect_sources ;;
  acknowledge-current) acknowledge_sources ;;
  enroll) enroll_sources ;;
  validate) validate_enrollment ;;
  rollback) shift; rollback_backup "${1:-}" ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
