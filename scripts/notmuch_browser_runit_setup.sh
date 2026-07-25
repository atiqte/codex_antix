#!/bin/sh
set -eu

APP=${NOTMUCH_BROWSER_BIN:-"$HOME/.local/bin/notmuch-browser"}
BROWSER_CONTROL=${NOTMUCH_BROWSER_CONTROL:-"$HOME/.local/bin/notmuch-browser-control"}
INDEX_CONTROL=${NOTMUCH_BROWSER_INDEX_CONTROL:-"$HOME/.local/bin/notmuch-browser-index-control"}
CONFIG=${NOTMUCH_BROWSER_CONFIG:-"$HOME/.config/notmuch/default/config"}
ADDR=${NOTMUCH_BROWSER_ADDR:-"127.0.0.1:8765"}
STATE_DIR=${NOTMUCH_BROWSER_STATE_DIR:-"/mail/AppData/notmuch-browser"}
LOG_DIR=${NOTMUCH_BROWSER_LOG_DIR:-"/mail/Logs/notmuch-browser"}
BACKUP_ROOT=${NOTMUCH_BROWSER_BACKUP_ROOT:-"/mail/Backups/notmuch-browser"}
ICEWM_STARTUP=${NOTMUCH_BROWSER_ICEWM_STARTUP:-"$HOME/.icewm/startup"}

USER_SERVICE_ROOT=${NOTMUCH_BROWSER_USER_SERVICE_ROOT:-"$HOME/.runit/usersv"}
ACTIVE_SERVICE_ROOT=${NOTMUCH_BROWSER_ACTIVE_SERVICE_ROOT:-"$HOME/.runit/service"}
BROWSER_DEF="$USER_SERVICE_ROOT/notmuch-browser"
INDEX_DEF="$USER_SERVICE_ROOT/notmuch-browser-index"
BROWSER_ACTIVE="$ACTIVE_SERVICE_ROOT/notmuch-browser"
INDEX_ACTIVE="$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
POINTER="$STATE_DIR/user-runit-rollback-current"

BROWSER_BEGIN="# BEGIN NOTMUCH BROWSER SERVICE"
BROWSER_END="# END NOTMUCH BROWSER SERVICE"
INDEX_BEGIN="# BEGIN NOTMUCH BROWSER INDEX REFRESH SERVICE"
INDEX_END="# END NOTMUCH BROWSER INDEX REFRESH SERVICE"
MANAGED_MARKER=".notmuch-browser-user-runit-managed"

log() {
  printf '%s\n' "$*"
}

die() {
  log "status=blocked"
  log "reason=$*"
  exit 1
}

mail_ready() {
  awk '$2 == "/mail" { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null
}

require_prerequisites() {
  command -v sv >/dev/null 2>&1 || die "missing sv"
  command -v svlogd >/dev/null 2>&1 || die "missing svlogd"
  command -v curl >/dev/null 2>&1 || die "missing curl"
  mail_ready || die "/mail is not mounted"
  [ -x "$APP" ] || die "missing browser binary: $APP"
  [ -x "$BROWSER_CONTROL" ] || die "missing browser control: $BROWSER_CONTROL"
  [ -x "$INDEX_CONTROL" ] || die "missing index control: $INDEX_CONTROL"
  [ -r "$CONFIG" ] || die "missing notmuch config: $CONFIG"
  [ -d "$USER_SERVICE_ROOT" ] || die "missing user service definition root: $USER_SERVICE_ROOT"
  [ -d "$ACTIVE_SERVICE_ROOT" ] || die "missing active user runit root: $ACTIVE_SERVICE_ROOT"
  pgrep -u "$(id -u)" -f "runsvdir -P $ACTIVE_SERVICE_ROOT" >/dev/null 2>&1 ||
    die "user runsvdir is not supervising $ACTIVE_SERVICE_ROOT"
}

managed_or_absent() {
  definition=$1
  if [ -e "$definition" ] && [ ! -f "$definition/$MANAGED_MARKER" ]; then
    die "refusing unmanaged service definition: $definition"
  fi
}

