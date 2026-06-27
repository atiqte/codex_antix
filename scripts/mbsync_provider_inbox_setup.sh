#!/bin/sh
set -eu

PROFILE=${MBSYNC_PROFILE:-provider}
MARKER_PROFILE=${MBSYNC_MARKER_PROFILE:-}
if [ -z "$MARKER_PROFILE" ]; then
  case "$PROFILE" in
    provider) MARKER_PROFILE=PROVIDER ;;
    *) MARKER_PROFILE=$PROFILE ;;
  esac
fi
MAIL_ROOT=${MAIL_ROOT:-/mail}
HOME_DIR=${HOME:?HOME is not set}
CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME_DIR/.config"}
CONFIG_FILE=${MBSYNC_CONFIG_FILE:-"$CONFIG_HOME/isyncrc"}
SECRET_DIR=${MBSYNC_SECRET_DIR:-"$CONFIG_HOME/isync"}
PASS_FILE=${MBSYNC_PASS_FILE:-"$SECRET_DIR/$PROFILE.pass"}
TEST_MAILDIR=${MBSYNC_TEST_MAILDIR:-"$MAIL_ROOT/Mailstore/mbsync/$PROFILE-inbox-test"}
LIVE_MAILDIR=${MBSYNC_LIVE_MAILDIR:-"$MAIL_ROOT/Mailstore/mbsync/$PROFILE-live"}
STATE_DIR=${MBSYNC_STATE_DIR:-"$MAIL_ROOT/AppData/isync/state/$PROFILE"}
LIVE_STATE_DIR=${MBSYNC_LIVE_STATE_DIR:-"$MAIL_ROOT/AppData/isync/state/$PROFILE-live"}
LOG_DIR=${MBSYNC_LOG_DIR:-"$MAIL_ROOT/Logs/mbsync"}
LIVE_LOG_DIR=${MBSYNC_LIVE_LOG_DIR:-"$MAIL_ROOT/Logs/mbsync-live"}
LIVE_LOOP_STATE_DIR=${MBSYNC_LIVE_LOOP_STATE_DIR:-"$MAIL_ROOT/AppData/isync/$PROFILE-live-loop"}
NOTMUCH_DIR=${NOTMUCH_DIR:-"$MAIL_ROOT/SearchIndex/notmuch"}
BIN_DIR=${MBSYNC_BIN_DIR:-"$HOME_DIR/.local/bin"}
LOOP_SCRIPT=${MBSYNC_LIVE_LOOP_SCRIPT:-"$BIN_DIR/mbsync-$PROFILE-live-loop"}
CONTROL_SCRIPT=${MBSYNC_LIVE_CONTROL_SCRIPT:-"$BIN_DIR/mbsync-$PROFILE-live-control"}
ICEWM_STARTUP=${MBSYNC_ICEWM_STARTUP:-"$HOME_DIR/.icewm/startup"}
SENT_MAILBOX=${MBSYNC_SENT_MAILBOX:-Sent}
LIVE_PATTERNS=${MBSYNC_LIVE_PATTERNS:-'"INBOX" "Drafts" "Trash" "spam" "Junk" "Archive"'}

ACCOUNT="$PROFILE"
REMOTE_STORE="$PROFILE-remote"
LOCAL_STORE="$PROFILE-local"
CHANNEL="$PROFILE-inbox"
LIVE_LOCAL_STORE="$PROFILE-live-local"
LIVE_CHANNEL="$PROFILE-live"
LIVE_SENT_CHANNEL="$PROFILE-live-sent-upload"
LIVE_GROUP="$PROFILE-live-group"
BEGIN_MARKER="# BEGIN CODEX MBSYNC $MARKER_PROFILE INBOX TEST"
END_MARKER="# END CODEX MBSYNC $MARKER_PROFILE INBOX TEST"
LIVE_BEGIN_MARKER="# BEGIN CODEX MBSYNC $MARKER_PROFILE LIVE"
LIVE_END_MARKER="# END CODEX MBSYNC $MARKER_PROFILE LIVE"
STARTUP_BEGIN_MARKER="# BEGIN CODEX MBSYNC $MARKER_PROFILE LIVE AUTOSYNC"
STARTUP_END_MARKER="# END CODEX MBSYNC $MARKER_PROFILE LIVE AUTOSYNC"

