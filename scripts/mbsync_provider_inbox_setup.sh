#!/bin/sh
set -eu

PROFILE=${MBSYNC_PROFILE:-provider}
MAIL_ROOT=${MAIL_ROOT:-/mail}
HOME_DIR=${HOME:?HOME is not set}
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME_DIR/.config"}
CONFIG_FILE=${MBSYNC_CONFIG_FILE:-"$CONFIG_HOME/isyncrc"}
SECRET_DIR=${MBSYNC_SECRET_DIR:-"$CONFIG_HOME/isync"}
PASS_FILE=${MBSYNC_PASS_FILE:-"$SECRET_DIR/$PROFILE.pass"}
TEST_MAILDIR=${MBSYNC_TEST_MAILDIR:-"$MAIL_ROOT/Mailstore/mbsync/$PROFILE-inbox-test"}
LIVE_MAILDIR=${MBSYNC_LIVE_MAILDIR:-"$MAIL_ROOT/Mailstore/mbsync/$PROFILE-live"}
STATE_DIR=${MBSYNC_STATE_DIR:-"$MAIL_ROOT/AppData/isync/state/$PROFILE"}
LOG_DIR=${MBSYNC_LOG_DIR:-"$MAIL_ROOT/Logs/mbsync"}
NOTMUCH_DIR=${NOTMUCH_DIR:-"$MAIL_ROOT/SearchIndex/notmuch"}

ACCOUNT="$PROFILE"
REMOTE_STORE="$PROFILE-remote"
LOCAL_STORE="$PROFILE-local"
CHANNEL="$PROFILE-inbox"
BEGIN_MARKER="# BEGIN CODEX MBSYNC $PROFILE INBOX TEST"
END_MARKER="# END CODEX MBSYNC $PROFILE INBOX TEST"

