#!/bin/sh
set -eu

ENGINE=${PROVIDER_LIVE_ARCHIVE_ENGINE:-"$HOME/.local/lib/provider-live-archive.py"}
PYTHON=${PROVIDER_LIVE_ARCHIVE_PYTHON:-python3}
LIVE=${PROVIDER_LIVE_MAILDIR:-/mail/Mailstore/mbsync/provider-live}
ARCHIVE=${PROVIDER_LIVE_ARCHIVE_MAILDIR:-/mail/Mailstore/evolution/provider-live-archive}
STATE=${PROVIDER_LIVE_ARCHIVE_STATE:-/mail/AppData/provider-live-archive}
BACKUP=${PROVIDER_LIVE_ARCHIVE_BACKUP:-/mail/Backups/provider-live-archive}
LOG_DIR=${PROVIDER_LIVE_ARCHIVE_LOG_DIR:-/mail/Logs/provider-live-archive}
THRESHOLD=${PROVIDER_LIVE_ARCHIVE_THRESHOLD:-15000}
MONITOR_INTERVAL_DEFAULT=${PROVIDER_LIVE_ARCHIVE_MONITOR_INTERVAL_SECONDS:-900}
REMINDER_INTERVAL=${PROVIDER_LIVE_ARCHIVE_REMINDER_SECONDS:-86400}
MAX_LOG_BYTES=${PROVIDER_LIVE_ARCHIVE_MAX_LOG_BYTES:-2097152}
MBSYNC_CONTROL=${PROVIDER_LIVE_MBSYNC_CONTROL:-"$HOME/.local/bin/mbsync-provider-live-control"}
NOTMUCH_INDEX_CONTROL=${PROVIDER_LIVE_NOTMUCH_INDEX_CONTROL:-"$HOME/.local/bin/notmuch-browser-index-control"}
NOTMUCH_CONTROL=${PROVIDER_LIVE_NOTMUCH_CONTROL:-"$HOME/.local/bin/notmuch-browser-control"}
NOTMUCH_CONFIG=${PROVIDER_LIVE_NOTMUCH_CONFIG:-"$HOME/.config/notmuch/default/config"}
ICEWM_STARTUP=${PROVIDER_LIVE_ARCHIVE_ICEWM_STARTUP:-"$HOME/.icewm/startup"}
CONTROL_PATH=${PROVIDER_LIVE_ARCHIVE_CONTROL_PATH:-"$HOME/.local/bin/provider-live-archive-control"}

MONITOR_DIR="$STATE/monitor"
MONITOR_PID="$MONITOR_DIR/monitor.pid"
MONITOR_INTERVAL_FILE="$MONITOR_DIR/interval-seconds"
ALERT_FILE="$MONITOR_DIR/alert-pending"
LAST_ALERT_EPOCH="$MONITOR_DIR/last-alert-epoch"
LAST_CHECK="$MONITOR_DIR/last-check.txt"
MONITOR_LOG="$LOG_DIR/provider-live-archive-monitor.log"
TRANSACTION_LOCK="$STATE/transaction.lock"
STARTUP_BEGIN="# BEGIN PROVIDER LIVE ARCHIVE MONITOR"
STARTUP_END="# END PROVIDER LIVE ARCHIVE MONITOR"

log() { printf '%s\n' "$*"; }
timestamp() { date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'; }

die() {
  log "ERROR: $*" >&2
  exit 1
}

normalize_int() {
  value=$1
  fallback=$2
  case "$value" in ''|*[!0-9]*) printf '%s\n' "$fallback" ;; *) printf '%s\n' "$value" ;; esac
}