usage() {
  cat <<EOF
Usage: $(basename "$0") COMMAND

Commands:
  inspect           Print system, disk, package, and current mbsync state.
  install-packages  Run apt update and install isync, ca-certificates, and SASL modules.
  create-layout     Create the isolated /mail Maildir, state, log, and secret directories.
  write-config      Prompt for standard IMAP settings and write a pull-only INBOX config.
  list              List remote store mailboxes and the configured channel mailboxes.
  dry-run           Run a verbose mbsync simulation for the INBOX channel.
  sync-once         Run one real INBOX pull, saving the full log under /mail/Logs/mbsync.
  status            Print counts, disk usage, sync-state files, and redacted config.
  production-layout Create production provider-live Maildir, state, log, and loop paths.
  write-production-config
                    Append or replace the validated provider-live production block.
  production-list   List production provider-live, Sent upload, and group mappings.
  production-sync   Run one provider-live-group sync and save a log.
  production-status Print provider-live counts, state, logs, controls, and redacted config.
  write-autosync    Write provider-live loop/control scripts with hardened controls.
  install-autosync-startup
                    Add a marked IceWM startup block for provider-live auto-sync.
  autosync-status   Print provider-live auto-sync status through the control script.
  autosync-preflight
                    Read-only audit of provider-live scripts, logs, and controls.
  refresh-autosync  Pause, stop, backup, rewrite, and syntax-check auto-sync scripts.
  autosync-validate Resume, sync once, start loop, and audit provider-live state.
  autosync-stale-lock-proof
                    Prove stale lock visibility and safe clear-stale-lock behavior.
  autosync-log-rotation-proof
                    Prove cleanup compresses, deletes, keeps, and removes test logs.
  redact-config     Print the mbsync config with username and password command redacted.

Environment overrides:
  MBSYNC_PROFILE       Default: provider
  MBSYNC_MARKER_PROFILE Default: PROVIDER for provider, otherwise profile name
  MAIL_ROOT            Default: /mail
  MBSYNC_CONFIG_FILE   Default: ~/.config/isyncrc
  MBSYNC_LIVE_PATTERNS Default: "INBOX" "Drafts" "Trash" "spam" "Junk" "Archive"
  MBSYNC_SENT_MAILBOX  Default: Sent
  MBSYNC_AUTO_LOG_COMPRESS_DAYS Default: 2
  MBSYNC_AUTO_LOG_DELETE_DAYS   Default: 30
  MBSYNC_MANUAL_LOG_DELETE_DAYS Default: 90
  MBSYNC_PROVIDER_LIVE_SYNC_TIMEOUT_SECONDS Default: 3600
  MBSYNC_AUTOSYNC_VALIDATE_SLEEP_SECONDS Default: 8
  MBSYNC_OVERWRITE_CONFIG=1 allows replacing a non-Codex existing config.

The generated channel uses Sync PullNew, Create Near, Remove None, and Expunge None.
The production provider-live block keeps normal folders receive-only and enables
PushNew only for the Sent folder.
Generated provider-live controls include logs, cleanup-logs, timeout visibility,
sync lock age, stale loop PID protection, and clear-stale-lock.
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

config_has_inbox_marker() {
  [ -f "$CONFIG_FILE" ] || return 1
  grep -F "$BEGIN_MARKER" "$CONFIG_FILE" >/dev/null 2>&1 && return 0
  grep -F "# BEGIN CODEX MBSYNC $PROFILE INBOX TEST" "$CONFIG_FILE" >/dev/null 2>&1 && return 0
  return 1
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
  print_path "$LIVE_MAILDIR"
  print_path "$STATE_DIR"
  print_path "$LIVE_STATE_DIR"
  print_path "$LOG_DIR"
  print_path "$LIVE_LOG_DIR"
  print_path "$LIVE_LOOP_STATE_DIR"
  print_path "$LOOP_SCRIPT"
  print_path "$CONTROL_SCRIPT"
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

create_production_layout() {
  validate_profile

  mkdir -p "$MAIL_ROOT/Mailstore/mbsync" \
    "$MAIL_ROOT/AppData/isync/state" \
    "$LIVE_STATE_DIR" \
    "$LIVE_LOG_DIR" \
    "$LIVE_LOOP_STATE_DIR" \
    "$BIN_DIR"

  create_maildir "$LIVE_MAILDIR"
  create_maildir "$LIVE_MAILDIR/.$SENT_MAILBOX"

  chmod 700 "$MAIL_ROOT/AppData/isync" \
    "$MAIL_ROOT/AppData/isync/state" \
    "$LIVE_STATE_DIR" \
    "$LIVE_LOG_DIR" \
    "$LIVE_LOOP_STATE_DIR" \
    "$BIN_DIR"

  log "== created production layout =="
  print_path "$LIVE_MAILDIR"
  print_path "$LIVE_MAILDIR/cur"
  print_path "$LIVE_MAILDIR/new"
  print_path "$LIVE_MAILDIR/tmp"
  print_path "$LIVE_MAILDIR/.$SENT_MAILBOX"
  print_path "$LIVE_STATE_DIR"
  print_path "$LIVE_LOG_DIR"
  print_path "$LIVE_LOOP_STATE_DIR"
  print_path "$BIN_DIR"
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

  if [ -f "$CONFIG_FILE" ] && ! config_has_inbox_marker; then
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
PipelineDepth 1

IMAPStore $REMOTE_STORE
Account $ACCOUNT
UseNamespace yes

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

backup_to_mail() {
  label=$1
  backup_dir="$MAIL_ROOT/Backups/mbsync/$(timestamp)-$label"
  mkdir -p "$backup_dir"
  chmod 700 "$MAIL_ROOT/Backups" "$MAIL_ROOT/Backups/mbsync" "$backup_dir" 2>/dev/null || true
  printf '%s\n' "$backup_dir"
}

remove_live_block() {
  input=$1
  output=$2
  old_begin="# BEGIN CODEX MBSYNC $PROFILE LIVE"
  old_end="# END CODEX MBSYNC $PROFILE LIVE"
  provider_begin="# BEGIN CODEX MBSYNC PROVIDER LIVE"
  provider_end="# END CODEX MBSYNC PROVIDER LIVE"
  awk -v begin="$LIVE_BEGIN_MARKER" -v end="$LIVE_END_MARKER" \
    -v old_begin="$old_begin" -v old_end="$old_end" \
    -v provider_begin="$provider_begin" -v provider_end="$provider_end" '
      $0 == begin || $0 == old_begin || $0 == provider_begin { skip = 1; next }
      $0 == end || $0 == old_end || $0 == provider_end { skip = 0; next }
      !skip { print }
    ' "$input" > "$output"
}

warn_live_base_config() {
  grep -F "PipelineDepth 1" "$CONFIG_FILE" >/dev/null 2>&1 || \
    log "WARNING: expected PipelineDepth 1 under IMAPAccount $ACCOUNT"
  grep -F "UseNamespace yes" "$CONFIG_FILE" >/dev/null 2>&1 || \
    log "WARNING: expected UseNamespace yes under IMAPStore $REMOTE_STORE"
}

write_production_config() {
  validate_profile
  [ -f "$CONFIG_FILE" ] || die "missing config: $CONFIG_FILE"
  grep -F "IMAPAccount $ACCOUNT" "$CONFIG_FILE" >/dev/null 2>&1 || die "missing IMAPAccount $ACCOUNT"
  grep -F "IMAPStore $REMOTE_STORE" "$CONFIG_FILE" >/dev/null 2>&1 || die "missing IMAPStore $REMOTE_STORE"

  create_production_layout
  warn_live_base_config

  backup_dir=$(backup_to_mail "before-provider-live-config")
  cp -p "$CONFIG_FILE" "$backup_dir/isyncrc.before-provider-live"
  log "Backed up config to: $backup_dir/isyncrc.before-provider-live"

  tmp_config=$(mktemp)
  remove_live_block "$CONFIG_FILE" "$tmp_config"

  cat >> "$tmp_config" <<EOF

$LIVE_BEGIN_MARKER
# Production Maildir tree under /mail.
# Receive-only for normal folders; $SENT_MAILBOX has a narrow PushNew-only upload path.
MaildirStore $LIVE_LOCAL_STORE
Inbox $LIVE_MAILDIR
SubFolders Maildir++

Channel $LIVE_CHANNEL
Far :$REMOTE_STORE:
Near :$LIVE_LOCAL_STORE:
Patterns $LIVE_PATTERNS
Sync PullNew
Create Near
Remove None
Expunge None
CopyArrivalDate yes
SyncState $LIVE_STATE_DIR/

Channel $LIVE_SENT_CHANNEL
Far :$REMOTE_STORE:$SENT_MAILBOX
Near :$LIVE_LOCAL_STORE:$SENT_MAILBOX
Sync PullNew PushNew
Create None
Remove None
Expunge None
CopyArrivalDate yes
SyncState $LIVE_STATE_DIR/

Group $LIVE_GROUP
Channel $LIVE_CHANNEL
Channel $LIVE_SENT_CHANNEL
$LIVE_END_MARKER
EOF

  install -m 600 "$tmp_config" "$CONFIG_FILE"
  rm -f "$tmp_config"

  log "== wrote production provider-live config =="
  awk -v begin="$LIVE_BEGIN_MARKER" -v end="$LIVE_END_MARKER" '
    $0 == begin { show = 1 }
    show { print }
    $0 == end { show = 0 }
  ' "$CONFIG_FILE"
}

production_list() {
  require_config

  log "== list remote store =="
  mbsync -c "$CONFIG_FILE" --list-stores "$REMOTE_STORE"

  log "== list production receive-only channel =="
  mbsync -c "$CONFIG_FILE" --list "$LIVE_CHANNEL"

  log "== list Sent upload channel =="
  mbsync -c "$CONFIG_FILE" --list "$LIVE_SENT_CHANNEL"

  log "== list production group =="
  mbsync -c "$CONFIG_FILE" --list "$LIVE_GROUP"
}

production_sync() {
  require_config
  mkdir -p "$LIVE_LOG_DIR"
  chmod 700 "$LIVE_LOG_DIR"

  log_file="$LIVE_LOG_DIR/$(timestamp)-$LIVE_GROUP.log"

  log "== real sync: $LIVE_GROUP =="
  if mbsync -c "$CONFIG_FILE" -V "$LIVE_GROUP" > "$log_file" 2>&1; then
    cat "$log_file"
  else
    status=$?
    cat "$log_file"
    log "mbsync failed; full log: $log_file"
    exit "$status"
  fi

  log "== saved log =="
  ls -l "$log_file"

  production_status
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

production_status() {
  log "== production config policy =="
  if [ -f "$CONFIG_FILE" ]; then
    awk -v begin="$LIVE_BEGIN_MARKER" -v end="$LIVE_END_MARKER" '
      $0 == begin { show = 1 }
      show { print }
      $0 == end { show = 0 }
    ' "$CONFIG_FILE" | sed \
      -e 's/^User .*/User ***REDACTED***/' \
      -e 's/^PassCmd .*/PassCmd ***REDACTED***/'
  else
    log "missing config: $CONFIG_FILE"
  fi

  log "== production channel mappings =="
  if command -v mbsync >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
    mbsync -c "$CONFIG_FILE" --list "$LIVE_CHANNEL" 2>/dev/null || true
    mbsync -c "$CONFIG_FILE" --list "$LIVE_SENT_CHANNEL" 2>/dev/null || true
  fi

  log "== provider-live folder counts =="
  for dir in "$LIVE_MAILDIR" "$LIVE_MAILDIR"/.*; do
    [ -d "$dir" ] || continue
    base=$(basename "$dir")
    [ "$base" = "." ] && continue
    [ "$base" = ".." ] && continue
    [ -d "$dir/cur" ] || continue

    if [ "$dir" = "$LIVE_MAILDIR" ]; then
      name=INBOX
    else
      name=${base#.}
    fi

    cur_new=$(find "$dir/cur" "$dir/new" -type f 2>/dev/null | wc -l)
    tmp_count=$(find "$dir/tmp" -type f 2>/dev/null | wc -l)
    printf '%-20s messages=%s tmp=%s\n' "$name" "$cur_new" "$tmp_count"
  done | sort

  log "== disk usage =="
  du -sh "$LIVE_MAILDIR" "$LIVE_STATE_DIR" "$LIVE_LOG_DIR" 2>/dev/null || true

  log "== production state files =="
  find "$LIVE_STATE_DIR" -maxdepth 1 -type f -print 2>/dev/null | sort | sed -n '1,40p' || true

  log "== auto-sync scripts =="
  print_path "$LOOP_SCRIPT"
  print_path "$CONTROL_SCRIPT"
  print_path "$ICEWM_STARTUP"
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" status || true
  fi
}

write_autosync() {
  validate_profile
  create_production_layout
  mkdir -p "$BIN_DIR"
  chmod 700 "$BIN_DIR"

  backup_dir=$(backup_to_mail "before-provider-live-autosync")
  [ ! -e "$LOOP_SCRIPT" ] || cp -p "$LOOP_SCRIPT" "$backup_dir/$(basename "$LOOP_SCRIPT").before"
  [ ! -e "$CONTROL_SCRIPT" ] || cp -p "$CONTROL_SCRIPT" "$backup_dir/$(basename "$CONTROL_SCRIPT").before"
  log "Backed up existing auto-sync scripts, if any, to: $backup_dir"

  cat > "$LOOP_SCRIPT" <<'EOF'
#!/bin/sh
set -u

PROFILE=${MBSYNC_PROFILE:-provider}
MAIL_ROOT=${MAIL_ROOT:-/mail}
CONFIG=${MBSYNC_CONFIG_FILE:-"$HOME/.config/isyncrc"}
CHANNEL=${MBSYNC_LIVE_GROUP:-"$PROFILE-live-group"}
STATE_DIR=${MBSYNC_LIVE_LOOP_STATE_DIR:-"$MAIL_ROOT/AppData/isync/$PROFILE-live-loop"}
LOG_DIR=${MBSYNC_LIVE_LOG_DIR:-"$MAIL_ROOT/Logs/mbsync-live"}
INTERVAL_SECONDS=${MBSYNC_PROVIDER_LIVE_INTERVAL_SECONDS:-180}
SYNC_TIMEOUT_SECONDS=${MBSYNC_PROVIDER_LIVE_SYNC_TIMEOUT_SECONDS:-3600}
AUTO_LOG_COMPRESS_DAYS=${MBSYNC_AUTO_LOG_COMPRESS_DAYS:-2}
AUTO_LOG_DELETE_DAYS=${MBSYNC_AUTO_LOG_DELETE_DAYS:-30}
MANUAL_LOG_DELETE_DAYS=${MBSYNC_MANUAL_LOG_DELETE_DAYS:-90}

case "$SYNC_TIMEOUT_SECONDS" in
  ''|*[!0-9]*) SYNC_TIMEOUT_SECONDS=3600 ;;
esac

LOCK_DIR="$STATE_DIR/lock"
PAUSE_FILE="$STATE_DIR/paused"
STOP_FILE="$STATE_DIR/stop"
PID_FILE="$STATE_DIR/loop.pid"
LAST_STATUS="$STATE_DIR/last-status.txt"
CLEANUP_STAMP="$STATE_DIR/log-cleanup-date"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_STARTED_EPOCH_FILE="$LOCK_DIR/started_epoch"
LOCK_STARTED_AT_FILE="$LOCK_DIR/started_at"
LOCK_CHANNEL_FILE="$LOCK_DIR/channel"

mkdir -p "$STATE_DIR" "$LOG_DIR"
chmod 700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true
echo "$$" > "$PID_FILE"
rm -f "$STOP_FILE"

log_line() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*"
}

write_lock_metadata() {
  now_epoch=$(date +%s)
  printf '%s\n' "$$" > "$LOCK_PID_FILE"
  printf '%s\n' "$now_epoch" > "$LOCK_STARTED_EPOCH_FILE"
  date '+%Y-%m-%d %H:%M:%S%z' > "$LOCK_STARTED_AT_FILE"
  printf '%s\n' "$CHANNEL" > "$LOCK_CHANNEL_FILE"
}

clear_lock() {
  rm -f "$LOCK_PID_FILE" "$LOCK_STARTED_EPOCH_FILE" "$LOCK_STARTED_AT_FILE" "$LOCK_CHANNEL_FILE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

clear_lock_if_owned() {
  [ -f "$LOCK_PID_FILE" ] || return 0
  owner_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
  [ "$owner_pid" = "$$" ] && clear_lock
}

run_mbsync_with_timeout() {
  if command -v timeout >/dev/null 2>&1 && [ "$SYNC_TIMEOUT_SECONDS" -gt 0 ]; then
    if timeout --help 2>&1 | grep -q -- '--kill-after'; then
      timeout --kill-after=60s "$SYNC_TIMEOUT_SECONDS" mbsync -c "$CONFIG" "$CHANNEL"
    else
      timeout "$SYNC_TIMEOUT_SECONDS" mbsync -c "$CONFIG" "$CHANNEL"
    fi
  else
    mbsync -c "$CONFIG" "$CHANNEL"
  fi
}

cleanup_logs() {
  [ -d "$LOG_DIR" ] || return 0

  if command -v gzip >/dev/null 2>&1; then
    find "$LOG_DIR" -maxdepth 1 -type f -name "????????-$PROFILE-live-auto.log" \
      -mtime +"$AUTO_LOG_COMPRESS_DAYS" -exec gzip -f {} \; 2>/dev/null || true
  fi

  find "$LOG_DIR" -maxdepth 1 -type f -name "????????-$PROFILE-live-auto.log.gz" \
    -mtime +"$AUTO_LOG_DELETE_DAYS" -exec rm -f {} \; 2>/dev/null || true
  find "$LOG_DIR" -maxdepth 1 -type f -name "????????-$PROFILE-live-auto.log" \
    -mtime +"$AUTO_LOG_DELETE_DAYS" -exec rm -f {} \; 2>/dev/null || true
  find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" \
    ! -name "????????-$PROFILE-live-auto.log" \
    -mtime +"$MANUAL_LOG_DELETE_DAYS" -exec rm -f {} \; 2>/dev/null || true
}

cleanup_logs_if_due() {
  today=$(date +%Y%m%d)
  last_cleanup=$(cat "$CLEANUP_STAMP" 2>/dev/null || true)

  if [ "$last_cleanup" != "$today" ]; then
    cleanup_logs
    printf '%s\n' "$today" > "$CLEANUP_STAMP"
  fi
}

run_sync_once() {
  log_file="$LOG_DIR/$(date +%Y%m%d)-$PROFILE-live-auto.log"

  if [ -e "$PAUSE_FILE" ]; then
    log_line "paused; skipping sync" >> "$log_file"
    printf '%s\n' "paused $(date '+%Y-%m-%d %H:%M:%S%z')" > "$LAST_STATUS"
    return 0
  fi

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    log_line "lock exists; previous sync still running, skipping" >> "$log_file"
    printf '%s\n' "locked $(date '+%Y-%m-%d %H:%M:%S%z')" > "$LAST_STATUS"
    return 0
  fi
  write_lock_metadata

  {
    log_line "sync start timeout=${SYNC_TIMEOUT_SECONDS}s"
    run_mbsync_with_timeout
    rc=$?
    case "$rc" in
      124|137) log_line "sync timed out or was killed after ${SYNC_TIMEOUT_SECONDS}s" ;;
    esac
    log_line "sync exit=$rc"
    printf '%s\n' "last_exit=$rc $(date '+%Y-%m-%d %H:%M:%S%z')" > "$LAST_STATUS"
    clear_lock
    return "$rc"
  } >> "$log_file" 2>&1
}

trap 'rm -f "$PID_FILE"; clear_lock_if_owned; exit 0' INT TERM HUP
cleanup_logs_if_due
log_line "loop start interval=${INTERVAL_SECONDS}s timeout=${SYNC_TIMEOUT_SECONDS}s pid=$$" >> "$LOG_DIR/$(date +%Y%m%d)-$PROFILE-live-auto.log"

while :; do
  cleanup_logs_if_due

  if [ -e "$STOP_FILE" ]; then
    log_line "stop file found; loop exiting" >> "$LOG_DIR/$(date +%Y%m%d)-$PROFILE-live-auto.log"
    rm -f "$STOP_FILE" "$PID_FILE"
    exit 0
  fi

  run_sync_once || true

  slept=0
  while [ "$slept" -lt "$INTERVAL_SECONDS" ]; do
    if [ -e "$STOP_FILE" ]; then
      log_line "stop file found during sleep; loop exiting" >> "$LOG_DIR/$(date +%Y%m%d)-$PROFILE-live-auto.log"
      rm -f "$STOP_FILE" "$PID_FILE"
      exit 0
    fi
    sleep 5
    slept=$((slept + 5))
  done
done
EOF

  cat > "$CONTROL_SCRIPT" <<'EOF'
#!/bin/sh
set -u

PROFILE=${MBSYNC_PROFILE:-provider}
MAIL_ROOT=${MAIL_ROOT:-/mail}
CONFIG=${MBSYNC_CONFIG_FILE:-"$HOME/.config/isyncrc"}
CHANNEL=${MBSYNC_LIVE_GROUP:-"$PROFILE-live-group"}
STATE_DIR=${MBSYNC_LIVE_LOOP_STATE_DIR:-"$MAIL_ROOT/AppData/isync/$PROFILE-live-loop"}
LOG_DIR=${MBSYNC_LIVE_LOG_DIR:-"$MAIL_ROOT/Logs/mbsync-live"}
LOOP=${MBSYNC_LIVE_LOOP_SCRIPT:-"$HOME/.local/bin/mbsync-$PROFILE-live-loop"}
AUTO_LOG_COMPRESS_DAYS=${MBSYNC_AUTO_LOG_COMPRESS_DAYS:-2}
AUTO_LOG_DELETE_DAYS=${MBSYNC_AUTO_LOG_DELETE_DAYS:-30}
MANUAL_LOG_DELETE_DAYS=${MBSYNC_MANUAL_LOG_DELETE_DAYS:-90}
SYNC_TIMEOUT_SECONDS=${MBSYNC_PROVIDER_LIVE_SYNC_TIMEOUT_SECONDS:-3600}

case "$SYNC_TIMEOUT_SECONDS" in
  ''|*[!0-9]*) SYNC_TIMEOUT_SECONDS=3600 ;;
esac

LOCK_DIR="$STATE_DIR/lock"
PAUSE_FILE="$STATE_DIR/paused"
STOP_FILE="$STATE_DIR/stop"
PID_FILE="$STATE_DIR/loop.pid"
LAST_STATUS="$STATE_DIR/last-status.txt"
CLEANUP_STAMP="$STATE_DIR/log-cleanup-date"
LOCK_PID_FILE="$LOCK_DIR/pid"
LOCK_STARTED_EPOCH_FILE="$LOCK_DIR/started_epoch"
LOCK_STARTED_AT_FILE="$LOCK_DIR/started_at"
LOCK_CHANNEL_FILE="$LOCK_DIR/channel"

mkdir -p "$STATE_DIR" "$LOG_DIR"
chmod 700 "$STATE_DIR" "$LOG_DIR" 2>/dev/null || true

is_loop_running() {
  if [ -s "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if pid_is_loop "$pid"; then
      return 0
    fi
  fi
  pgrep -f "mbsync-$PROFILE-live-loop" >/dev/null 2>&1
}

pid_is_loop() {
  pid=${1:-}
  case "$pid" in
    ''|*[!0-9]*) return 1 ;;
  esac
  kill -0 "$pid" 2>/dev/null || return 1

  if command -v ps >/dev/null 2>&1; then
    cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
    [ -n "$cmd" ] || return 1
    case "$cmd" in
      *"mbsync-$PROFILE-live-loop"*) return 0 ;;
      *) return 1 ;;
    esac
  fi

  return 0
}

lock_pid_alive() {
  [ -s "$LOCK_PID_FILE" ] || return 1
  lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
  [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null
}

show_lock_status() {
  echo "sync_timeout_seconds=$SYNC_TIMEOUT_SECONDS"
  if [ -d "$LOCK_DIR" ]; then
    echo "sync_lock=present"
    [ ! -f "$LOCK_STARTED_AT_FILE" ] || echo "sync_started_at=$(cat "$LOCK_STARTED_AT_FILE")"
    [ ! -f "$LOCK_CHANNEL_FILE" ] || echo "sync_channel=$(cat "$LOCK_CHANNEL_FILE")"
    if [ -f "$LOCK_STARTED_EPOCH_FILE" ]; then
      started_epoch=$(cat "$LOCK_STARTED_EPOCH_FILE" 2>/dev/null || echo 0)
      now_epoch=$(date +%s)
      case "$started_epoch" in
        ''|*[!0-9]*) ;;
        *) echo "sync_age_seconds=$((now_epoch - started_epoch))" ;;
      esac
    fi
    if [ -f "$LOCK_PID_FILE" ]; then
      lock_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null || true)
      echo "sync_pid=$lock_pid"
      if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        echo "sync_pid_alive=yes"
      else
        echo "sync_pid_alive=no"
      fi
    fi
  else
    echo "sync_lock=absent"
  fi
}

