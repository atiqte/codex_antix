#!/bin/sh
set -eu

APP_ID=${EVOLUTION_APP_ID:-org.gnome.Evolution}
APP_LABEL=${EVOLUTION_APP_LABEL:-Evolution Mail}

HOME_DIR=${HOME:?HOME is not set}
ICEWM_DIR=${ICEWM_DIR:-"$HOME_DIR/.icewm"}
MENU_FILE=${ICEWM_MENU_FILE:-"$ICEWM_DIR/personal"}
TOOLBAR_FILE=${ICEWM_TOOLBAR_FILE:-"$ICEWM_DIR/toolbar"}
STARTUP_FILE=${ICEWM_STARTUP_FILE:-"$ICEWM_DIR/startup"}
BIN_DIR=${BIN_DIR:-"$HOME_DIR/.local/bin"}
STATE_ROOT=${XDG_STATE_HOME:-"$HOME_DIR/.local/state"}
STATE_DIR="$STATE_ROOT/evolution-flatpak"
WRAPPER="$BIN_DIR/evolution-flatpak-mail"
OFFICIAL_ICON="$HOME_DIR/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps/$APP_ID.svg"

BEGIN_MENU="# BEGIN CODEX EVOLUTION FLATPAK PERSONAL MENU"
END_MENU="# END CODEX EVOLUTION FLATPAK PERSONAL MENU"
OLD_BEGIN_MENU="# BEGIN CODEX EVOLUTION FLATPAK MENU"
OLD_END_MENU="# END CODEX EVOLUTION FLATPAK MENU"
BEGIN_TOOLBAR="# BEGIN CODEX EVOLUTION FLATPAK TOOLBAR"
END_TOOLBAR="# END CODEX EVOLUTION FLATPAK TOOLBAR"
BEGIN_STARTUP="# BEGIN CODEX EVOLUTION FLATPAK KEYRING"
END_STARTUP="# END CODEX EVOLUTION FLATPAK KEYRING"

usage() {
  cat <<EOF
Usage: $(basename "$0") inspect|install|validate|launch|uninstall

Commands:
  inspect    Print read-only IceWM, Flatpak, keyring, and icon state.
  install    Install the wrapper, Personal menu entry, toolbar entry, and keyring startup.
  validate   Check wrapper syntax, IceWM entries, official icon, Flatpak app, and /mail access.
  launch     Launch Evolution through the installed wrapper.
  uninstall  Remove the marked IceWM blocks and launcher wrapper.

No sudo is used. All changes are under the current user's home directory.
EOF
}

timestamp() {
  date +%Y%m%d-%H%M%S
}

log() {
  printf '%s\n' "$*"
}

resolved_icon() {
  if [ "${EVOLUTION_APP_ICON:-}" ]; then
    printf '%s\n' "$EVOLUTION_APP_ICON"
  elif [ -f "$OFFICIAL_ICON" ]; then
    printf '%s\n' "$OFFICIAL_ICON"
  else
    printf '%s\n' "$APP_ID"
  fi
}

print_file_head() {
  file=$1
  if [ -f "$file" ]; then
    log "--- $file ---"
    ls -l "$file"
    sed -n '1,180p' "$file"
  else
    log "--- missing: $file ---"
  fi
}

inspect_icon() {
  icon=$(resolved_icon)
  log "== Evolution icon =="
  log "Resolved IceWM icon: $icon"
  if [ -f "$OFFICIAL_ICON" ]; then
    ls -l "$OFFICIAL_ICON"
    file "$OFFICIAL_ICON" 2>/dev/null || true
    sha256sum "$OFFICIAL_ICON" 2>/dev/null || true
  else
    log "Official Flatpak SVG icon not found: $OFFICIAL_ICON"
  fi

  desktop="$HOME_DIR/.local/share/flatpak/exports/share/applications/$APP_ID.desktop"
  if [ -f "$desktop" ]; then
    log "--- Flatpak desktop metadata ---"
    grep -E '^(Name|GenericName|Comment|Exec|Icon|X-Flatpak)=' "$desktop" 2>/dev/null || true
  fi
}