THRESHOLD=$(normalize_int "$THRESHOLD" 15000)
MONITOR_INTERVAL_DEFAULT=$(normalize_int "$MONITOR_INTERVAL_DEFAULT" 900)
REMINDER_INTERVAL=$(normalize_int "$REMINDER_INTERVAL" 86400)
MAX_LOG_BYTES=$(normalize_int "$MAX_LOG_BYTES" 2097152)
[ "$THRESHOLD" -ge 1 ] || THRESHOLD=15000
[ "$MONITOR_INTERVAL_DEFAULT" -ge 60 ] || MONITOR_INTERVAL_DEFAULT=60

ensure_dirs() {
  mkdir -p "$STATE" "$STATE/runs" "$MONITOR_DIR" "$BACKUP" "$LOG_DIR"
  chmod 700 "$STATE" "$STATE/runs" "$MONITOR_DIR" "$BACKUP" "$LOG_DIR" 2>/dev/null || true
}

require_engine() {
  command -v "$PYTHON" >/dev/null 2>&1 || die "missing Python command: $PYTHON"
  [ -r "$ENGINE" ] || die "missing archive engine: $ENGINE"
  "$PYTHON" -m py_compile "$ENGINE" || die "archive engine syntax check failed"
}

engine() {
  "$PYTHON" "$ENGINE" "$@"
}

engine_common() {
  engine "$@" --live "$LIVE" --archive "$ARCHIVE" --state "$STATE" --backup "$BACKUP"
}

read_monitor_interval() {
  value=$(cat "$MONITOR_INTERVAL_FILE" 2>/dev/null || true)
  value=$(normalize_int "$value" "$MONITOR_INTERVAL_DEFAULT")
  [ "$value" -ge 60 ] || value=60
  [ "$value" -le 86400 ] || value=86400
  printf '%s\n' "$value"
}

monitor_pid_alive() {
  pid=${1:-}
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  if [ -r "/proc/$pid/cmdline" ]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'provider-live-archive-control.*monitor-loop' || return 1
  fi
}

current_monitor_pid() {
  sed -n '1p' "$MONITOR_PID" 2>/dev/null || true
}

rotate_monitor_log() {
  [ -f "$MONITOR_LOG" ] || return 0
  bytes=$(wc -c < "$MONITOR_LOG" 2>/dev/null | tr -d ' ')
  case "$bytes" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$bytes" -gt "$MAX_LOG_BYTES" ]; then
    mv -f "$MONITOR_LOG.2" "$MONITOR_LOG.3" 2>/dev/null || true
    mv -f "$MONITOR_LOG.1" "$MONITOR_LOG.2" 2>/dev/null || true
    mv -f "$MONITOR_LOG" "$MONITOR_LOG.1" 2>/dev/null || true
  fi
}

monitor_log() {
  ensure_dirs
  printf '%s %s\n' "$(timestamp)" "$*" >> "$MONITOR_LOG"
}

live_count() {
  require_engine
  engine count --live "$LIVE" --threshold "$THRESHOLD" | sed -n 's/^live_inbox_count=//p' | sed -n '1p'
}

check_now() {
  ensure_dirs
  if [ -d "$TRANSACTION_LOCK" ]; then
    monitor_log "status=skipped_transaction_lock"
    log "status=skipped_transaction_lock"
    return 0
  fi
  count=$(live_count)
  case "$count" in ''|*[!0-9]*) die "invalid live INBOX count: $count" ;; esac
  now=$(date +%s)
  printf 'last_check=%s live_inbox_count=%s threshold=%s\n' "$(timestamp)" "$count" "$THRESHOLD" > "$LAST_CHECK"
  chmod 600 "$LAST_CHECK"
  if [ "$count" -ge "$THRESHOLD" ]; then
    first=no
    if [ ! -f "$ALERT_FILE" ]; then
      first=yes
      printf 'alert_pending_since=%s count=%s threshold=%s\n' "$(timestamp)" "$count" "$THRESHOLD" > "$ALERT_FILE"
      chmod 600 "$ALERT_FILE"
    fi
    last=$(cat "$LAST_ALERT_EPOCH" 2>/dev/null || echo 0)
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    if [ "$first" = yes ] || [ $((now - last)) -ge "$REMINDER_INTERVAL" ]; then
      message="provider-live INBOX has $count messages (threshold $THRESHOLD). Run provider-live-archive-control estimate."
      if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "Mail archive required" "$message" 2>/dev/null || true
      fi
      printf '%s\n' "$now" > "$LAST_ALERT_EPOCH"
      chmod 600 "$LAST_ALERT_EPOCH"
      monitor_log "status=alert count=$count threshold=$THRESHOLD"
    else
      monitor_log "status=alert_pending count=$count threshold=$THRESHOLD"
    fi
    log "alert=pending"
    log "live_inbox_count=$count"
    log "threshold=$THRESHOLD"
    log "next_action=provider-live-archive-control estimate"
  else
    rm -f "$ALERT_FILE" "$LAST_ALERT_EPOCH"
    monitor_log "status=below_threshold count=$count threshold=$THRESHOLD"
    log "alert=clear"
    log "live_inbox_count=$count"
    log "threshold=$THRESHOLD"
  fi
}