write_lock_metadata() {
  now_epoch=$(date +%s)
  printf '%s\n' "$$" > "$LOCK_PID_FILE"
  printf '%s\n' "$now_epoch" > "$LOCK_STARTED_EPOCH_FILE"
  date '+%Y-%m-%d %H:%M:%S%z' > "$LOCK_STARTED_AT_FILE"
  printf '%s\n' "$CHANNEL" > "$LOCK_CHANNEL_FILE"
}

clear_lock() {
  rm -f "$LOCK_PID_FILE" "$LOCK_STARTED_EPOCH_FILE" "$LOCK_STARTED_AT_FILE" "$LOCK_CHANNEL_FILE"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

run_mbsync_with_timeout() {
  if command -v timeout >/dev/null 2>&1 && [ "$SYNC_TIMEOUT_SECONDS" -gt 0 ]; then
    if timeout --help 2>&1 | grep -q -- '--kill-after'; then
      timeout --kill-after=60s "$SYNC_TIMEOUT_SECONDS" mbsync -c "$CONFIG" "$CHANNEL"
    else
      timeout "$SYNC_TIMEOUT_SECONDS" mbsync -c "$CONFIG" "$CHANNEL"
    fi
  else
    mbsync -c "$CONFIG" "$CHANNEL"
  fi
}

clear_stale_lock() {
  if [ ! -d "$LOCK_DIR" ]; then
    echo "no lock present"
    return 0
  fi
  if lock_pid_alive; then
    echo "lock pid is still alive; refusing to clear active lock"
    show_lock_status
    return 1
  fi
  clear_lock
  echo "stale lock cleared"
}

cleanup_logs() {
  [ -d "$LOG_DIR" ] || return 0

  if command -v gzip >/dev/null 2>&1; then
    find "$LOG_DIR" -maxdepth 1 -type f -name "????????-$PROFILE-live-auto.log" \
      -mtime +"$AUTO_LOG_COMPRESS_DAYS" -exec gzip -f {} \; 2>/dev/null || true
  fi

  find "$LOG_DIR" -maxdepth 1 -type f -name "????????-$PROFILE-live-auto.log.gz" \
    -mtime +"$AUTO_LOG_DELETE_DAYS" -exec rm -f {} \; 2>/dev/null || true
  find "$LOG_DIR" -maxdepth 1 -type f -name "????????-$PROFILE-live-auto.log" \
    -mtime +"$AUTO_LOG_DELETE_DAYS" -exec rm -f {} \; 2>/dev/null || true
  find "$LOG_DIR" -maxdepth 1 -type f -name "*.log" \
    ! -name "????????-$PROFILE-live-auto.log" \
    -mtime +"$MANUAL_LOG_DELETE_DAYS" -exec rm -f {} \; 2>/dev/null || true

  printf '%s\n' "$(date +%Y%m%d)" > "$CLEANUP_STAMP"
}

show_logs() {
  echo "== provider-live log usage =="
  du -sh "$LOG_DIR" 2>/dev/null || true
  echo "retention: auto_compress_days=$AUTO_LOG_COMPRESS_DAYS auto_delete_days=$AUTO_LOG_DELETE_DAYS manual_delete_days=$MANUAL_LOG_DELETE_DAYS"
  echo "== latest logs =="
  ls -lt "$LOG_DIR" 2>/dev/null | sed -n '1,12p' || true
}

case "${1:-status}" in
  start)
    if is_loop_running; then
      echo "provider-live loop already running"
      exit 0
    fi
    if [ ! -x "$LOOP" ]; then
      echo "missing executable loop script: $LOOP"
      exit 1
    fi
    rm -f "$STOP_FILE"
    nohup "$LOOP" >/tmp/mbsync-provider-live-loop.nohup 2>&1 &
    echo "provider-live loop started"
    ;;
  pause)
    date '+paused at %Y-%m-%d %H:%M:%S%z' > "$PAUSE_FILE"
    echo "provider-live auto-sync paused"
    ;;
  resume)
    rm -f "$PAUSE_FILE"
    echo "provider-live auto-sync resumed"
    ;;
  stop-loop)
    touch "$STOP_FILE"
    if [ -s "$PID_FILE" ]; then
      pid=$(cat "$PID_FILE" 2>/dev/null || true)
      if pid_is_loop "$pid"; then
        kill "$pid" 2>/dev/null || true
      else
        echo "stale loop pid ignored: $pid"
        rm -f "$PID_FILE"
      fi
    fi
    echo "provider-live loop stop requested"
    ;;
  sync-now)
    if [ -e "$PAUSE_FILE" ]; then
      echo "provider-live is paused; refusing sync-now until resumed"
      exit 1
    fi
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
      echo "provider-live sync already running"
      exit 1
    fi
    write_lock_metadata
    log_file="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$PROFILE-live-manual-sync-now.log"
    {
      echo "$(date '+%Y-%m-%d %H:%M:%S%z') manual sync start timeout=${SYNC_TIMEOUT_SECONDS}s"
      run_mbsync_with_timeout
      rc=$?
      case "$rc" in
        124|137) echo "$(date '+%Y-%m-%d %H:%M:%S%z') manual sync timed out or was killed after ${SYNC_TIMEOUT_SECONDS}s" ;;
      esac
      echo "$(date '+%Y-%m-%d %H:%M:%S%z') manual sync exit=$rc"
      echo "last_manual_exit=$rc $(date '+%Y-%m-%d %H:%M:%S%z')" > "$LAST_STATUS"
      clear_lock
      echo "$rc" > "$STATE_DIR/sync-now.rc"
    } > "$log_file" 2>&1
    rc=$(cat "$STATE_DIR/sync-now.rc" 2>/dev/null || echo 1)
    rm -f "$STATE_DIR/sync-now.rc"
    cat "$log_file"
    echo "log: $log_file"
    exit "$rc"
    ;;
  status)
    echo "== provider-live auto-sync status =="
    if is_loop_running; then
      echo "loop=running"
      if [ -s "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if pid_is_loop "$pid"; then
          echo "pid=$pid"
        else
          echo "stale_loop_pid=$pid"
        fi
      fi
    else
      echo "loop=stopped"
      if [ -s "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null || true)
        pid_is_loop "$pid" || echo "stale_loop_pid=$pid"
      fi
    fi
    if [ -e "$PAUSE_FILE" ]; then
      echo "paused=yes"
      cat "$PAUSE_FILE"
    else
      echo "paused=no"
    fi
    show_lock_status
    [ ! -f "$LAST_STATUS" ] || cat "$LAST_STATUS"
    echo "channel=$CHANNEL"
    echo "log_usage:"
    du -sh "$LOG_DIR" 2>/dev/null || true
    echo "latest_logs:"
    ls -lt "$LOG_DIR" 2>/dev/null | sed -n '1,8p' || true
    ;;
  logs)
    show_logs
    ;;
  cleanup-logs)
    cleanup_logs
    show_logs
    ;;
  clear-stale-lock)
    clear_stale_lock
    ;;
  *)
    echo "Usage: $0 {start|pause|resume|stop-loop|sync-now|status|logs|cleanup-logs|clear-stale-lock}"
    exit 2
    ;;