inspect() {
  log "== host =="
  cat /etc/os-release 2>/dev/null || true
  uname -a 2>/dev/null || true
  id

  log "== IceWM =="
  command -v icewm || true
  icewm --version 2>/dev/null || true
  pgrep -fa 'icewm|icewm-session' 2>/dev/null || true

  log "== tools =="
  command -v flatpak || true
  command -v gnome-keyring-daemon || true
  command -v pgrep || true
  command -v sh || true
  command -v awk || true
  command -v sed || true
  command -v grep || true
  command -v mktemp || true

  log "== Flatpak Evolution =="
  flatpak --user info "$APP_ID" 2>/dev/null || true
  flatpak --user info --show-permissions "$APP_ID" 2>/dev/null || true

  log "== keyring/dbus processes =="
  echo "DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:+set}"
  pgrep -fa 'dbus|gnome-keyring' 2>/dev/null || true

  inspect_icon

  log "== IceWM directories =="
  for dir in "$ICEWM_DIR" /etc/icewm /usr/share/icewm /etc/X11/icewm; do
    if [ -d "$dir" ]; then
      log "--- $dir ---"
      ls -la "$dir" | sed -n '1,120p'
    else
      log "--- missing: $dir ---"
    fi
  done

  log "== user IceWM files =="
  print_file_head "$ICEWM_DIR/menu"
  print_file_head "$MENU_FILE"
  print_file_head "$TOOLBAR_FILE"
  print_file_head "$STARTUP_FILE"
  print_file_head "$ICEWM_DIR/preferences"

  log "== existing launcher markers =="
  grep -RIn 'CODEX EVOLUTION FLATPAK' "$ICEWM_DIR/menu" "$MENU_FILE" "$TOOLBAR_FILE" "$STARTUP_FILE" 2>/dev/null || true
}

backup_file() {
  file=$1
  backup_dir=$2
  if [ -e "$file" ]; then
    mkdir -p "$backup_dir"
    cp -p "$file" "$backup_dir/$(basename "$file")"
  fi
}

remove_marked_block() {
  file=$1
  begin=$2
  end=$3

  [ -f "$file" ] || return 0

  tmp=$(mktemp "${TMPDIR:-/tmp}/evolution-icewm.XXXXXX")
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skip = 1; next }
    $0 == end { skip = 0; next }
    skip != 1 { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

append_marked_block() {
  file=$1
  begin=$2
  end=$3
  block_file=$4

  remove_marked_block "$file" "$begin" "$end"
  if [ -s "$file" ]; then
    printf '\n' >> "$file"
  fi
  cat "$block_file" >> "$file"
}

install_wrapper() {
  mkdir -p "$BIN_DIR" "$STATE_DIR"

  cat > "$WRAPPER" <<'EOF'
#!/bin/sh
set -u

APP_ID=org.gnome.Evolution
STATE_ROOT=${XDG_STATE_HOME:-"$HOME/.local/state"}
STATE_DIR="$STATE_ROOT/evolution-flatpak"
LOG="$STATE_DIR/launcher.log"

mkdir -p "$STATE_DIR" 2>/dev/null || true

rotate_log() {
  [ -f "$LOG" ] || return 0
  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  case "$size" in
    ''|*[!0-9]*) size=0 ;;
  esac
  if [ "$size" -gt 1048576 ]; then
    mv "$LOG" "$LOG.1" 2>/dev/null || true
  fi
}

log_msg() {
  printf '%s %s\n' "$(date -Is 2>/dev/null || date)" "$*" >> "$LOG" 2>/dev/null || true
}

keyring_running() {
  command -v pgrep >/dev/null 2>&1 || return 1
  pgrep -u "$(id -u)" -x gnome-keyring-daemon >/dev/null 2>&1
}

rotate_log
log_msg "Evolution launcher requested"

if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! keyring_running; then
    gnome-keyring-daemon --start --components=secrets,pkcs11,ssh >/dev/null 2>&1 || \
      log_msg "gnome-keyring-daemon start returned non-zero"
  fi
else
  log_msg "gnome-keyring-daemon not found"
fi

if ! command -v flatpak >/dev/null 2>&1; then
  log_msg "flatpak command not found"
  exit 127
fi

exec flatpak --user run "$APP_ID" "$@"
EOF

  chmod 755 "$WRAPPER"
}