monitor_loop() {
  ensure_dirs
  printf '%s\n' "$$" > "$MONITOR_PID"
  chmod 600 "$MONITOR_PID"
  trap 'rm -f "$MONITOR_PID"; exit 0' HUP INT TERM EXIT
  monitor_log "loop_start pid=$$ interval_seconds=$(read_monitor_interval)"
  while :; do
    rotate_monitor_log
    check_now >> "$MONITOR_LOG" 2>&1 || monitor_log "status=check_failed rc=$?"
    slept=0
    while [ "$slept" -lt "$(read_monitor_interval)" ]; do
      sleep 5
      slept=$((slept + 5))
    done
  done
}

monitor_start() {
  ensure_dirs
  pid=$(current_monitor_pid)
  if monitor_pid_alive "$pid"; then
    log "monitor=running"
    log "pid=$pid"
    return 0
  fi
  rm -f "$MONITOR_PID"
  nohup "$CONTROL_PATH" monitor-loop >/tmp/provider-live-archive-monitor.nohup 2>&1 &
  pid=$!
  sleep 1
  monitor_pid_alive "$pid" || die "archive monitor failed to start; inspect /tmp/provider-live-archive-monitor.nohup"
  log "monitor=running"
  log "pid=$pid"
  log "interval_seconds=$(read_monitor_interval)"
}

monitor_stop() {
  pid=$(current_monitor_pid)
  if ! monitor_pid_alive "$pid"; then
    rm -f "$MONITOR_PID"
    log "monitor=stopped"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  i=0
  while monitor_pid_alive "$pid" && [ "$i" -lt 20 ]; do sleep 1; i=$((i + 1)); done
  monitor_pid_alive "$pid" && die "archive monitor did not stop: $pid"
  rm -f "$MONITOR_PID"
  log "monitor=stopped"
}

set_monitor_interval() {
  value=$(normalize_int "${1:-}" 0)
  [ "$value" -ge 60 ] 2>/dev/null && [ "$value" -le 86400 ] || die "interval must be 60..86400 seconds"
  tmp="$MONITOR_INTERVAL_FILE.tmp.$$"
  (umask 077 && printf '%s\n' "$value" > "$tmp") || die "cannot write interval"
  mv -f "$tmp" "$MONITOR_INTERVAL_FILE"
  log "monitor_interval_seconds=$value"
  log "apply=running_monitor_will_notice_after_current_sleep"
}

