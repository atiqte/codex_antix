#!/bin/sh
set -u

APP=${NOTMUCH_BROWSER_BIN:-"$HOME/.local/bin/notmuch-browser"}
ADDR=${NOTMUCH_BROWSER_ADDR:-"127.0.0.1:8765"}
CONFIG=${NOTMUCH_BROWSER_CONFIG:-"$HOME/.config/notmuch/default/config"}
STATE_DIR=${NOTMUCH_BROWSER_STATE_DIR:-"/mail/AppData/notmuch-browser"}
DOWNLOAD_TMP=${NOTMUCH_BROWSER_DOWNLOAD_TMP:-"$STATE_DIR/download-tmp"}
LOG_DIR=${NOTMUCH_BROWSER_LOG_DIR:-"/mail/Logs/notmuch-browser"}
PID_FILE="$STATE_DIR/notmuch-browser.pid"
SERVER_LOG="$LOG_DIR/notmuch-browser.log"
RUNIT_SERVICE=${NOTMUCH_BROWSER_RUNIT_SERVICE:-"$HOME/.runit/service/notmuch-browser"}
RUNIT_LOG_DIR=${NOTMUCH_BROWSER_RUNIT_LOG_DIR:-"$LOG_DIR/runit-browser"}
REFRESH_LOCK_DIR="$STATE_DIR/index-refresh.lock"
MBSYNC_LOCK_DIR=${NOTMUCH_BROWSER_MBSYNC_LOCK:-"/mail/AppData/isync/provider-live-loop/lock"}
REFRESH_TIMEOUT_SECONDS=${NOTMUCH_BROWSER_REFRESH_TIMEOUT_SECONDS:-600}

EXPECTED_DB=${NOTMUCH_BROWSER_EXPECTED_DB:-"/mail/SearchIndex/notmuch/default"}
EXPECTED_MAIL_ROOT=${NOTMUCH_BROWSER_EXPECTED_MAIL_ROOT:-"/mail/Mailstore"}
EXPECTED_SYNC_FLAGS=${NOTMUCH_BROWSER_EXPECTED_SYNC_FLAGS:-"false"}
EXPECTED_INDEX_DECRYPT=${NOTMUCH_BROWSER_EXPECTED_INDEX_DECRYPT:-"false"}

ICEWM_STARTUP=${NOTMUCH_BROWSER_ICEWM_STARTUP:-"$HOME/.icewm/startup"}
STARTUP_BEGIN="# BEGIN NOTMUCH BROWSER SERVICE"
STARTUP_END="# END NOTMUCH BROWSER SERVICE"

log() {
  printf '%s\n' "$*"
}

ensure_dirs() {
  mkdir -p "$STATE_DIR" "$LOG_DIR"
  chmod 700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
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
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -q 'notmuch-browser' || return 1
  fi
  return 0
}

current_pid_alive() {
  pid=$(read_pid 2>/dev/null || true)
  pid_alive "$pid"
}

runit_supervised() {
  command -v sv >/dev/null 2>&1 &&
    [ -L "$RUNIT_SERVICE" ]
}

runit_status_line() {
  sv status "$RUNIT_SERVICE" 2>&1
}

notmuch_config_get() {
  notmuch --config="$CONFIG" config get "$1" 2>/dev/null | sed -n '1p'
}

check_notmuch_safety() {
  command -v notmuch >/dev/null 2>&1 || {
    log "status=blocked_missing_notmuch"
    return 1
  }
  [ -r "$CONFIG" ] || {
    log "status=blocked_missing_notmuch_config config=$CONFIG"
    return 1
  }
  db=$(notmuch_config_get database.path)
  mail_root=$(notmuch_config_get database.mail_root)
  sync_flags=$(notmuch_config_get maildir.synchronize_flags)
  index_decrypt=$(notmuch_config_get index.decrypt)
  [ "$db" = "$EXPECTED_DB" ] || {
    log "status=blocked_unexpected_database_path actual=$db expected=$EXPECTED_DB"
    return 1
  }
  [ "$mail_root" = "$EXPECTED_MAIL_ROOT" ] || {
    log "status=blocked_unexpected_mail_root actual=$mail_root expected=$EXPECTED_MAIL_ROOT"
    return 1
  }
  [ "$sync_flags" = "$EXPECTED_SYNC_FLAGS" ] || {
    log "status=blocked_unexpected_maildir_synchronize_flags actual=$sync_flags expected=$EXPECTED_SYNC_FLAGS"
    return 1
  }
  [ "$index_decrypt" = "$EXPECTED_INDEX_DECRYPT" ] || {
    log "status=blocked_unexpected_index_decrypt actual=$index_decrypt expected=$EXPECTED_INDEX_DECRYPT"
    return 1
  }
}