esac
EOF

  chmod 700 "$LOOP_SCRIPT" "$CONTROL_SCRIPT"
  sh -n "$LOOP_SCRIPT"
  sh -n "$CONTROL_SCRIPT"

  log "== wrote auto-sync scripts =="
  ls -l "$LOOP_SCRIPT" "$CONTROL_SCRIPT"
}

install_autosync_startup() {
  [ -x "$CONTROL_SCRIPT" ] || die "missing executable control script: $CONTROL_SCRIPT"
  mkdir -p "$(dirname "$ICEWM_STARTUP")"

  backup_dir=$(backup_to_mail "before-provider-live-icewm-startup")
  if [ -e "$ICEWM_STARTUP" ]; then
    cp -p "$ICEWM_STARTUP" "$backup_dir/startup.before-provider-live-autosync"
  else
    printf '%s\n' '#!/bin/sh' > "$ICEWM_STARTUP"
  fi

  tmp_startup=$(mktemp)
  old_begin="# BEGIN CODEX MBSYNC $PROFILE LIVE AUTOSYNC"
  old_end="# END CODEX MBSYNC $PROFILE LIVE AUTOSYNC"
  provider_begin="# BEGIN CODEX MBSYNC PROVIDER LIVE AUTOSYNC"
  provider_end="# END CODEX MBSYNC PROVIDER LIVE AUTOSYNC"
  awk -v begin="$STARTUP_BEGIN_MARKER" -v end="$STARTUP_END_MARKER" \
    -v old_begin="$old_begin" -v old_end="$old_end" \
    -v provider_begin="$provider_begin" -v provider_end="$provider_end" '
    $0 == begin || $0 == old_begin || $0 == provider_begin { skip = 1; next }
    $0 == end || $0 == old_end || $0 == provider_end { skip = 0; next }
    !skip { print }
  ' "$ICEWM_STARTUP" > "$tmp_startup"

  cat >> "$tmp_startup" <<EOF

$STARTUP_BEGIN_MARKER
# Start provider-live mbsync polling when IceWM session starts.
if [ -x "$CONTROL_SCRIPT" ]; then
  "$CONTROL_SCRIPT" start >/tmp/mbsync-provider-live-icewm-startup.log 2>&1 &
fi
$STARTUP_END_MARKER
EOF

  install -m 700 "$tmp_startup" "$ICEWM_STARTUP"
  rm -f "$tmp_startup"

  log "== installed IceWM startup block =="
  grep -nA5 -B2 "CODEX MBSYNC $MARKER_PROFILE LIVE AUTOSYNC" "$ICEWM_STARTUP" || true
}