status() {
  ensure_dirs
  log "== provider-live archive status =="
  engine count --live "$LIVE" --threshold "$THRESHOLD"
  pid=$(current_monitor_pid)
  if monitor_pid_alive "$pid"; then log "monitor=running"; log "monitor_pid=$pid"; else log "monitor=stopped"; fi
  log "monitor_interval_seconds=$(read_monitor_interval)"
  [ -f "$ALERT_FILE" ] && log "alert=pending" || log "alert=clear"
  if [ -f "$LAST_CHECK" ]; then cat "$LAST_CHECK"; else log "last_check=never"; fi
  [ -d "$TRANSACTION_LOCK" ] && log "transaction_lock=present" || log "transaction_lock=absent"
  if [ -x "$MBSYNC_CONTROL" ]; then "$MBSYNC_CONTROL" status | sed -n '/^loop=/p;/^paused=/p;/^sync_lock=/p;/^last_/p;/^channel=/p'; fi
  if [ -x "$NOTMUCH_INDEX_CONTROL" ]; then "$NOTMUCH_INDEX_CONTROL" status | sed -n '/^loop=/p;/^pid=/p;/^mbsync_lock=/p;/^refresh_lock=/p'; fi
  log "archive=$ARCHIVE"
  log "state=$STATE"
  log "backup=$BACKUP"
  log "log=$MONITOR_LOG"
  if [ -f "$ALERT_FILE" ]; then
    log "next_action=provider-live-archive-control estimate"
  else
    log "next_action=none_until_threshold"
  fi
}

install_startup() {
  ensure_dirs
  mkdir -p "$(dirname "$ICEWM_STARTUP")"
  tmp=$(mktemp)
  if [ -f "$ICEWM_STARTUP" ]; then
    awk -v begin="$STARTUP_BEGIN" -v end="$STARTUP_END" '
      $0 == begin {skip=1; next}
      $0 == end {skip=0; next}
      skip != 1 {print}
    ' "$ICEWM_STARTUP" > "$tmp"
  fi
  {
    cat "$tmp"
    printf '\n%s\n' "$STARTUP_BEGIN"
    printf 'if [ -x "%s" ]; then\n' "$CONTROL_PATH"
    printf '  "%s" monitor-start >/tmp/provider-live-archive-icewm-startup.log 2>&1 &\n' "$CONTROL_PATH"
    printf 'fi\n%s\n' "$STARTUP_END"
  } > "$tmp.new"
  install -m 700 "$tmp.new" "$ICEWM_STARTUP"
  rm -f "$tmp" "$tmp.new"
  grep -nA5 -B2 'PROVIDER LIVE ARCHIVE MONITOR' "$ICEWM_STARTUP" || true
}

evolution_running() {
  if command -v flatpak >/dev/null 2>&1; then
    flatpak ps --columns=application 2>/dev/null | grep -qx 'org.gnome.Evolution' && return 0
  fi
  pgrep -x evolution >/dev/null 2>&1 && return 0
  return 1
}

wait_for_mbsync_lock() {
  i=0
  while [ -d /mail/AppData/isync/provider-live-loop/lock ] && [ "$i" -lt 1800 ]; do sleep 2; i=$((i + 2)); done
  [ ! -d /mail/AppData/isync/provider-live-loop/lock ] || die "mbsync lock remained active for ${i}s"
}

quiesce_mail_services() {
  evolution_running && die "Evolution is running; close it and run: flatpak kill org.gnome.Evolution"
  engine audit-mbsync-config --config "$HOME/.config/isyncrc"
  [ -x "$MBSYNC_CONTROL" ] || die "missing mbsync control: $MBSYNC_CONTROL"
  "$MBSYNC_CONTROL" pause
  wait_for_mbsync_lock
  "$MBSYNC_CONTROL" stop-loop
  sleep 2
  if pgrep -f 'mbsync-provider-live-loop|mbsync .*provider-live-group|isync' >/dev/null 2>&1; then
    pgrep -af 'mbsync-provider-live-loop|mbsync .*provider-live-group|isync' || true
    die "mail sync process remains after stop"
  fi
  if [ -x "$NOTMUCH_INDEX_CONTROL" ]; then "$NOTMUCH_INDEX_CONTROL" stop; fi
  if [ -x "$NOTMUCH_CONTROL" ]; then "$NOTMUCH_CONTROL" stop; fi
}