write_browser_definition() {
  install -d -m 700 "$BROWSER_DEF" "$BROWSER_DEF/log"
  : > "$BROWSER_DEF/$MANAGED_MARKER"
  : > "$BROWSER_DEF/down"

  cat > "$BROWSER_DEF/run" <<'RUN'
#!/bin/sh
set -u
exec 2>&1
while :; do
  if awk '$2 == "/mail" { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null &&
     [ -x "$HOME/.local/bin/notmuch-browser" ] &&
     [ -r "$HOME/.config/notmuch/default/config" ]; then
    break
  fi
  printf '%s readiness=waiting_for_mail_binary_or_config\n' "$(date -Is 2>/dev/null || date)"
  sleep 5
done
sleep 1
exec "$HOME/.local/bin/notmuch-browser" --addr 127.0.0.1:8765 --config "$HOME/.config/notmuch/default/config"
RUN

  cat > "$BROWSER_DEF/finish" <<'FINISH'
#!/bin/sh
printf '%s service=notmuch-browser exit_code=%s signal=%s restart_delay_seconds=2\n' \
  "$(date -Is 2>/dev/null || date)" "${1:-unknown}" "${2:-unknown}"
sleep 2
FINISH

  cat > "$BROWSER_DEF/check" <<'CHECK'
#!/bin/sh
health=$(curl -fsS --max-time 15 http://127.0.0.1:8765/healthz 2>/dev/null) || exit 1
case "$health" in
  *'"ok":true'*) ;;
  *) exit 1 ;;
esac
case "$health" in
  *'"read_only":true'*) ;;
  *) exit 1 ;;
esac
case "$health" in
  *'"mail_mutation":false'*) exit 0 ;;
  *) exit 1 ;;
esac
CHECK

  cat > "$BROWSER_DEF/log/run" <<'LOG'
#!/bin/sh
set -u
while ! awk '$2 == "/mail" { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null; do
  sleep 5
done
install -d -m 700 /mail/Logs/notmuch-browser/runit-browser
exec svlogd -tt /mail/Logs/notmuch-browser/runit-browser
LOG

  cat > "$LOG_DIR/runit-browser/config" <<'CONFIG'
s2097152
n5
N2
t86400
CONFIG

  chmod 755 "$BROWSER_DEF/run" "$BROWSER_DEF/finish" "$BROWSER_DEF/check" "$BROWSER_DEF/log/run"
  chmod 600 "$BROWSER_DEF/$MANAGED_MARKER" "$BROWSER_DEF/down" "$LOG_DIR/runit-browser/config"
}

write_index_definition() {
  install -d -m 700 "$INDEX_DEF" "$INDEX_DEF/log"
  : > "$INDEX_DEF/$MANAGED_MARKER"
  : > "$INDEX_DEF/down"

  cat > "$INDEX_DEF/run" <<'RUN'
#!/bin/sh
set -u
exec 2>&1
while :; do
  if awk '$2 == "/mail" { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null &&
     [ -x "$HOME/.local/bin/notmuch-browser-control" ] &&
     [ -x "$HOME/.local/bin/notmuch-browser-index-control" ]; then
    break
  fi
  printf '%s readiness=waiting_for_mail_or_controls\n' "$(date -Is 2>/dev/null || date)"
  sleep 5
done
sleep 2
exec "$HOME/.local/bin/notmuch-browser-index-control" loop
RUN

  cat > "$INDEX_DEF/finish" <<'FINISH'
#!/bin/sh
printf '%s service=notmuch-browser-index exit_code=%s signal=%s restart_delay_seconds=2\n' \
  "$(date -Is 2>/dev/null || date)" "${1:-unknown}" "${2:-unknown}"
sleep 2
FINISH

  cat > "$INDEX_DEF/check" <<'CHECK'
#!/bin/sh
status=$(sv status "$HOME/.runit/service/notmuch-browser" 2>/dev/null) || exit 1
case "$status" in
  run:*) ;;
  *) exit 1 ;;