start_service() {
  ensure_dirs
  [ -x "$APP" ] || {
    log "status=blocked_missing_binary binary=$APP"
    return 1
  }
  check_notmuch_safety || return 1
  if runit_supervised; then
    if sv -w 20 up "$RUNIT_SERVICE"; then
      log "server=running"
      log "supervisor=user-runit"
      runit_status_line
      log "url=http://$ADDR/"
      return 0
    fi
    log "status=failed_to_start_runit_service"
    runit_status_line
    return 1
  fi
  if current_pid_alive; then
    log "server=running"
    log "pid=$(read_pid)"
    log "url=http://$ADDR/"
    return 0
  fi
  rm -f "$PID_FILE"
  log "starting notmuch browser: $APP"
  nohup "$APP" --addr "$ADDR" --config "$CONFIG" >> "$SERVER_LOG" 2>&1 &
  pid=$!
  printf '%s\n' "$pid" > "$PID_FILE"
  sleep 1
  if pid_alive "$pid"; then
    log "server=running"
    log "pid=$pid"
    log "url=http://$ADDR/"
    log "log=$SERVER_LOG"
    return 0
  fi
  log "status=failed_to_start"
  tail -80 "$SERVER_LOG" 2>/dev/null || true
  return 1
}

stop_service() {
  if runit_supervised; then
    if sv -w 20 down "$RUNIT_SERVICE"; then
      log "server=stopped"
      log "supervisor=user-runit"
      runit_status_line
      return 0
    fi
    log "status=failed_to_stop_runit_service"
    runit_status_line
    return 1
  fi
  pid=$(read_pid 2>/dev/null || true)
  if ! pid_alive "$pid"; then
    rm -f "$PID_FILE"
    log "server=stopped"
    return 0
  fi
  kill "$pid" 2>/dev/null || true
  i=0
  while pid_alive "$pid" && [ "$i" -lt 20 ]; do
    i=$((i + 1))
    sleep 1
  done
  if pid_alive "$pid"; then
    log "status=failed_to_stop pid=$pid"
    return 1
  fi
  rm -f "$PID_FILE"
  log "server=stopped"
}

status_service() {
  ensure_dirs
  if runit_supervised; then
    status=$(runit_status_line)
    case "$status" in
      run:*) log "server=running" ;;
      down:*) log "server=stopped" ;;
      *) log "server=unknown" ;;
    esac
    log "supervisor=user-runit"
    log "$status"
  else
    pid=$(read_pid 2>/dev/null || true)
    if pid_alive "$pid"; then
      log "server=running"
      log "pid=$pid"
    elif [ -s "$PID_FILE" ]; then
      log "server=stale_pid"
      log "pid=$pid"
    else
      log "server=stopped"
    fi
    log "supervisor=direct"
  fi
  log "url=http://$ADDR/"
  log "binary=$APP"
  log "config=$CONFIG"
  log "state_dir=$STATE_DIR"
  log "log_dir=$LOG_DIR"
  if [ -d "$DOWNLOAD_TMP" ]; then
    temp_count=$(find "$DOWNLOAD_TMP" -maxdepth 1 -type f -name 'nmb-*' 2>/dev/null | wc -l | tr -d ' ')
    temp_bytes=$(find "$DOWNLOAD_TMP" -maxdepth 1 -type f -name 'nmb-*' -exec stat -c '%s' {} \; 2>/dev/null | awk '{total += $1} END {print total + 0}')
  else
    temp_count=0
    temp_bytes=0
  fi
  log "download_tmp=$DOWNLOAD_TMP"
  log "download_tmp_files=$temp_count"
  log "download_tmp_bytes=$temp_bytes"
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
  if command -v notmuch >/dev/null 2>&1 && [ -r "$CONFIG" ]; then
    notmuch --config="$CONFIG" count '*' | sed 's/^/notmuch_unique_messages=/'
    notmuch --config="$CONFIG" count --output=files '*' | sed 's/^/notmuch_indexed_files=/'
    notmuch --config="$CONFIG" config get new.ignore | sed 's/^/new.ignore=/'
  fi
}

logs_service() {
  ensure_dirs
  log "log=$SERVER_LOG"
  log "runit_log=$RUNIT_LOG_DIR/current"
  ls -lh "$LOG_DIR" 2>/dev/null || true
  tail -120 "$RUNIT_LOG_DIR/current" 2>/dev/null || true
  tail -120 "$SERVER_LOG" 2>/dev/null || true
}