autosync_status() {
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" status
  else
    die "missing executable control script: $CONTROL_SCRIPT"
  fi
}

autosync_preflight() {
  validate_profile

  log "== time =="
  date

  log "== current auto-sync status =="
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" status || true
  else
    log "missing executable control script: $CONTROL_SCRIPT"
  fi

  log "== current scripts =="
  ls -l "$LOOP_SCRIPT" "$CONTROL_SCRIPT" 2>/dev/null || true

  log "== syntax check current scripts =="
  if [ -f "$LOOP_SCRIPT" ]; then
    if sh -n "$LOOP_SCRIPT"; then
      log "loop syntax OK"
    else
      log "loop syntax FAILED"
    fi
  else
    log "missing loop script: $LOOP_SCRIPT"
  fi

  if [ -f "$CONTROL_SCRIPT" ]; then
    if sh -n "$CONTROL_SCRIPT"; then
      log "control syntax OK"
    else
      log "control syntax FAILED"
    fi
  else
    log "missing control script: $CONTROL_SCRIPT"
  fi

  log "== current log usage =="
  du -sh "$LIVE_LOG_DIR" 2>/dev/null || true
  ls -lh "$LIVE_LOG_DIR" 2>/dev/null | tail -20 || true

  log "== timeout command =="
  command -v timeout || true
  timeout --version 2>/dev/null | sed -n '1,2p' || true

  log "== current control supports expected commands? =="
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" logs 2>&1 || true
    "$CONTROL_SCRIPT" __codex_usage_probe__ 2>&1 | sed -n '1,4p' || true
  else
    log "missing executable control script: $CONTROL_SCRIPT"
  fi
}