esac
pgrep -u "$(id -u)" -f 'notmuch-browser-index-control loop' >/dev/null 2>&1
CHECK

  cat > "$INDEX_DEF/log/run" <<'LOG'
#!/bin/sh
set -u
while ! awk '$2 == "/mail" { found=1 } END { exit(found ? 0 : 1) }' /proc/mounts 2>/dev/null; do
  sleep 5
done
install -d -m 700 /mail/Logs/notmuch-browser/runit-index
exec svlogd -tt /mail/Logs/notmuch-browser/runit-index
LOG

  cat > "$LOG_DIR/runit-index/config" <<'CONFIG'
s2097152
n5
N2
t86400
CONFIG

  chmod 755 "$INDEX_DEF/run" "$INDEX_DEF/finish" "$INDEX_DEF/check" "$INDEX_DEF/log/run"
  chmod 600 "$INDEX_DEF/$MANAGED_MARKER" "$INDEX_DEF/down" "$LOG_DIR/runit-index/config"
}

inspect_state() {
  log "user_service_root=$USER_SERVICE_ROOT"
  log "active_service_root=$ACTIVE_SERVICE_ROOT"
  log "browser_definition=$BROWSER_DEF"
  log "index_definition=$INDEX_DEF"
  log "browser_active=$BROWSER_ACTIVE"
  log "index_active=$INDEX_ACTIVE"
  log "state_dir=$STATE_DIR"
  log "log_dir=$LOG_DIR"
  if mail_ready; then log "mail_mount=ready"; else log "mail_mount=missing"; fi
  if pgrep -u "$(id -u)" -f "runsvdir -P $ACTIVE_SERVICE_ROOT" >/dev/null 2>&1; then
    log "user_runsvdir=running"
  else
    log "user_runsvdir=stopped"
  fi
  for service in "$BROWSER_ACTIVE" "$INDEX_ACTIVE"; do
    if [ -L "$service" ]; then
      log "service_link=$service target=$(readlink "$service")"
      sv status "$service" 2>&1 || true
    else
      log "service_link_absent=$service"
    fi
  done
  if [ -f "$ICEWM_STARTUP" ]; then
    log "icewm_browser_begin_count=$(grep -Fxc "$BROWSER_BEGIN" "$ICEWM_STARTUP" || true)"
    log "icewm_index_begin_count=$(grep -Fxc "$INDEX_BEGIN" "$ICEWM_STARTUP" || true)"
  else
    log "icewm_startup=absent"
  fi
  if [ -s "$POINTER" ]; then log "rollback_pointer=present"; else log "rollback_pointer=absent"; fi
}

stage_services() {
  require_prerequisites
  managed_or_absent "$BROWSER_DEF"
  managed_or_absent "$INDEX_DEF"
  [ ! -e "$BROWSER_ACTIVE" ] || die "browser service is already active"
  [ ! -e "$INDEX_ACTIVE" ] || die "index service is already active"
  install -d -m 700 "$STATE_DIR" "$LOG_DIR" "$LOG_DIR/runit-browser" "$LOG_DIR/runit-index"
  write_browser_definition
  write_index_definition
  sh -n "$BROWSER_DEF/run" "$BROWSER_DEF/finish" "$BROWSER_DEF/check" "$BROWSER_DEF/log/run"
  sh -n "$INDEX_DEF/run" "$INDEX_DEF/finish" "$INDEX_DEF/check" "$INDEX_DEF/log/run"
  log "status=user_runit_services_staged"
}