usage() {
  cat <<EOF
Usage: $(basename "$0") inspect|install-packages|create-layout|write-config|list|dry-run|sync-once|status|redact-config

Commands:
  inspect           Print system, disk, package, and current mbsync state.
  install-packages  Run apt update and install isync, ca-certificates, and SASL modules.
  create-layout     Create the isolated /mail Maildir, state, log, and secret directories.
  write-config      Prompt for standard IMAP settings and write a pull-only INBOX config.
  list              List remote store mailboxes and the configured channel mailboxes.
  dry-run           Run a verbose mbsync simulation for the INBOX channel.
  sync-once         Run one real INBOX pull, saving the full log under /mail/Logs/mbsync.
  status            Print counts, disk usage, sync-state files, and redacted config.
  redact-config     Print the mbsync config with username and password command redacted.

Environment overrides:
  MBSYNC_PROFILE       Default: provider
  MAIL_ROOT            Default: /mail
  MBSYNC_CONFIG_FILE   Default: ~/.config/isyncrc
  MBSYNC_OVERWRITE_CONFIG=1 allows replacing a non-Codex existing config.

The generated channel uses Sync PullNew, Create Near, Remove None, and Expunge None.
It is intended for the first provider INBOX test only.
EOF
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

timestamp() {
  date +%Y%m%d-%H%M%S
}

validate_profile() {
  case "$PROFILE" in
    ''|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*)
      die "MBSYNC_PROFILE must contain only letters, digits, underscore, or dash"
      ;;
  esac
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

print_path() {
  path=$1
  if [ -e "$path" ]; then
    ls -ld "$path"
  else
    log "missing: $path"
  fi
}

inspect() {
  log "== system =="
  cat /etc/os-release 2>/dev/null || true
  uname -a 2>/dev/null || true
  id

  log "== disk =="
  df -hT / "$MAIL_ROOT" 2>/dev/null || true
  findmnt "$MAIL_ROOT" 2>/dev/null || true

  log "== current mail layout =="
  print_path "$MAIL_ROOT"
  print_path "$MAIL_ROOT/Mailstore"
  print_path "$MAIL_ROOT/Mailstore/evolution"
  print_path "$MAIL_ROOT/Mailstore/mbsync"
  print_path "$MAIL_ROOT/AppData"
  print_path "$MAIL_ROOT/AppData/isync"
  print_path "$MAIL_ROOT/Logs"
  print_path "$MAIL_ROOT/SearchIndex"

  log "== package candidates =="
  apt-cache policy isync ca-certificates libsasl2-modules notmuch astroid 2>/dev/null || true

  log "== current mbsync if installed =="
  command -v mbsync || true
  mbsync --version 2>/dev/null || true

  log "== existing config paths =="
  print_path "$CONFIG_FILE"
  print_path "$SECRET_DIR"
  print_path "$PASS_FILE"
  print_path "$TEST_MAILDIR"
  print_path "$STATE_DIR"
  print_path "$LOG_DIR"
}

install_packages() {
  need_cmd sudo
  need_cmd apt

  log "== apt update =="
  sudo apt update

  log "== install mbsync support packages =="
  sudo apt install isync ca-certificates libsasl2-modules

  log "== mbsync version =="
  mbsync --version
}

create_maildir() {
  dir=$1
  mkdir -p "$dir/cur" "$dir/new" "$dir/tmp"
  chmod 700 "$dir" "$dir/cur" "$dir/new" "$dir/tmp"
}

create_layout() {
  validate_profile

  mkdir -p "$MAIL_ROOT/Mailstore/mbsync" \
    "$MAIL_ROOT/AppData/isync/state" \
    "$LOG_DIR" \
    "$NOTMUCH_DIR" \
    "$SECRET_DIR"

  create_maildir "$TEST_MAILDIR"
  mkdir -p "$LIVE_MAILDIR" "$STATE_DIR"

  chmod 700 "$SECRET_DIR" \
    "$MAIL_ROOT/AppData/isync" \
    "$MAIL_ROOT/AppData/isync/state" \
    "$STATE_DIR" \
    "$LOG_DIR"

  log "== created layout =="
  print_path "$TEST_MAILDIR"
  print_path "$TEST_MAILDIR/cur"
  print_path "$TEST_MAILDIR/new"
  print_path "$TEST_MAILDIR/tmp"
  print_path "$LIVE_MAILDIR"
  print_path "$STATE_DIR"
  print_path "$LOG_DIR"
  print_path "$NOTMUCH_DIR"
  print_path "$SECRET_DIR"
}

prompt_if_empty() {
  var_name=$1
  prompt=$2
  current=$3

  if [ -n "$current" ]; then
    printf '%s\n' "$current"
    return 0
  fi

  printf '%s' "$prompt" >&2
  IFS= read -r value
  printf '%s\n' "$value"
}

read_password() {
  if [ -n "${IMAP_PASS-}" ]; then
    printf '%s\n' "$IMAP_PASS"
    return 0
  fi

  printf 'IMAP app password: ' >&2
  if [ -t 0 ]; then
    old_stty=$(stty -g 2>/dev/null || true)
    stty -echo 2>/dev/null || true
    IFS= read -r value
    if [ -n "$old_stty" ]; then
      stty "$old_stty" 2>/dev/null || true
    else
      stty echo 2>/dev/null || true
    fi
    printf '\n' >&2
  else
    IFS= read -r value
  fi
  printf '%s\n' "$value"
}

backup_file() {
  file=$1
  if [ -e "$file" ]; then
    backup="$file.codex-backup-$(timestamp)"
    cp -p "$file" "$backup"
    log "Backed up existing file: $backup"
  fi
}

shell_single_quote() {
  printf "'"
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

write_config() {
  validate_profile
  create_layout

  if [ -f "$CONFIG_FILE" ] && ! grep -F "$BEGIN_MARKER" "$CONFIG_FILE" >/dev/null 2>&1; then
    if [ "${MBSYNC_OVERWRITE_CONFIG:-0}" != "1" ]; then
      die "$CONFIG_FILE exists and is not marked as a Codex mbsync test config. Set MBSYNC_OVERWRITE_CONFIG=1 to replace it after reviewing."
    fi
  fi

  IMAP_HOST=$(prompt_if_empty IMAP_HOST "IMAP host, example imap.example.com: " "${IMAP_HOST-}")
  IMAP_USER=$(prompt_if_empty IMAP_USER "IMAP username/email: " "${IMAP_USER-}")
  IMAP_PORT=${IMAP_PORT:-993}
  IMAP_PASS_VALUE=$(read_password)

  [ -n "$IMAP_HOST" ] || die "IMAP host is required"
  [ -n "$IMAP_USER" ] || die "IMAP username is required"
  [ -n "$IMAP_PASS_VALUE" ] || die "IMAP password is required"

  mkdir -p "$CONFIG_HOME" "$SECRET_DIR"
  chmod 700 "$SECRET_DIR"

  printf '%s\n' "$IMAP_PASS_VALUE" > "$PASS_FILE"
  chmod 600 "$PASS_FILE"
  pass_cmd_path=$(shell_single_quote "$PASS_FILE")

  backup_file "$CONFIG_FILE"

  cat > "$CONFIG_FILE" <<EOF
$BEGIN_MARKER
# First-pass standard IMAP INBOX pull into an isolated Maildir under /mail.
# No push, delete propagation, or expunge is enabled.
FSync yes

IMAPAccount $ACCOUNT
Host $IMAP_HOST
Port $IMAP_PORT
User $IMAP_USER
PassCmd "cat $pass_cmd_path"
TLSType IMAPS
SystemCertificates yes
Timeout 60

IMAPStore $REMOTE_STORE
Account $ACCOUNT

MaildirStore $LOCAL_STORE
Inbox $TEST_MAILDIR
SubFolders Maildir++

Channel $CHANNEL
Far :$REMOTE_STORE:
Near :$LOCAL_STORE:
Sync PullNew
Create Near
Remove None
Expunge None
CopyArrivalDate yes
SyncState $STATE_DIR/
$END_MARKER
EOF

  chmod 600 "$CONFIG_FILE"

  log "== wrote pull-only mbsync config =="
  redact_config
}

redact_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    die "missing config: $CONFIG_FILE"
  fi

  sed \
    -e 's/^User .*/User ***REDACTED***/' \
    -e 's/^PassCmd .*/PassCmd ***REDACTED***/' \
    "$CONFIG_FILE"
}

require_config() {
  [ -f "$CONFIG_FILE" ] || die "missing config: $CONFIG_FILE"
  need_cmd mbsync
}

list_mailboxes() {
  require_config

  log "== list remote store =="
  mbsync -c "$CONFIG_FILE" --list-stores "$REMOTE_STORE"

  log "== list channel mailboxes =="
  mbsync -c "$CONFIG_FILE" --list "$CHANNEL"
}

dry_run() {
  require_config

  log "== dry run =="
  mbsync -c "$CONFIG_FILE" --dry-run -V "$CHANNEL"
}

sync_once() {
  require_config
  mkdir -p "$LOG_DIR"
  chmod 700 "$LOG_DIR"

  log_file="$LOG_DIR/$(timestamp)-$CHANNEL.log"

  log "== real pull: $CHANNEL =="
  if mbsync -c "$CONFIG_FILE" -V "$CHANNEL" > "$log_file" 2>&1; then
    cat "$log_file"
  else
    status=$?
    cat "$log_file"
    log "mbsync failed; full log: $log_file"
    exit "$status"
  fi

  log "== saved log =="
  ls -l "$log_file"

  status
}

count_files() {
  dir=$1
  if [ -d "$dir" ]; then
    find "$dir" -type f | wc -l
  else
    printf '0\n'
  fi
}

status() {
  log "== config policy =="
  if [ -f "$CONFIG_FILE" ]; then
    grep -E '^(Sync|Create|Remove|Expunge|CopyArrivalDate|SyncState|Far|Near|Inbox) ' "$CONFIG_FILE" || true
  else
    log "missing config: $CONFIG_FILE"
  fi

  log "== local message files =="
  cur_count=$(count_files "$TEST_MAILDIR/cur")
  new_count=$(count_files "$TEST_MAILDIR/new")
  log "cur: $cur_count"
  log "new: $new_count"
  log "total: $((cur_count + new_count))"

  log "== disk usage =="
  du -sh "$TEST_MAILDIR" "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true

  log "== sync state =="
  find "$STATE_DIR" -maxdepth 1 -type f -print 2>/dev/null | sed -n '1,40p' || true

  log "== sample files =="
  find "$TEST_MAILDIR/cur" "$TEST_MAILDIR/new" -type f 2>/dev/null | sed -n '1,10p' || true

  log "== redacted config =="
  if [ -f "$CONFIG_FILE" ]; then
    redact_config
  fi
}

validate_profile

case "${1:-}" in
  inspect) inspect ;;
  install-packages) install_packages ;;
  create-layout) create_layout ;;
  write-config) write_config ;;
  list) list_mailboxes ;;
  dry-run) dry_run ;;
  sync-once) sync_once ;;
  status) status ;;
  redact-config) redact_config ;;
  -h|--help|help|'') usage ;;
  *)
    usage
    exit 2
    ;;
esac