install_icewm_blocks() {
  icon=$(resolved_icon)

  mkdir -p "$ICEWM_DIR" "$STATE_DIR"
  backup_dir="$STATE_DIR/icewm-backup-$(timestamp)"
  mkdir -p "$backup_dir"

  backup_file "$ICEWM_DIR/menu" "$backup_dir"
  backup_file "$MENU_FILE" "$backup_dir"
  backup_file "$TOOLBAR_FILE" "$backup_dir"
  backup_file "$STARTUP_FILE" "$backup_dir"

  [ -f "$MENU_FILE" ] || : > "$MENU_FILE"
  [ -f "$TOOLBAR_FILE" ] || : > "$TOOLBAR_FILE"

  if [ ! -e "$STARTUP_FILE" ]; then
    printf '%s\n\n' '#!/bin/sh' > "$STARTUP_FILE"
  fi

  menu_block=$(mktemp "${TMPDIR:-/tmp}/evolution-menu.XXXXXX")
  toolbar_block=$(mktemp "${TMPDIR:-/tmp}/evolution-toolbar.XXXXXX")
  startup_block=$(mktemp "${TMPDIR:-/tmp}/evolution-startup.XXXXXX")

  {
    printf '%s\n' "$BEGIN_MENU"
    printf 'prog "%s" %s %s\n' "$APP_LABEL" "$icon" "$WRAPPER"
    printf '%s\n' "$END_MENU"
  } > "$menu_block"

  {
    printf '%s\n' "$BEGIN_TOOLBAR"
    printf 'prog "%s" %s %s\n' "$APP_LABEL" "$icon" "$WRAPPER"
    printf '%s\n' "$END_TOOLBAR"
  } > "$toolbar_block"

  {
    printf '%s\n' "$BEGIN_STARTUP"
    printf '%s\n' 'if command -v gnome-keyring-daemon >/dev/null 2>&1; then'
    printf '%s\n' '  gnome-keyring-daemon --start --components=secrets,pkcs11,ssh >/dev/null 2>&1 || true'
    printf '%s\n' 'fi'
    printf '%s\n' "$END_STARTUP"
  } > "$startup_block"

  remove_marked_block "$ICEWM_DIR/menu" "$OLD_BEGIN_MENU" "$OLD_END_MENU"
  append_marked_block "$MENU_FILE" "$BEGIN_MENU" "$END_MENU" "$menu_block"
  append_marked_block "$TOOLBAR_FILE" "$BEGIN_TOOLBAR" "$END_TOOLBAR" "$toolbar_block"
  append_marked_block "$STARTUP_FILE" "$BEGIN_STARTUP" "$END_STARTUP" "$startup_block"

  rm -f "$menu_block" "$toolbar_block" "$startup_block"
  chmod 644 "$MENU_FILE" "$TOOLBAR_FILE"
  chmod 755 "$STARTUP_FILE"

  log "Installed icon: $icon"
  log "Backups written under: $backup_dir"
}

restart_icewm() {
  if pgrep -u "$(id -u)" -x icewm >/dev/null 2>&1; then
    icewm --restart 2>/dev/null || log "IceWM restart command returned non-zero; log out and back in if menu/toolbar do not refresh."
  else
    log "IceWM process not detected; log out and back in if menu/toolbar do not refresh."
  fi
}

install() {
  install_wrapper
  sh -n "$WRAPPER"
  install_icewm_blocks
  validate
  restart_icewm
  log "Installed Evolution launcher: $WRAPPER"
}