run_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    if timeout --help 2>/dev/null | grep -q -- '--kill-after'; then
      timeout --kill-after=60s "$REFRESH_TIMEOUT_SECONDS" "$@"
    else
      timeout "$REFRESH_TIMEOUT_SECONDS" "$@"
    fi
  else
    "$@"
  fi
}

refresh_index() {
  ensure_dirs
  check_notmuch_safety || return 1
  if [ -d "$MBSYNC_LOCK_DIR" ]; then
    log "status=skipped_mbsync_lock_present"
    log "mbsync_lock=$MBSYNC_LOCK_DIR"
    return 0
  fi
  if ! mkdir "$REFRESH_LOCK_DIR" 2>/dev/null; then
    log "status=skipped_refresh_lock_present"
    log "refresh_lock=$REFRESH_LOCK_DIR"
    return 0
  fi
  trap 'rm -rf "$REFRESH_LOCK_DIR"' EXIT HUP INT TERM
  printf '%s\n' "$$" > "$REFRESH_LOCK_DIR/pid"
  date '+%Y-%m-%d %H:%M:%S%z' > "$REFRESH_LOCK_DIR/started_at"

  log_file="$LOG_DIR/notmuch-new-$(date +%Y%m%d-%H%M%S).log"
  before_msg=$(notmuch --config="$CONFIG" count '*')
  before_files=$(notmuch --config="$CONFIG" count --output=files '*')
  log "before_messages=$before_msg"
  log "before_files=$before_files"
  if run_timeout notmuch --config="$CONFIG" new > "$log_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  cat "$log_file"
  after_msg=$(notmuch --config="$CONFIG" count '*')
  after_files=$(notmuch --config="$CONFIG" count --output=files '*')
  log "after_messages=$after_msg"
  log "after_files=$after_files"
  log "log=$log_file"
  rm -rf "$REFRESH_LOCK_DIR"
  trap - EXIT HUP INT TERM
  if [ "$rc" -eq 0 ]; then
    log "status=refresh_index_complete"
  else
    log "status=refresh_index_failed rc=$rc"
  fi
  return "$rc"
}

tunnel_hint() {
  port=${ADDR##*:}
  log "Run this from Windows PowerShell or another host terminal with SSH access:"
  log "ssh -N -L ${port}:127.0.0.1:${port} atiq@ANTI_X_VM_IP"
  log "Then open: http://127.0.0.1:${port}/"
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
    printf '%s\n' 'if [ -x "$HOME/.local/bin/notmuch-browser-control" ]; then'
    printf '%s\n' '  "$HOME/.local/bin/notmuch-browser-control" start >/tmp/notmuch-browser-icewm-startup.log 2>&1 &'
    printf '%s\n' 'fi'
    printf '%s\n' "$STARTUP_END"
  } > "$ICEWM_STARTUP"
  rm -f "$tmp"
  log "status=icewm_startup_installed"
  log "startup=$ICEWM_STARTUP"
}

print_runit_service() {
  cat <<EOF
# The approved supervisor is the existing per-user runsvdir, not root runit.
# Install the reviewed setup helper, then stage and activate one gate at a time:
notmuch-browser-runit-setup inspect
notmuch-browser-runit-setup stage
notmuch-browser-runit-setup activate
notmuch-browser-runit-setup validate
EOF
}

usage() {
  cat <<EOF
Usage: notmuch-browser-control {start|stop|restart|status|logs|refresh-index|tunnel-hint|install-icewm-startup|print-runit-service}

Environment overrides:
  NOTMUCH_BROWSER_BIN
  NOTMUCH_BROWSER_ADDR
  NOTMUCH_BROWSER_CONFIG
  NOTMUCH_BROWSER_STATE_DIR
  NOTMUCH_BROWSER_LOG_DIR
  NOTMUCH_BROWSER_DOWNLOAD_TMP
  NOTMUCH_BROWSER_REFRESH_TIMEOUT_SECONDS
  NOTMUCH_BROWSER_RUNIT_SERVICE
  NOTMUCH_BROWSER_RUNIT_LOG_DIR
EOF
}

cmd=${1:-}
case "$cmd" in
  start) start_service ;;
  stop) stop_service ;;
  restart) stop_service && start_service ;;
  status) status_service ;;
  logs) logs_service ;;
  refresh-index) refresh_index ;;
  tunnel-hint) tunnel_hint ;;
  install-icewm-startup) install_icewm_startup ;;
  print-runit-service) print_runit_service ;;
  *) usage; exit 2 ;;
esac
