#!/bin/sh
set -u

CONTROL=${NOTMUCH_BROWSER_CONTROL:-"$HOME/.local/bin/notmuch-browser-control"}
STATE_DIR=${NOTMUCH_BROWSER_STATE_DIR:-"/mail/AppData/notmuch-browser"}
LOG_DIR=${NOTMUCH_BROWSER_LOG_DIR:-"/mail/Logs/notmuch-browser"}
PID_FILE="$STATE_DIR/notmuch-browser-index-loop.pid"
LOOP_LOG="$LOG_DIR/notmuch-browser-index-loop.log"
MBSYNC_LOCK_DIR=${NOTMUCH_BROWSER_MBSYNC_LOCK:-"/mail/AppData/isync/provider-live-loop/lock"}
REFRESH_LOCK_DIR="$STATE_DIR/index-refresh.lock"
INTERVAL_SECONDS=${NOTMUCH_BROWSER_INDEX_REFRESH_INTERVAL_SECONDS:-60}
LOCK_RECHECK_SECONDS=${NOTMUCH_BROWSER_INDEX_LOCK_RECHECK_SECONDS:-15}
MAX_LOG_BYTES=${NOTMUCH_BROWSER_INDEX_LOOP_MAX_LOG_BYTES:-2097152}
ICEWM_STARTUP=${NOTMUCH_BROWSER_ICEWM_STARTUP:-"$HOME/.icewm/startup"}
STARTUP_BEGIN="# BEGIN NOTMUCH BROWSER INDEX REFRESH SERVICE"
STARTUP_END="# END NOTMUCH BROWSER INDEX REFRESH SERVICE"

normalize_positive_int() {
  value=$1
  fallback=$2
  case "$value" in
    ''|*[!0-9]*) printf '%s\n' "$fallback" ;;
    *) printf '%s\n' "$value" ;;
  esac
}

INTERVAL_SECONDS=$(normalize_positive_int "$INTERVAL_SECONDS" 60)
LOCK_RECHECK_SECONDS=$(normalize_positive_int "$LOCK_RECHECK_SECONDS" 15)
MAX_LOG_BYTES=$(normalize_positive_int "$MAX_LOG_BYTES" 2097152)

if [ "$INTERVAL_SECONDS" -lt 30 ]; then
  INTERVAL_SECONDS=30
fi
if [ "$LOCK_RECHECK_SECONDS" -lt 5 ]; then
  LOCK_RECHECK_SECONDS=5
fi

log() {
  printf '%s\n' "$*"
}

ensure_dirs() {
  mkdir -p "$STATE_DIR" "$LOG_DIR"
  chmod 700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
}

timestamp() {
  date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'
}

loop_log() {
  ensure_dirs
  printf '%s %s\n' "$(timestamp)" "$*" >> "$LOOP_LOG"
}

rotate_loop_log() {
  [ -f "$LOOP_LOG" ] || return 0
  bytes=$(wc -c < "$LOOP_LOG" 2>/dev/null | tr -d ' ')
  case "$bytes" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$bytes" -gt "$MAX_LOG_BYTES" ]; then
    mv -f "$LOOP_LOG.2" "$LOOP_LOG.3" 2>/dev/null || true
    mv -f "$LOOP_LOG.1" "$LOOP_LOG.2" 2>/dev/null || true
    mv -f "$LOOP_LOG" "$LOOP_LOG.1" 2>/dev/null || true
  fi
}

read_pid() {
  [ -s "$PID_FILE" ] || return 1
  sed -n '1p' "$PID_FILE"
}

pid_alive() {
  pid=$1
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  if [ -r "/proc/$pid/cmdline" ]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'notmuch-browser-index-control' || return 1
  fi
  return 0
}

current_pid_alive() {
  pid=$(read_pid 2>/dev/null || true)
  pid_alive "$pid"
}

loop_forever() {
  ensure_dirs
  loop_log "loop_start interval_seconds=$INTERVAL_SECONDS lock_recheck_seconds=$LOCK_RECHECK_SECONDS"
  while :; do
    rotate_loop_log
    if [ ! -x "$CONTROL" ]; then
      loop_log "status=skipped_missing_control control=$CONTROL"
      sleep "$INTERVAL_SECONDS"
      continue
    fi
    if [ -d "$MBSYNC_LOCK_DIR" ]; then
      loop_log "status=skipped_mbsync_lock_present lock=$MBSYNC_LOCK_DIR"
      sleep "$LOCK_RECHECK_SECONDS"
      continue
    fi
    if [ -d "$REFRESH_LOCK_DIR" ]; then
      loop_log "status=skipped_refresh_lock_present lock=$REFRESH_LOCK_DIR"
      sleep "$LOCK_RECHECK_SECONDS"
      continue
    fi
    loop_log "refresh_begin"
    "$CONTROL" refresh-index >> "$LOOP_LOG" 2>&1
    rc=$?
    loop_log "refresh_end rc=$rc"
    sleep "$INTERVAL_SECONDS"
  done
}