resume_mbsync() {
  "$MBSYNC_CONTROL" resume
  "$MBSYNC_CONTROL" start
}

resume_index() {
  [ ! -x "$NOTMUCH_INDEX_CONTROL" ] || "$NOTMUCH_INDEX_CONTROL" start
}

resume_browser() {
  [ ! -x "$NOTMUCH_CONTROL" ] || "$NOTMUCH_CONTROL" start
}

begin_transaction() {
  ensure_dirs
  mkdir "$TRANSACTION_LOCK" 2>/dev/null || die "another archive transaction is active"
  printf '%s\n' "$$" > "$TRANSACTION_LOCK/pid"
  date -Is > "$TRANSACTION_LOCK/started_at" 2>/dev/null || date > "$TRANSACTION_LOCK/started_at"
  trap 'rm -f "$TRANSACTION_LOCK/pid" "$TRANSACTION_LOCK/started_at"; rmdir "$TRANSACTION_LOCK" 2>/dev/null || true' EXIT HUP INT TERM
}

end_transaction() {
  rm -f "$TRANSACTION_LOCK/pid" "$TRANSACTION_LOCK/started_at"
  rmdir "$TRANSACTION_LOCK" 2>/dev/null || true
  trap - EXIT HUP INT TERM
}

parse_prepare() {
  run_id=${1:-}; shift || true
  approve=""; external=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --approve-copy) approve=${2:-}; shift 2 ;;
      --external-target) external=${2:-}; shift 2 ;;
      *) die "unknown prepare argument: $1" ;;
    esac
  done
  [ -n "$run_id" ] || die "prepare requires RUN_ID"
  [ "$approve" = "$run_id" ] || die "copy approval must exactly match RUN_ID"
  [ -n "$external" ] || die "prepare requires --external-target PATH"
  begin_transaction
  monitor_stop
  quiesce_mail_services
  engine_common snapshot "$run_id" --mbsync-state /mail/AppData/isync/state/provider-live --config "$HOME/.config/isyncrc" --threshold "$THRESHOLD"
  resume_mbsync
  engine external-pack "$run_id" --state "$STATE" --backup "$BACKUP" --external-target "$external" --mail-root /mail
  engine_common copy "$run_id"
  engine_common verify-copy "$run_id"
  resume_index
  resume_browser
  monitor_start
  end_transaction
  log "status=copy_verified"
  log "run_id=$run_id"
  log "next=Open Evolution and validate TAG-Mustang Local Archive, then mark-evolution-validated."
}

controlled_notmuch_refresh() {
  [ -x "$NOTMUCH_CONTROL" ] || die "missing notmuch browser control: $NOTMUCH_CONTROL"
  wait_for_mbsync_lock
  "$NOTMUCH_CONTROL" refresh-index
}

audit_notmuch_config() {
  [ "$(notmuch --config="$NOTMUCH_CONFIG" config get database.path)" = /mail/SearchIndex/notmuch/default ] || die "unsafe notmuch database.path"
  [ "$(notmuch --config="$NOTMUCH_CONFIG" config get database.mail_root)" = /mail/Mailstore ] || die "unsafe notmuch database.mail_root"
  [ "$(notmuch --config="$NOTMUCH_CONFIG" config get maildir.synchronize_flags)" = false ] || die "unsafe notmuch maildir.synchronize_flags"
  [ "$(notmuch --config="$NOTMUCH_CONFIG" config get index.decrypt)" = false ] || die "unsafe notmuch index.decrypt"
}

controlled_notmuch_full_refresh() {
  wait_for_mbsync_lock
  command -v notmuch >/dev/null 2>&1 || die "missing notmuch command"
  audit_notmuch_config
  notmuch --config="$NOTMUCH_CONFIG" new --full-scan
}