validate() {
  fail=0
  icon=$(resolved_icon)

  log "== validate wrapper =="
  if [ -x "$WRAPPER" ]; then
    sh -n "$WRAPPER" || fail=1
    ls -l "$WRAPPER"
  else
    log "ERROR: wrapper missing or not executable: $WRAPPER"
    fail=1
  fi

  log "== validate official icon =="
  if [ -f "$OFFICIAL_ICON" ]; then
    ls -l "$OFFICIAL_ICON"
    sha256sum "$OFFICIAL_ICON" 2>/dev/null || true
  else
    log "ERROR: official Flatpak icon missing: $OFFICIAL_ICON"
    fail=1
  fi

  log "== validate IceWM entries =="
  if [ -f "$MENU_FILE" ] && grep -F "$WRAPPER" "$MENU_FILE" >/dev/null && grep -F "$icon" "$MENU_FILE" >/dev/null; then
    grep -F "$WRAPPER" "$MENU_FILE"
  else
    log "ERROR: missing Evolution wrapper/icon entry in $MENU_FILE"
    fail=1
  fi

  if [ -f "$TOOLBAR_FILE" ] && grep -F "$WRAPPER" "$TOOLBAR_FILE" >/dev/null && grep -F "$icon" "$TOOLBAR_FILE" >/dev/null; then
    grep -F "$WRAPPER" "$TOOLBAR_FILE"
  else
    log "ERROR: missing Evolution wrapper/icon entry in $TOOLBAR_FILE"
    fail=1
  fi

  if [ -f "$STARTUP_FILE" ] && grep -F 'gnome-keyring-daemon --start --components=secrets,pkcs11,ssh' "$STARTUP_FILE" >/dev/null; then
    grep -F 'gnome-keyring-daemon --start --components=secrets,pkcs11,ssh' "$STARTUP_FILE"
  else
    log "ERROR: missing keyring startup entry in $STARTUP_FILE"
    fail=1
  fi

  if [ -x "$STARTUP_FILE" ]; then
    ls -l "$STARTUP_FILE"
  else
    log "ERROR: $STARTUP_FILE is not executable"
    fail=1
  fi

  log "== validate Flatpak Evolution =="
  if flatpak --user info "$APP_ID" >/dev/null 2>&1; then
    flatpak --user info "$APP_ID" | sed -n '1,80p'
  else
    log "ERROR: Flatpak app is not installed for this user: $APP_ID"
    fail=1
  fi

  log "== validate /mail permission =="
  if flatpak --user info --show-permissions "$APP_ID" 2>/dev/null | grep -F '/mail:create' >/dev/null; then
    flatpak --user info --show-permissions "$APP_ID" | sed -n '1,120p'
  else
    log "ERROR: missing Flatpak /mail:create override"
    fail=1
  fi

  log "== validate keyring process =="
  if command -v gnome-keyring-daemon >/dev/null 2>&1; then
    gnome-keyring-daemon --start --components=secrets,pkcs11,ssh >/dev/null 2>&1 || true
    if pgrep -fa gnome-keyring 2>/dev/null; then
      :
    else
      log "WARNING: gnome-keyring-daemon did not show in pgrep output"
    fi
  else
    log "ERROR: gnome-keyring-daemon is not installed"
    fail=1
  fi

  return "$fail"
}

launch() {
  if [ ! -x "$WRAPPER" ]; then
    log "ERROR: wrapper is not installed: $WRAPPER"
    exit 1
  fi
  exec "$WRAPPER"
}

uninstall() {
  backup_dir="$STATE_DIR/icewm-backup-before-uninstall-$(timestamp)"
  mkdir -p "$backup_dir"
  backup_file "$ICEWM_DIR/menu" "$backup_dir"
  backup_file "$MENU_FILE" "$backup_dir"
  backup_file "$TOOLBAR_FILE" "$backup_dir"
  backup_file "$STARTUP_FILE" "$backup_dir"

  remove_marked_block "$ICEWM_DIR/menu" "$OLD_BEGIN_MENU" "$OLD_END_MENU"
  remove_marked_block "$MENU_FILE" "$BEGIN_MENU" "$END_MENU"
  remove_marked_block "$TOOLBAR_FILE" "$BEGIN_TOOLBAR" "$END_TOOLBAR"
  remove_marked_block "$STARTUP_FILE" "$BEGIN_STARTUP" "$END_STARTUP"
  rm -f "$WRAPPER"
  restart_icewm
  log "Removed marked IceWM blocks and wrapper. Backups written under: $backup_dir"
}

case "${1:-}" in
  inspect) inspect ;;
  install) install ;;
  validate) validate ;;
  launch) launch ;;
  uninstall) uninstall ;;
  -h|--help|help|'') usage ;;
  *)
    usage
    exit 2
    ;;
esac