start_loop() {
  ensure_dirs
  if current_pid_alive; then
    log "loop=running"
    log "pid=$(read_pid)"
    log "interval_seconds=$INTERVAL_SECONDS"
    log "log=$LOOP_LOG"
    return 0
  fi
  rm -f "$PID_FILE"
  nohup "$0" loop >/dev/null 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"
  sleep 1
  if pid_alive "$pid"; then
    log "loop=running"
    log "pid=$pid"
    log "interval_seconds=$INTERVAL_SECONDS"
    log "log=$LOOP_LOG"
    return 0
  fi
  log "status=failed_to_start_index_loop"
  tail -80 "$LOOP_LOG" 2>/dev/null || true
  return 1
}

stop_loop() {
  pid=$(read_pid 2>/dev/null || true)
  if ! pid_alive "$pid"; then
    rm -f "$PID_FILE"
    log "loop=stopped"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  i=0
  while pid_alive "$pid" && [ "$i" -lt 20 ]; do
    i=$((i + 1))
    sleep 1
  done
  if pid_alive "$pid"; then
    log "status=failed_to_stop_index_loop pid=$pid"
    return 1
  fi
  rm -f "$PID_FILE"
  log "loop=stopped"
}

status_loop() {
  ensure_dirs
  pid=$(read_pid 2>/dev/null || true)
  if pid_alive "$pid"; then
    log "loop=running"
    log "pid=$pid"
  elif [ -s "$PID_FILE" ]; then
    log "loop=stale_pid"
    log "pid=$pid"
  else
    log "loop=stopped"
  fi
  log "control=$CONTROL"
  log "state_dir=$STATE_DIR"
  log "log_dir=$LOG_DIR"
  log "log=$LOOP_LOG"
  log "interval_seconds=$INTERVAL_SECONDS"
  log "lock_recheck_seconds=$LOCK_RECHECK_SECONDS"
  if [ -d "$MBSYNC_LOCK_DIR" ]; then
    log "mbsync_lock=present"
  else
    log "mbsync_lock=absent"
  fi
  if [ -d "$REFRESH_LOCK_DIR" ]; then
    log "refresh_lock=present"
  else
    log "refresh_lock=absent"
  fi
  if [ -x "$CONTROL" ]; then
    "$CONTROL" status 2>/dev/null | sed -n '
      s/^server=/browser_server=/p
      /^notmuch_unique_messages=/p
      /^notmuch_indexed_files=/p
    '
  fi
}

logs_loop() {
  ensure_dirs
  log "log=$LOOP_LOG"
  ls -lh "$LOG_DIR" 2>/dev/null || true
  tail -160 "$LOOP_LOG" 2>/dev/null || true
}

install_icewm_startup() {
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
    printf '%s\n' "$STARTUP_BEGIN"
    printf '%s\n' 'if [ -x "$HOME/.local/bin/notmuch-browser-index-control" ]; then'
    printf '%s\n' '  "$HOME/.local/bin/notmuch-browser-index-control" start >/tmp/notmuch-browser-index-icewm-startup.log 2>&1 &'
    printf '%s\n' 'fi'
    printf '%s\n' "$STARTUP_END"
  } > "$ICEWM_STARTUP"
  rm -f "$tmp"
  log "status=icewm_index_refresh_startup_installed"
  log "startup=$ICEWM_STARTUP"
}

remove_icewm_startup() {
  [ -f "$ICEWM_STARTUP" ] || {
    log "status=icewm_startup_absent"
    return 0
  }
  tmp=$(mktemp)
  awk -v begin="$STARTUP_BEGIN" -v end="$STARTUP_END" '
    $0 == begin {skip=1; next}
    $0 == end {skip=0; next}
    skip != 1 {print}
  ' "$ICEWM_STARTUP" > "$tmp"
  cat "$tmp" > "$ICEWM_STARTUP"
  rm -f "$tmp"
  log "status=icewm_index_refresh_startup_removed"
  log "startup=$ICEWM_STARTUP"
}

usage() {
  cat <<EOF
Usage: notmuch-browser-index-control {start|stop|restart|status|logs|loop|install-icewm-startup|remove-icewm-startup}

Environment overrides:
  NOTMUCH_BROWSER_CONTROL
  NOTMUCH_BROWSER_STATE_DIR
  NOTMUCH_BROWSER_LOG_DIR
  NOTMUCH_BROWSER_MBSYNC_LOCK
  NOTMUCH_BROWSER_INDEX_REFRESH_INTERVAL_SECONDS
  NOTMUCH_BROWSER_INDEX_LOCK_RECHECK_SECONDS
  NOTMUCH_BROWSER_INDEX_LOOP_MAX_LOG_BYTES
  NOTMUCH_BROWSER_ICEWM_STARTUP
EOF
}

cmd=${1:-}
case "$cmd" in
  start) start_loop ;;
  stop) stop_loop ;;
  restart) stop_loop && start_loop ;;
  status) status_loop ;;
  logs) logs_loop ;;
  loop) loop_forever ;;
  install-icewm-startup) install_icewm_startup ;;
  remove-icewm-startup) remove_icewm_startup ;;
  *) usage; exit 2 ;;
esac