create_backup() {
  run_id=$(date +%Y%m%d-%H%M%S)
  backup="$BACKUP_ROOT/$run_id-before-user-runit"
  [ ! -e "$backup" ] || die "backup already exists: $backup"
  install -d -m 700 "$backup"
  if [ -f "$ICEWM_STARTUP" ]; then
    cp -p "$ICEWM_STARTUP" "$backup/icewm-startup"
  fi
  cp -p "$APP" "$backup/notmuch-browser"
  cp -p "$BROWSER_CONTROL" "$backup/notmuch-browser-control"
  cp -p "$INDEX_CONTROL" "$backup/notmuch-browser-index-control"
  (
    cd "$backup" || exit 1
    sha256sum notmuch-browser notmuch-browser-control notmuch-browser-index-control > artifacts.sha256
    if [ -f icewm-startup ]; then sha256sum icewm-startup >> artifacts.sha256; fi
  ) || die "backup checksum generation failed"
  tmp_pointer=$(mktemp "$STATE_DIR/.user-runit-pointer.XXXXXX")
  printf '%s\n' "$backup" > "$tmp_pointer"
  chmod 600 "$tmp_pointer"
  mv "$tmp_pointer" "$POINTER"
  log "rollback_backup=$backup"
}

remove_icewm_blocks() {
  [ -f "$ICEWM_STARTUP" ] || return 0
  tmp=$(mktemp "$(dirname "$ICEWM_STARTUP")/.notmuch-browser-startup.XXXXXX")
  awk \
    -v browser_begin="$BROWSER_BEGIN" -v browser_end="$BROWSER_END" \
    -v index_begin="$INDEX_BEGIN" -v index_end="$INDEX_END" '
      $0 == browser_begin || $0 == index_begin { skip=1; next }
      $0 == browser_end || $0 == index_end { skip=0; next }
      skip != 1 { print }
    ' "$ICEWM_STARTUP" > "$tmp"
  chmod "$(stat -c '%a' "$ICEWM_STARTUP")" "$tmp"
  mv "$tmp" "$ICEWM_STARTUP"
}

link_service() {
  definition=$1
  active=$2
  relative="../usersv/$(basename "$definition")"
  [ ! -e "$active" ] || die "active service path already exists: $active"
  ln -s "$relative" "$active"
}

validate_runtime() {
  sv -w 20 check "$BROWSER_ACTIVE" >/dev/null || return 1
  sv -w 20 check "$INDEX_ACTIVE" >/dev/null || return 1
  health=$(curl -fsS --max-time 20 "http://$ADDR/healthz") || return 1
  case "$health" in
    *'"ok":true'*) ;;
    *) return 1 ;;
  esac
  case "$health" in
    *'"read_only":true'*) ;;
    *) return 1 ;;
  esac
  case "$health" in
    *'"mail_mutation":false'*) ;;
    *) return 1 ;;
  esac
  return 0
}