refresh_autosync() {
  validate_profile

  log "== time =="
  date

  log "== pause auto-sync =="
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" pause || true
  else
    log "missing executable control script before refresh: $CONTROL_SCRIPT"
  fi

  log "== stop auto-sync loop =="
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" stop-loop || true
  else
    log "missing executable control script before refresh: $CONTROL_SCRIPT"
  fi

  log "== wait for loop to exit =="
  sleep 3

  log "== status after stop request =="
  if [ -x "$CONTROL_SCRIPT" ]; then
    "$CONTROL_SCRIPT" status || true
  else
    log "missing executable control script before refresh: $CONTROL_SCRIPT"
  fi

  log "== remaining related processes =="
  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -af 'mbsync-provider-live-loop|mbsync .*provider-live-group|isync'; then
      die "related mbsync process is still running; stop it before replacing scripts"
    fi
  else
    log "pgrep unavailable; skipping process audit"
  fi

  log "== write refreshed auto-sync scripts =="
  write_autosync

  log "== install IceWM startup block =="
  install_autosync_startup

  log "== syntax check installed scripts =="
  sh -n "$LOOP_SCRIPT"
  sh -n "$CONTROL_SCRIPT"
  log "installed scripts syntax OK"

  log "== refreshed script commands =="
  "$CONTROL_SCRIPT" logs || true

  log "== status before restart =="
  "$CONTROL_SCRIPT" status || true
}