verify_notmuch() {
  run_id=${1:-}
  [ -n "$run_id" ] || die "verify-notmuch requires RUN_ID"
  begin_transaction
  [ ! -x "$NOTMUCH_INDEX_CONTROL" ] || "$NOTMUCH_INDEX_CONTROL" stop
  controlled_notmuch_full_refresh
  paths_file="$STATE/runs/$run_id/notmuch-indexed-paths.txt"
  notmuch --config="$NOTMUCH_CONFIG" search --output=files '*' > "$paths_file"
  chmod 600 "$paths_file"
  engine_common verify-notmuch "$run_id" --indexed-paths "$paths_file" --forbidden-prefix /mail/Mailstore/evolution/local-maildir
  resume_index
  end_transaction
}

configure_notmuch_scope() {
  begin_transaction
  [ ! -x "$NOTMUCH_INDEX_CONTROL" ] || "$NOTMUCH_INDEX_CONTROL" stop
  [ ! -x "$NOTMUCH_CONTROL" ] || "$NOTMUCH_CONTROL" stop
  engine configure-notmuch-scope --config "$NOTMUCH_CONFIG" --mail-root /mail/Mailstore --backup-root /mail/Backups/notmuch
  controlled_notmuch_full_refresh
  paths_file="$STATE/notmuch-scope-paths-after.txt"
  notmuch --config="$NOTMUCH_CONFIG" search --output=files '*' > "$paths_file"
  chmod 600 "$paths_file"
  if grep -Fq '/mail/Mailstore/evolution/local-maildir/' "$paths_file"; then
    die "forbidden 59G Betterbird archive entered notmuch index"
  fi
  resume_index
  resume_browser
  end_transaction
  log "status=notmuch_scope_configured"
}

sync_once_while_loop_stopped() {
  "$MBSYNC_CONTROL" resume
  if "$MBSYNC_CONTROL" sync-now; then rc=0; else rc=$?; fi
  "$MBSYNC_CONTROL" pause
  [ "$rc" -eq 0 ] || die "controlled mbsync sync failed: $rc"
}

parse_cleanup() {
  run_id=${1:-}; shift || true
  approve=""
  while [ "$#" -gt 0 ]; do
    case "$1" in --approve-cleanup) approve=${2:-}; shift 2 ;; *) die "unknown cleanup argument: $1" ;; esac
  done
  [ -n "$run_id" ] || die "cleanup requires RUN_ID"
  [ "$approve" = "$run_id" ] || die "cleanup approval must exactly match RUN_ID"
  begin_transaction
  monitor_stop
  quiesce_mail_services
  engine_common cleanup-canary "$run_id"
  sync_once_while_loop_stopped
  if ! engine_common verify-canary "$run_id"; then
    engine rollback "$run_id" --live "$LIVE" --state "$STATE" --backup "$BACKUP" || true
    die "cleanup canary failed and rollback was attempted"
  fi
  engine_common cleanup-remaining "$run_id"
  sync_once_while_loop_stopped
  engine_common verify-cleanup "$run_id"
  controlled_notmuch_refresh
  resume_mbsync
  resume_index
  resume_browser
  monitor_start
  end_transaction
  log "status=cleanup_verified"
  log "run_id=$run_id"
}

rollback_run() {
  run_id=${1:-}
  [ -n "$run_id" ] || die "rollback requires RUN_ID"
  begin_transaction
  monitor_stop
  quiesce_mail_services
  engine rollback "$run_id" --live "$LIVE" --state "$STATE" --backup "$BACKUP"
  controlled_notmuch_refresh || true
  resume_mbsync
  resume_index
  resume_browser
  monitor_start
  end_transaction
}

retire_run() {
  run_id=${1:-}; shift || true
  approve=""
  while [ "$#" -gt 0 ]; do
    case "$1" in --approve-retire) approve=${2:-}; shift 2 ;; *) die "unknown retire argument: $1" ;; esac
  done
  [ "$approve" = "$run_id" ] || die "retirement approval must exactly match RUN_ID"
  engine retire-snapshot "$run_id" --state "$STATE" --backup "$BACKUP" --archive "$ARCHIVE" --minimum-days 30
}