rollback_activation() {
  log "rollback=begin"
  sv -w 20 down "$INDEX_ACTIVE" >/dev/null 2>&1 || true
  sv -w 20 down "$BROWSER_ACTIVE" >/dev/null 2>&1 || true
  : > "$BROWSER_DEF/down"
  : > "$INDEX_DEF/down"
  if [ -L "$INDEX_ACTIVE" ] && [ "$(readlink "$INDEX_ACTIVE")" = "../usersv/notmuch-browser-index" ]; then
    unlink "$INDEX_ACTIVE"
  fi
  if [ -L "$BROWSER_ACTIVE" ] && [ "$(readlink "$BROWSER_ACTIVE")" = "../usersv/notmuch-browser" ]; then
    unlink "$BROWSER_ACTIVE"
  fi
  if [ -s "$POINTER" ]; then
    backup=$(sed -n '1p' "$POINTER")
    case "$backup" in
      "$BACKUP_ROOT"/*)
        if [ -f "$backup/icewm-startup" ]; then cp -p "$backup/icewm-startup" "$ICEWM_STARTUP"; fi
        ;;
    esac
  fi
  "$BROWSER_CONTROL" start >/dev/null 2>&1 || true
  "$INDEX_CONTROL" start >/dev/null 2>&1 || true
  log "rollback=complete"
}

archive_failed_pointer() {
  if [ -s "$POINTER" ]; then
    failed_pointer="$POINTER.failed-$(date +%Y%m%d-%H%M%S)"
    mv "$POINTER" "$failed_pointer"
    log "rollback_pointer_archived=$failed_pointer"
  fi
}

fail_activation() {
  reason=$1
  rollback_activation
  archive_failed_pointer
  die "$reason"
}

activate_services() {
  require_prerequisites
  [ -f "$BROWSER_DEF/$MANAGED_MARKER" ] || die "browser service is not staged"
  [ -f "$INDEX_DEF/$MANAGED_MARKER" ] || die "index service is not staged"
  [ ! -e "$BROWSER_ACTIVE" ] || die "browser service is already active"
  [ ! -e "$INDEX_ACTIVE" ] || die "index service is already active"
  [ ! -s "$POINTER" ] || die "rollback pointer already exists: $POINTER"

  create_backup
  "$INDEX_CONTROL" stop || fail_activation "could not stop legacy index loop"
  "$BROWSER_CONTROL" stop || fail_activation "could not stop legacy browser"
  link_service "$BROWSER_DEF" "$BROWSER_ACTIVE"
  link_service "$INDEX_DEF" "$INDEX_ACTIVE"
  unlink "$BROWSER_DEF/down"
  unlink "$INDEX_DEF/down"
  sv -w 20 up "$BROWSER_ACTIVE" || fail_activation "browser runit activation failed"
  sv -w 20 up "$INDEX_ACTIVE" || fail_activation "index runit activation failed"
  validate_runtime || fail_activation "runit runtime validation failed"
  remove_icewm_blocks
  log "status=user_runit_services_activated"
  validate_services
}

validate_services() {
  require_prerequisites
  [ -L "$BROWSER_ACTIVE" ] || die "browser service link is absent"
  [ -L "$INDEX_ACTIVE" ] || die "index service link is absent"
  [ "$(readlink "$BROWSER_ACTIVE")" = "../usersv/notmuch-browser" ] || die "unexpected browser service target"
  [ "$(readlink "$INDEX_ACTIVE")" = "../usersv/notmuch-browser-index" ] || die "unexpected index service target"
  validate_runtime || die "service health check failed"
  if [ -f "$ICEWM_STARTUP" ]; then
    [ "$(grep -Fxc "$BROWSER_BEGIN" "$ICEWM_STARTUP" || true)" -eq 0 ] || die "legacy browser IceWM block remains"
    [ "$(grep -Fxc "$INDEX_BEGIN" "$ICEWM_STARTUP" || true)" -eq 0 ] || die "legacy index IceWM block remains"
  fi
  log "status=user_runit_validation_passed"
  sv status "$BROWSER_ACTIVE"
  sv status "$INDEX_ACTIVE"
  "$BROWSER_CONTROL" status
  "$INDEX_CONTROL" status
}

rollback_services() {
  require_prerequisites
  [ -s "$POINTER" ] || die "rollback pointer is absent"
  backup=$(sed -n '1p' "$POINTER")
  case "$backup" in
    "$BACKUP_ROOT"/*) ;;
    *) die "rollback pointer is outside backup root" ;;
  esac
  [ -d "$backup" ] || die "rollback backup is missing: $backup"
  (cd "$backup" && sha256sum -c artifacts.sha256) || die "rollback backup verification failed"
  rollback_activation
  used_pointer="$POINTER.used-$(date +%Y%m%d-%H%M%S)"
  mv "$POINTER" "$used_pointer"
  log "rollback_pointer_archived=$used_pointer"
  log "status=user_runit_rollback_complete"
}

usage() {
  cat <<EOF
Usage: notmuch-browser-runit-setup {inspect|stage|activate|validate|rollback}

The helper manages only the approved per-user services:
  $BROWSER_ACTIVE
  $INDEX_ACTIVE

It never writes under /etc/service and never changes Maildir, tags, or messages.
EOF
}

cmd=${1:-}
case "$cmd" in
  inspect) inspect_state ;;
  stage) stage_services ;;
  activate) activate_services ;;
  validate) validate_services ;;
  rollback) rollback_services ;;
  *) usage; exit 2 ;;
esac