autosync_validate() {
  validate_profile
  [ -x "$CONTROL_SCRIPT" ] || die "missing executable control script: $CONTROL_SCRIPT"

  log "== time =="
  date

  log "== pre-start status =="
  "$CONTROL_SCRIPT" status

  log "== resume auto-sync =="
  "$CONTROL_SCRIPT" resume

  log "== run one manual provider-live-group sync through control script =="
  if "$CONTROL_SCRIPT" sync-now; then
    sync_rc=0
  else
    sync_rc=$?
  fi
  log "sync-now exit code: $sync_rc"
  [ "$sync_rc" -eq 0 ] || die "sync-now failed"

  log "== status after manual sync =="
  "$CONTROL_SCRIPT" status

  log "== start auto-sync loop =="
  "$CONTROL_SCRIPT" start

  sleep_seconds=${MBSYNC_AUTOSYNC_VALIDATE_SLEEP_SECONDS:-8}
  log "== wait briefly for first loop pass =="
  sleep "$sleep_seconds"

  log "== final status =="
  "$CONTROL_SCRIPT" status

  log "== log controls =="
  "$CONTROL_SCRIPT" logs

  log "== latest auto log tail =="
  tail -40 "$LIVE_LOG_DIR/$(date +%Y%m%d)-$PROFILE-live-auto.log" 2>/dev/null || true

  log "== related processes =="
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -af 'mbsync-provider-live-loop|mbsync .*provider-live-group|isync' || true
  else
    log "pgrep unavailable; skipping process audit"
  fi

  log "== tmp directories should be empty =="
  [ -d "$LIVE_MAILDIR" ] || die "missing live Maildir: $LIVE_MAILDIR"
  tmp_report=$(mktemp)
  if find "$LIVE_MAILDIR" -type d -name tmp -exec sh -c '
    for d do
      c=$(find "$d" -type f | wc -l)
      printf "%s files=%s\n" "$d" "$c"
      [ "$c" -eq 0 ] || exit 1
    done
  ' sh {} + > "$tmp_report"; then
    tmp_status=0
  else
    tmp_status=$?
  fi
  cat "$tmp_report"
  rm -f "$tmp_report"
  [ "$tmp_status" -eq 0 ] || die "one or more provider-live tmp directories contain files"
}