usage() {
  cat <<EOF
Usage: $(basename "$0") COMMAND

Commands:
  layout
  status
  check-now
  simulate-alert
  monitor-start | monitor-stop | monitor-status | monitor-loop
  monitor-set-interval SECONDS
  install-icewm-startup
  estimate
  configure-notmuch-scope
  prepare RUN_ID --approve-copy RUN_ID --external-target PATH
  verify-copy RUN_ID
  mark-evolution-validated RUN_ID
  verify-notmuch RUN_ID
  cleanup RUN_ID --approve-cleanup RUN_ID
  rollback RUN_ID
  retire-snapshot RUN_ID --approve-retire RUN_ID
  run-status RUN_ID
EOF
}

run_logged_command() {
  ensure_dirs
  command_name=$1
  run_id=${2:-general}
  safe_id=$(printf '%s' "$run_id" | tr -cd 'A-Za-z0-9._-')
  [ -n "$safe_id" ] || safe_id=general
  command_log="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$command_name-$safe_id.log"
  rc_file="$STATE/.command-rc.$$"
  (
    if PROVIDER_LIVE_ARCHIVE_LOGGED=1 "$0" "$@"; then rc=0; else rc=$?; fi
    printf '%s\n' "$rc" > "$rc_file"
  ) 2>&1 | tee -a "$command_log"
  if [ ! -f "$rc_file" ]; then
    log "ERROR: command ended without an exit record; inspect $command_log" >&2
    return 1
  fi
  rc=$(cat "$rc_file")
  rm -f "$rc_file"
  log "command_log=$command_log"
  return "$rc"
}

case "${1:-}" in
  help|-h|--help|'') usage; exit 0 ;;
esac

ensure_dirs
require_engine

if [ "${PROVIDER_LIVE_ARCHIVE_LOGGED:-0}" != 1 ]; then
  case ${1:-} in
    configure-notmuch-scope|prepare|verify-copy|mark-evolution-validated|verify-notmuch|cleanup|rollback|retire-snapshot)
      run_logged_command "$@"
      exit $?
      ;;
  esac
fi

case "${1:-}" in
  layout) engine layout --archive "$ARCHIVE" --state "$STATE" --backup "$BACKUP" ;;
  status) status ;;
  check-now) check_now ;;
  simulate-alert) log "simulation_only=yes"; log "simulated_count=$THRESHOLD"; log "alert=would_trigger" ;;
  monitor-loop) monitor_loop ;;
  monitor-start) monitor_start ;;
  monitor-stop) monitor_stop ;;
  monitor-status) status ;;
  monitor-set-interval) set_monitor_interval "${2:-}" ;;
  install-icewm-startup) install_startup ;;
  estimate) engine estimate --live "$LIVE" --threshold "$THRESHOLD"; log "recommended_run_id=$(date +%Y%m%d-%H%M%S)" ;;
  configure-notmuch-scope) configure_notmuch_scope ;;
  prepare) shift; parse_prepare "$@" ;;
  verify-copy) engine_common verify-copy "${2:-}" ;;
  mark-evolution-validated) engine mark-evolution-validated "${2:-}" --state "$STATE" --backup "$BACKUP" --live "$LIVE" --archive "$ARCHIVE" --note "operator confirmed Evolution text/html/attachment/unread/flagged archive samples" ;;
  verify-notmuch) verify_notmuch "${2:-}" ;;
  cleanup) shift; parse_cleanup "$@" ;;
  rollback) rollback_run "${2:-}" ;;
  retire-snapshot) shift; retire_run "$@" ;;
  run-status) engine run-status "${2:-}" --state "$STATE" --backup "$BACKUP" ;;
  *) usage >&2; exit 2 ;;
esac