autosync_stale_lock_proof() {
  validate_profile
  [ -x "$CONTROL_SCRIPT" ] || die "missing executable control script: $CONTROL_SCRIPT"

  lock_dir="$LIVE_LOOP_STATE_DIR/lock"
  lock_pid_file="$lock_dir/pid"
  lock_started_epoch_file="$lock_dir/started_epoch"
  lock_started_at_file="$lock_dir/started_at"
  lock_channel_file="$lock_dir/channel"

  cleanup_fake_lock() {
    if [ -f "$lock_pid_file" ] && grep -qx '99999999' "$lock_pid_file" 2>/dev/null; then
      rm -f "$lock_pid_file" "$lock_started_epoch_file" "$lock_started_at_file" "$lock_channel_file"
      rmdir "$lock_dir" 2>/dev/null || true
    fi
  }
  trap cleanup_fake_lock EXIT HUP INT TERM

  log "== time =="
  date

  log "== pre-proof status =="
  "$CONTROL_SCRIPT" status

  if "$CONTROL_SCRIPT" status 2>/dev/null | grep -q '^loop=running$'; then
    die "auto-sync loop is running; run refresh-autosync or stop-loop before stale-lock proof"
  fi

  [ ! -d "$lock_dir" ] || die "lock already exists; refusing to overwrite possible real lock: $lock_dir"

  log "== create fake stale lock =="
  mkdir -p "$lock_dir"
  fake_started_epoch=$(($(date +%s) - 600))
  printf '%s\n' '99999999' > "$lock_pid_file"
  printf '%s\n' "$fake_started_epoch" > "$lock_started_epoch_file"
  if fake_started_at=$(date -d '10 minutes ago' '+%Y-%m-%d %H:%M:%S%z' 2>/dev/null); then
    printf '%s\n' "$fake_started_at" > "$lock_started_at_file"
  else
    date '+%Y-%m-%d %H:%M:%S%z' > "$lock_started_at_file"
  fi
  printf '%s\n' "$LIVE_GROUP" > "$lock_channel_file"

  log "== status with fake stale lock =="
  "$CONTROL_SCRIPT" status

  log "== clear fake stale lock =="
  if "$CONTROL_SCRIPT" clear-stale-lock; then
    clear_rc=0
  else
    clear_rc=$?
  fi
  log "clear-stale-lock exit code: $clear_rc"
  [ "$clear_rc" -eq 0 ] || die "clear-stale-lock failed"

  log "== status after clearing fake stale lock =="
  "$CONTROL_SCRIPT" status
  [ ! -d "$lock_dir" ] || die "fake stale lock still exists after clear-stale-lock"

  trap - EXIT HUP INT TERM
}

autosync_log_rotation_proof() {
  validate_profile
  [ -x "$CONTROL_SCRIPT" ] || die "missing executable control script: $CONTROL_SCRIPT"

  mkdir -p "$LIVE_LOG_DIR"
  chmod 700 "$LIVE_LOG_DIR" 2>/dev/null || true

  auto_compress_test="$LIVE_LOG_DIR/20000101-$PROFILE-live-auto.log"
  auto_delete_test="$LIVE_LOG_DIR/20000102-$PROFILE-live-auto.log.gz"
  manual_delete_test="$LIVE_LOG_DIR/20000103-$PROFILE-live-manual-sync-now.log"
  manual_keep_test="$LIVE_LOG_DIR/20000104-$PROFILE-live-manual-sync-now.log"

  cleanup_fake_logs() {
    rm -f "$auto_compress_test" "$auto_compress_test.gz" \
      "$auto_delete_test" "$manual_delete_test" "$manual_keep_test"
  }
  trap cleanup_fake_logs EXIT HUP INT TERM

  log "== time =="
  date

  log "== create fake old test logs =="
  printf '%s\n' "fake auto compress test" > "$auto_compress_test"
  printf '%s\n' "fake old compressed auto delete test" > "$auto_delete_test"
  printf '%s\n' "fake old manual delete test" > "$manual_delete_test"
  printf '%s\n' "fake recent manual keep test" > "$manual_keep_test"

  touch -d '3 days ago' "$auto_compress_test"
  touch -d '40 days ago' "$auto_delete_test"
  touch -d '100 days ago' "$manual_delete_test"
  touch -d '10 days ago' "$manual_keep_test"

  log "== fake logs before cleanup =="
  ls -lh "$LIVE_LOG_DIR"/2000010*-"$PROFILE"-live-* 2>/dev/null || true

  log "== run cleanup =="
  "$CONTROL_SCRIPT" cleanup-logs

  log "== fake logs after cleanup =="
  ls -lh "$LIVE_LOG_DIR"/2000010*-"$PROFILE"-live-* 2>/dev/null || true

  log "== expected checks =="
  proof_failed=0

  if command -v gzip >/dev/null 2>&1; then
    if [ -f "$auto_compress_test.gz" ]; then
      log "OK: old auto log compressed"
    else
      log "FAIL: old auto log was not compressed"
      proof_failed=1
    fi
    if [ ! -e "$auto_compress_test" ]; then
      log "OK: original old auto log removed after compression"
    else
      log "FAIL: original old auto log still exists"
      proof_failed=1
    fi
  else
    log "SKIP: gzip missing, compression check skipped"
  fi

  if [ ! -e "$auto_delete_test" ]; then
    log "OK: expired compressed auto log deleted"
  else
    log "FAIL: expired compressed auto log still exists"
    proof_failed=1
  fi

  if [ ! -e "$manual_delete_test" ]; then
    log "OK: expired manual log deleted"
  else
    log "FAIL: expired manual log still exists"
    proof_failed=1
  fi

  if [ -f "$manual_keep_test" ]; then
    log "OK: recent manual log kept"
  else
    log "FAIL: recent manual log missing"
    proof_failed=1
  fi

  log "== remove remaining fake test logs =="
  cleanup_fake_logs
  trap - EXIT HUP INT TERM

  log "== final log status =="
  "$CONTROL_SCRIPT" logs

  log "== final auto-sync status =="
  "$CONTROL_SCRIPT" status

  [ "$proof_failed" -eq 0 ] || die "log rotation proof failed"
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
  production-layout) create_production_layout ;;
  write-production-config) write_production_config ;;
  production-list) production_list ;;
  production-sync) production_sync ;;
  production-status) production_status ;;
  write-autosync) write_autosync ;;
  install-autosync-startup) install_autosync_startup ;;
  autosync-status) autosync_status ;;
  autosync-preflight) autosync_preflight ;;
  refresh-autosync) refresh_autosync ;;
  autosync-validate) autosync_validate ;;
  autosync-stale-lock-proof) autosync_stale_lock_proof ;;
  autosync-log-rotation-proof) autosync_log_rotation_proof ;;
  redact-config) redact_config ;;
  -h|--help|help|'') usage ;;
  *)
    usage
    exit 2
    ;;
esac
