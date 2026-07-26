#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=${NOTMUCH_FRESH_REPO_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
MAIL_ROOT=${NOTMUCH_FRESH_MAIL_ROOT:-/mail}
MAILSTORE=${NOTMUCH_FRESH_MAILSTORE:-"$MAIL_ROOT/Mailstore"}
ARCHIVE_DEST=${NOTMUCH_FRESH_ARCHIVE_DEST:-"$MAILSTORE/evolution/local-maildir"}
ARCHIVE_MANIFEST=${NOTMUCH_FRESH_ARCHIVE_MANIFEST:-"$MAIL_ROOT/import-staging/maildirpp-archive-export-20260701-215204/manifest.json"}
STATE_DIR=${NOTMUCH_FRESH_STATE_DIR:-"$MAIL_ROOT/AppData/notmuch-browser/fresh-vm-setup"}
LOG_DIR=${NOTMUCH_FRESH_LOG_DIR:-"$MAIL_ROOT/Logs/notmuch-browser/fresh-vm-setup"}
DB_PATH=${NOTMUCH_FRESH_DB_PATH:-"$MAIL_ROOT/SearchIndex/notmuch/default"}
CONFIG=${NOTMUCH_FRESH_CONFIG:-"$HOME/.config/notmuch/default/config"}
BIN_DIR=${NOTMUCH_FRESH_BIN_DIR:-"$HOME/.local/bin"}
USER_SERVICE_ROOT=${NOTMUCH_FRESH_USER_SERVICE_ROOT:-"$HOME/.runit/usersv"}
ACTIVE_SERVICE_ROOT=${NOTMUCH_FRESH_ACTIVE_SERVICE_ROOT:-"$HOME/.runit/service"}
MBSYNC_CONFIG=${NOTMUCH_FRESH_MBSYNC_CONFIG:-"$HOME/.config/isyncrc"}
MBSYNC_CONTROL=${NOTMUCH_FRESH_MBSYNC_CONTROL:-"$BIN_DIR/mbsync-provider-live-control"}
BROWSER_CONTROL=${NOTMUCH_FRESH_BROWSER_CONTROL:-"$BIN_DIR/notmuch-browser-control"}
INDEX_CONTROL=${NOTMUCH_FRESH_INDEX_CONTROL:-"$BIN_DIR/notmuch-browser-index-control"}
RUNIT_SETUP=${NOTMUCH_FRESH_RUNIT_SETUP:-"$BIN_DIR/notmuch-browser-runit-setup"}

EXPECTED_GO_VERSION=${NOTMUCH_FRESH_GO_VERSION:-go1.26.5}
EXPECTED_BUN_VERSION=${NOTMUCH_FRESH_BUN_VERSION:-1.3.14}
EXPECTED_ARCHIVE_SHA256=23292983c9ffb3590197a534aeddd03590a2b8d9f913732573fa1637b71045fe
EXPECTED_INVENTORY_SHA256=97332ffac27c85372d91486ceeb8d49dde2cc036d6b0d889cd73243b1e06067d
EXPECTED_ARCHIVE_CUR=48720
EXPECTED_ARCHIVE_NEW=0
EXPECTED_ARCHIVE_TMP=0
EXPECTED_ARCHIVE_METADATA=1
EXPECTED_ARCHIVE_BYTES=62430783277
if [ "${NOTMUCH_FRESH_TEST_MODE:-0}" = 1 ]; then
  EXPECTED_ARCHIVE_CUR=${NOTMUCH_FRESH_TEST_CUR:-$EXPECTED_ARCHIVE_CUR}
  EXPECTED_ARCHIVE_NEW=${NOTMUCH_FRESH_TEST_NEW:-$EXPECTED_ARCHIVE_NEW}
  EXPECTED_ARCHIVE_TMP=${NOTMUCH_FRESH_TEST_TMP:-$EXPECTED_ARCHIVE_TMP}
  EXPECTED_ARCHIVE_METADATA=${NOTMUCH_FRESH_TEST_METADATA:-$EXPECTED_ARCHIVE_METADATA}
  EXPECTED_ARCHIVE_BYTES=${NOTMUCH_FRESH_TEST_BYTES:-$EXPECTED_ARCHIVE_BYTES}
fi
MIN_FREE_KIB=${NOTMUCH_FRESH_MIN_FREE_KIB:-83886080}

ARCHIVE_MARKER="$STATE_DIR/archive-restored.env"
INDEX_MARKER="$STATE_DIR/initial-index.env"
INSTALL_MARKER="$STATE_DIR/browser-installed.env"
IGNORE_VALUES="betterbird-post-main-archive-maildirpp-20260704-205827"

say() {
  printf '%s\n' "$*"
}

die() {
  say "status=blocked"
  say "reason=$*"
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

mail_fstype() {
  findmnt -n -o FSTYPE --target "$MAIL_ROOT" 2>/dev/null || true
}

mail_ready() {
  [ -d "$MAIL_ROOT" ] && [ "$(mail_fstype)" = xfs ]
}

free_kib() {
  df -Pk "$MAIL_ROOT" 2>/dev/null | awk 'NR == 2 { print $4 }'
}

value_from_output() {
  key=$1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, length($1) + 2); exit }'
}

manifest_value() {
  key=$1
  python3 - "$ARCHIVE_MANIFEST" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
}

all_packages_ready() {
  for tool in git curl python3 rsync notmuch mbsync sv svlogd ssh ss unzip tar sha256sum findmnt; do
    command_exists "$tool" || return 1
  done
}

go_ready() {
  command_exists go && [ "$(go version 2>/dev/null | awk '{print $3}')" = "$EXPECTED_GO_VERSION" ]
}

bun_command() {
  if [ -x "$HOME/.bun/bin/bun" ]; then
    printf '%s\n' "$HOME/.bun/bin/bun"
  elif command_exists bun; then
    command -v bun
  else
    return 1
  fi
}

bun_ready() {
  bun_bin=$(bun_command 2>/dev/null) || return 1
  [ "$("$bun_bin" --version 2>/dev/null)" = "$EXPECTED_BUN_VERSION" ]
}

mbsync_ready() {
  [ -s "$MBSYNC_CONFIG" ] &&
    [ -d "$MAILSTORE/mbsync/provider-live" ] &&
    [ -x "$MBSYNC_CONTROL" ]
}

archive_acknowledged() {
  [ -s "$ARCHIVE_MARKER" ] &&
    grep -Fqx "archive_sha256=$EXPECTED_ARCHIVE_SHA256" "$ARCHIVE_MARKER" &&
    grep -Fqx "inventory_sha256=$EXPECTED_INVENTORY_SHA256" "$ARCHIVE_MARKER" &&
    grep -Fqx "archive_cur=$EXPECTED_ARCHIVE_CUR" "$ARCHIVE_MARKER"
}

notmuch_value() {
  key=$1
  notmuch --config="$CONFIG" config get "$key" 2>/dev/null || true
}

notmuch_config_ready() {
  [ -s "$CONFIG" ] || return 1
  [ "$(notmuch_value database.path)" = "$DB_PATH" ] || return 1
  [ "$(notmuch_value database.mail_root)" = "$MAILSTORE" ] || return 1
  [ "$(notmuch_value maildir.synchronize_flags)" = false ] || return 1
  [ "$(notmuch_value index.decrypt)" = false ] || return 1
  notmuch_value new.ignore | grep -Fqx local-maildir && return 1
  return 0
}

initial_index_ready() {
  [ -s "$INDEX_MARKER" ] &&
    grep -Fqx "archive_indexed_files=$EXPECTED_ARCHIVE_CUR" "$INDEX_MARKER"
}

browser_installed() {
  [ -x "$BIN_DIR/notmuch-browser" ] &&
    [ -x "$BROWSER_CONTROL" ] &&
    [ -x "$INDEX_CONTROL" ] &&
    [ -x "$RUNIT_SETUP" ]
}

services_ready() {
  [ -L "$ACTIVE_SERVICE_ROOT/notmuch-browser" ] &&
    [ -L "$ACTIVE_SERVICE_ROOT/notmuch-browser-index" ] &&
    "$RUNIT_SETUP" validate >/dev/null 2>&1
}

next_stage() {
  mail_ready || { printf '%s\n' mail-disk; return; }
  all_packages_ready || { printf '%s\n' os-packages; return; }
  go_ready || { printf '%s\n' go; return; }
  bun_ready || { printf '%s\n' bun; return; }
  mbsync_ready || { printf '%s\n' mbsync; return; }
  archive_acknowledged || { printf '%s\n' archive; return; }
  notmuch_config_ready || { printf '%s\n' notmuch-config; return; }
  initial_index_ready || { printf '%s\n' initial-index; return; }
  browser_installed || { printf '%s\n' browser-install; return; }
  services_ready || { printf '%s\n' services; return; }
  printf '%s\n' complete
}

print_next() {
  stage=$(next_stage)
  say "next_stage=$stage"
  case "$stage" in
    mail-disk)
      say "Open: existing_DIY-Guide/antiX_VM_XFS_Maildir_Disk_Setup_Guide.html"
      say "Create and mount the dedicated XFS disk at /mail, then run this command again."
      ;;
    os-packages)
      say "Run:"
      say "sudo apt update && sudo apt install git curl ca-certificates unzip xz-utils rsync python3 notmuch isync libsasl2-modules runit-antix runit-service-ssh iproute2 openssh-client openssh-server build-essential"
      ;;
    go)
      say "Install the verified Go $EXPECTED_GO_VERSION command block from Step 8 of the guide."
      ;;
    bun)
      say "Install Bun $EXPECTED_BUN_VERSION using the command in Step 9 of the guide."
      ;;
    mbsync)
      say "Complete the interactive provider-live mbsync commands in Step 10 of the guide."
      ;;
    archive)
      say "Restore the verified archive into: $ARCHIVE_DEST"
      say "Then run:"
      say "./scripts/notmuch_browser_fresh_vm_setup.sh acknowledge archives-restored"
      ;;
    notmuch-config)
      say "Run, replacing the example identity:"
      say "./scripts/notmuch_browser_fresh_vm_setup.sh configure-notmuch \"Your Name\" \"you@example.com\""
      ;;
    initial-index)
      say "This is the long historical indexing step. Run:"
      say "./scripts/notmuch_browser_fresh_vm_setup.sh initial-index"
      ;;
    browser-install)
      say "Build and install the complete browser:"
      say "./scripts/notmuch_browser_fresh_vm_setup.sh build-install"
      ;;
    services)
      say "Enable and validate the browser plus 60-second index service:"
      say "./scripts/notmuch_browser_fresh_vm_setup.sh enable-services"
      ;;
    complete)
      say "Run the final checks:"
      say "./scripts/notmuch_browser_fresh_vm_setup.sh validate"
      ;;
  esac
}

inspect() {
  say "repo_root=$REPO_ROOT"
  say "mail_root=$MAIL_ROOT"
  say "mail_fstype=$(mail_fstype)"
  say "mail_free_kib=$(free_kib || true)"
  say "archive_manifest=$ARCHIVE_MANIFEST"
  say "archive_destination=$ARCHIVE_DEST"
  say "notmuch_config=$CONFIG"
  say "notmuch_database=$DB_PATH"
  say "state_dir=$STATE_DIR"
  if all_packages_ready; then say "os_packages=ready"; else say "os_packages=incomplete"; fi
  if go_ready; then say "go=ready"; else say "go=missing_or_wrong_version"; fi
  if bun_ready; then say "bun=ready"; else say "bun=missing_or_wrong_version"; fi
  if mbsync_ready; then say "mbsync=ready"; else say "mbsync=incomplete"; fi
  if archive_acknowledged; then say "archive=verified"; else say "archive=not_acknowledged"; fi
  if notmuch_config_ready; then say "notmuch_config=ready"; else say "notmuch_config=incomplete"; fi
  if initial_index_ready; then say "initial_index=verified"; else say "initial_index=incomplete"; fi
  if browser_installed; then say "browser_install=ready"; else say "browser_install=incomplete"; fi
  if services_ready; then say "services=ready"; else say "services=incomplete"; fi
  say "next_stage=$(next_stage)"
}

status() {
  inspect
  if [ -x "$MBSYNC_CONTROL" ]; then
    say "== mbsync =="
    "$MBSYNC_CONTROL" status 2>&1 || true
  fi
  if [ -x "$BROWSER_CONTROL" ]; then
    say "== browser =="
    "$BROWSER_CONTROL" status 2>&1 || true
  fi
  if [ -x "$INDEX_CONTROL" ]; then
    say "== index loop =="
    "$INDEX_CONTROL" status 2>&1 || true
  fi
}

acknowledge_archive() {
  mail_ready || die "$MAIL_ROOT is not a dedicated XFS mount"
  [ -f "$ARCHIVE_MANIFEST" ] || die "missing archive manifest: $ARCHIVE_MANIFEST"
  [ -d "$ARCHIVE_DEST" ] || die "missing restored archive: $ARCHIVE_DEST"
  [ -f "$REPO_ROOT/src/maildirpp_transport.py" ] || die "missing transport utility"

  archive_sha=$(manifest_value archive.sha256)
  inventory_sha=$(manifest_value inventory.sha256)
  [ "$archive_sha" = "$EXPECTED_ARCHIVE_SHA256" ] ||
    die "unexpected historical archive SHA256: $archive_sha"
  [ "$inventory_sha" = "$EXPECTED_INVENTORY_SHA256" ] ||
    die "unexpected historical inventory SHA256: $inventory_sha"

  python3 "$REPO_ROOT/src/maildirpp_transport.py" verify-archive \
    --manifest "$ARCHIVE_MANIFEST"
  python3 "$REPO_ROOT/src/maildirpp_transport.py" verify-tree \
    --manifest "$ARCHIVE_MANIFEST" --dest "$ARCHIVE_DEST"
  inspection=$(python3 "$REPO_ROOT/src/maildirpp_transport.py" inspect \
    --source "$ARCHIVE_DEST")

  cur=$(printf '%s\n' "$inspection" | value_from_output cur_files)
  new=$(printf '%s\n' "$inspection" | value_from_output new_files)
  tmp=$(printf '%s\n' "$inspection" | value_from_output tmp_files)
  metadata=$(printf '%s\n' "$inspection" | value_from_output metadata_files)
  bytes=$(printf '%s\n' "$inspection" | value_from_output bytes_regular)
  [ "$cur" = "$EXPECTED_ARCHIVE_CUR" ] || die "archive cur count is $cur, expected $EXPECTED_ARCHIVE_CUR"
  [ "$new" = "$EXPECTED_ARCHIVE_NEW" ] || die "archive new count is $new, expected 0"
  [ "$tmp" = "$EXPECTED_ARCHIVE_TMP" ] || die "archive tmp count is $tmp, expected 0"
  [ "$metadata" = "$EXPECTED_ARCHIVE_METADATA" ] || die "archive metadata count is $metadata, expected 1"
  [ "$bytes" = "$EXPECTED_ARCHIVE_BYTES" ] || die "archive byte count is $bytes, expected $EXPECTED_ARCHIVE_BYTES"

  available=$(free_kib)
  [ -n "$available" ] || die "could not measure free space on $MAIL_ROOT"
  [ "$available" -ge "$MIN_FREE_KIB" ] ||
    die "only $available KiB free; at least $MIN_FREE_KIB KiB is required before indexing"

  install -d -m 700 "$STATE_DIR"
  marker_tmp=$(mktemp "$STATE_DIR/.archive-restored.XXXXXX")
  {
    say "archive_sha256=$archive_sha"
    say "inventory_sha256=$inventory_sha"
    say "archive_cur=$cur"
    say "archive_new=$new"
    say "archive_tmp=$tmp"
    say "archive_metadata=$metadata"
    say "archive_bytes=$bytes"
    say "verified_at=$(date -Is 2>/dev/null || date)"
  } > "$marker_tmp"
  chmod 600 "$marker_tmp"
  mv "$marker_tmp" "$ARCHIVE_MARKER"
  printf '%s\n' "$inspection"
  say "status=archive_restore_acknowledged"
  say "next_stage=$(next_stage)"
}

configure_notmuch() {
  [ "$#" -eq 2 ] || die "usage: configure-notmuch \"Your Name\" \"you@example.com\""
  user_name=$1
  primary_email=$2
  [ -n "$user_name" ] || die "user name must not be empty"
  case "$primary_email" in
    *@*.*) ;;
    *) die "primary email does not look valid: $primary_email" ;;
  esac
  all_packages_ready || die "install the OS packages first"
  archive_acknowledged || die "verify and acknowledge the historical archive first"

  install -d -m 700 "$STATE_DIR" "$(dirname "$CONFIG")" "$DB_PATH"
  if [ -s "$CONFIG" ]; then
    stamp=$(date +%Y%m%d-%H%M%S)
    install -d -m 700 "$STATE_DIR/backups"
    cp -p "$CONFIG" "$STATE_DIR/backups/notmuch-config-$stamp"
  else
    : > "$CONFIG"
    chmod 600 "$CONFIG"
  fi

  notmuch --config="$CONFIG" config set database.path "$DB_PATH"
  notmuch --config="$CONFIG" config set database.mail_root "$MAILSTORE"
  notmuch --config="$CONFIG" config set user.name "$user_name"
  notmuch --config="$CONFIG" config set user.primary_email "$primary_email"
  notmuch --config="$CONFIG" config set new.tags unread inbox
  # Index every approved source and exclude only the unavailable legacy archive.
  notmuch --config="$CONFIG" config set new.ignore $IGNORE_VALUES
  notmuch --config="$CONFIG" config set search.exclude_tags deleted spam
  notmuch --config="$CONFIG" config set maildir.synchronize_flags false
  notmuch --config="$CONFIG" config set index.decrypt false
  chmod 600 "$CONFIG"

  notmuch_config_ready || die "the written notmuch configuration failed validation"
  say "status=notmuch_configured"
  say "database.path=$(notmuch_value database.path)"
  say "database.mail_root=$(notmuch_value database.mail_root)"
  notmuch_value new.ignore | sed 's/^/new.ignore=/'
  say "local_maildir_indexing=enabled"
  say "next_stage=$(next_stage)"
}

restore_background_services() {
  if [ "${INITIAL_TAGS_CLEARED:-no}" = yes ] && [ -s "$CONFIG" ]; then
    notmuch --config="$CONFIG" config set new.tags unread inbox >/dev/null 2>&1 || true
    INITIAL_TAGS_CLEARED=no
  fi
  if [ "${INDEX_WAS_RUNNING:-no}" = yes ] && [ -x "$INDEX_CONTROL" ]; then
    "$INDEX_CONTROL" start >/dev/null 2>&1 || true
  fi
  if [ "${MBSYNC_WAS_RUNNING:-no}" = yes ] && [ -x "$MBSYNC_CONTROL" ]; then
    "$MBSYNC_CONTROL" start-loop >/dev/null 2>&1 || true
  fi
  if [ "${MBSYNC_WAS_PAUSED:-yes}" = no ] && [ -x "$MBSYNC_CONTROL" ]; then
    "$MBSYNC_CONTROL" resume >/dev/null 2>&1 || true
  fi
}

pause_background_services() {
  MBSYNC_WAS_RUNNING=no
  MBSYNC_WAS_PAUSED=yes
  INDEX_WAS_RUNNING=no

  if [ -x "$MBSYNC_CONTROL" ]; then
    mbsync_status=$("$MBSYNC_CONTROL" status 2>&1 || true)
    printf '%s\n' "$mbsync_status" | grep -Eq 'loop=(running|alive)|loop_status=running' &&
      MBSYNC_WAS_RUNNING=yes
    printf '%s\n' "$mbsync_status" | grep -Eq 'paused=(no|false)' &&
      MBSYNC_WAS_PAUSED=no
    "$MBSYNC_CONTROL" pause
    "$MBSYNC_CONTROL" stop-loop
  fi

  if [ -x "$INDEX_CONTROL" ]; then
    index_status=$("$INDEX_CONTROL" status 2>&1 || true)
    printf '%s\n' "$index_status" | grep -Eq 'loop=(running|alive)|loop_status=running' &&
      INDEX_WAS_RUNNING=yes
    "$INDEX_CONTROL" stop
  fi
  export MBSYNC_WAS_RUNNING MBSYNC_WAS_PAUSED INDEX_WAS_RUNNING
}

initial_index() {
  mail_ready || die "$MAIL_ROOT is not a dedicated XFS mount"
  archive_acknowledged || die "historical archive acknowledgement is missing"
  notmuch_config_ready || die "notmuch configuration is not ready or still ignores local-maildir"
  available=$(free_kib)
  [ "$available" -ge "$MIN_FREE_KIB" ] ||
    die "only $available KiB free; at least $MIN_FREE_KIB KiB is required"

  install -d -m 700 "$STATE_DIR" "$LOG_DIR" "$STATE_DIR/backups"
  stamp=$(date +%Y%m%d-%H%M%S)
  run_log="$LOG_DIR/initial-notmuch-new-$stamp.log"
  backup="$STATE_DIR/backups/$stamp-before-initial-index"
  install -d -m 700 "$backup"
  cp -p "$CONFIG" "$backup/notmuch-config"
  if notmuch --config="$CONFIG" count '*' >/dev/null 2>&1; then
    notmuch --config="$CONFIG" dump --format=batch-tag > "$backup/notmuch-tags.batch-tag"
    chmod 600 "$backup/notmuch-tags.batch-tag"
  fi
  if [ -d "$DB_PATH" ] && find "$DB_PATH" -mindepth 1 -print -quit | grep -q .; then
    cp -a "$DB_PATH" "$backup/notmuch-database"
  fi

  pause_background_services
  trap 'restore_background_services' EXIT HUP INT TERM

  say "status=initial_index_running"
  say "log=$run_log"
  notmuch --config="$CONFIG" config set new.tags
  INITIAL_TAGS_CLEARED=yes
  export INITIAL_TAGS_CLEARED
  run_tmp=$(mktemp "$LOG_DIR/.initial-index.XXXXXX")
  if notmuch --config="$CONFIG" new > "$run_tmp" 2>&1; then
    cat "$run_tmp"
    mv "$run_tmp" "$run_log"
  else
    result=$?
    cat "$run_tmp"
    mv "$run_tmp" "$run_log"
    die "notmuch new failed with exit $result; fix the error and rerun initial-index"
  fi
  chmod 600 "$run_log"

  notmuch --config="$CONFIG" tag +inbox +unread -- 'path:mbsync/provider-live/**'
  notmuch --config="$CONFIG" tag +historical-archive -- 'path:evolution/local-maildir/**'
  notmuch --config="$CONFIG" tag +betterbird-delta -- 'path:evolution/betterbird-delta-maildirpp-20260704/**'
  notmuch --config="$CONFIG" tag +provider-inbox-test -- 'path:mbsync/provider-inbox-test/**'
  notmuch --config="$CONFIG" tag +test-mail -- 'path:evolution/test-maildir/**'
  notmuch --config="$CONFIG" config set new.tags unread inbox
  INITIAL_TAGS_CLEARED=no

  expected_paths=$(mktemp "$STATE_DIR/.archive-expected.XXXXXX")
  actual_paths=$(mktemp "$STATE_DIR/.archive-indexed.XXXXXX")
  find "$ARCHIVE_DEST" -type f \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    LC_ALL=C sort > "$expected_paths"
  notmuch --config="$CONFIG" search --output=files '*' |
    awk -v prefix="$ARCHIVE_DEST/" 'index($0, prefix) == 1 { print }' |
    LC_ALL=C sort > "$actual_paths"
  expected_count=$(wc -l < "$expected_paths" | tr -d ' ')
  actual_count=$(wc -l < "$actual_paths" | tr -d ' ')
  [ "$expected_count" = "$EXPECTED_ARCHIVE_CUR" ] ||
    die "restored archive path count changed to $expected_count"
  if ! cmp -s "$expected_paths" "$actual_paths"; then
    diff -u "$expected_paths" "$actual_paths" > "$LOG_DIR/archive-index-path-diff-$stamp.txt" || true
    die "notmuch archive path parity failed: indexed $actual_count of $expected_count"
  fi
  path_sha=$(sha256sum "$actual_paths" | awk '{print $1}')
  rm -f "$expected_paths" "$actual_paths"

  marker_tmp=$(mktemp "$STATE_DIR/.initial-index.XXXXXX")
  {
    say "archive_indexed_files=$actual_count"
    say "archive_paths_sha256=$path_sha"
    say "notmuch_unique_messages=$(notmuch --config="$CONFIG" count '*')"
    say "notmuch_indexed_files=$(notmuch --config="$CONFIG" count --output=files '*')"
    say "completed_at=$(date -Is 2>/dev/null || date)"
    say "log=$run_log"
    say "backup=$backup"
  } > "$marker_tmp"
  chmod 600 "$marker_tmp"
  mv "$marker_tmp" "$INDEX_MARKER"

  restore_background_services
  trap - EXIT HUP INT TERM
  say "archive_indexed_files=$actual_count"
  say "archive_path_parity=pass"
  say "status=initial_index_complete"
  say "next_stage=$(next_stage)"
}

build_install() {
  initial_index_ready || die "complete and validate the initial historical index first"
  go_ready || die "Go must be exactly $EXPECTED_GO_VERSION"
  bun_ready || die "Bun must be exactly $EXPECTED_BUN_VERSION"
  [ -x "$REPO_ROOT/scripts/notmuch_browser_build.sh" ] || die "missing browser build script"

  bun_bin=$(bun_command)
  BUN_BIN="$bun_bin" "$REPO_ROOT/scripts/notmuch_browser_build.sh" all
  [ -x "$REPO_ROOT/notmuch-browser" ] || die "browser build did not produce a binary"

  install -d -m 700 "$STATE_DIR" "$MAIL_ROOT/AppData/notmuch-browser/download-tmp" \
    "$MAIL_ROOT/Logs/notmuch-browser" "$MAIL_ROOT/Backups/notmuch-browser"
  install -d -m 755 "$BIN_DIR"
  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$STATE_DIR/backups/$stamp-before-browser-install"
  install -d -m 700 "$backup"
  for name in notmuch-browser notmuch-browser-control notmuch-browser-index-control notmuch-browser-runit-setup; do
    [ ! -e "$BIN_DIR/$name" ] || cp -p "$BIN_DIR/$name" "$backup/$name"
  done

  install -m 755 "$REPO_ROOT/notmuch-browser" "$BIN_DIR/notmuch-browser"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_control.sh" "$BROWSER_CONTROL"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_index_control.sh" "$INDEX_CONTROL"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_runit_setup.sh" "$RUNIT_SETUP"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_fresh_vm_setup.sh" \
    "$BIN_DIR/notmuch-browser-fresh-vm-setup"

  marker_tmp=$(mktemp "$STATE_DIR/.browser-installed.XXXXXX")
  {
    sha256sum "$BIN_DIR/notmuch-browser" "$BROWSER_CONTROL" "$INDEX_CONTROL" "$RUNIT_SETUP"
    say "installed_at=$(date -Is 2>/dev/null || date)"
    say "source_commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || say unknown)"
    say "backup=$backup"
  } > "$marker_tmp"
  chmod 600 "$marker_tmp"
  mv "$marker_tmp" "$INSTALL_MARKER"
  say "status=browser_built_and_installed"
  say "next_stage=$(next_stage)"
}

enable_services() {
  browser_installed || die "build and install the browser first"
  initial_index_ready || die "initial historical index validation is missing"
  [ -d "$USER_SERVICE_ROOT" ] || die "missing $USER_SERVICE_ROOT; follow the user-runit guide step"
  [ -d "$ACTIVE_SERVICE_ROOT" ] || die "missing $ACTIVE_SERVICE_ROOT; follow the user-runit guide step"
  pgrep -u "$(id -u)" -f "runsvdir -P $ACTIVE_SERVICE_ROOT" >/dev/null 2>&1 ||
    die "the antiX per-user runsvdir is not supervising $ACTIVE_SERVICE_ROOT"

  if [ ! -e "$ACTIVE_SERVICE_ROOT/notmuch-browser" ] &&
     [ ! -e "$ACTIVE_SERVICE_ROOT/notmuch-browser-index" ]; then
    "$RUNIT_SETUP" stage
    "$RUNIT_SETUP" activate
  fi
  "$RUNIT_SETUP" repair-session-startup
  "$RUNIT_SETUP" validate
  say "status=browser_and_index_services_enabled"
  say "automatic_index_interval_seconds=60"
}

validate_installation() {
  services_ready || die "browser/index runit services are not healthy"
  archive_acknowledged || die "archive verification marker is missing"
  initial_index_ready || die "initial index verification marker is missing"
  notmuch_config_ready || die "notmuch configuration is unsafe"
  health=$(curl -fsS --max-time 20 http://127.0.0.1:8765/healthz)
  printf '%s\n' "$health" | grep -Fq '"ok":true' || die "health did not report ok"
  printf '%s\n' "$health" | grep -Fq '"read_only":true' || die "health did not report read_only"
  printf '%s\n' "$health" | grep -Fq '"mail_mutation":false' || die "health reported mail mutation"
  ss -ltn | awk '$4 == "127.0.0.1:8765" { found=1 } END { exit(found ? 0 : 1) }' ||
    die "browser is not listening only on 127.0.0.1:8765"
  "$INDEX_CONTROL" status
  say "archive_indexed_files=$EXPECTED_ARCHIVE_CUR"
  say "automatic_new_mail_indexing=yes"
  say "status=fresh_vm_setup_complete"
}

update_installation() {
  services_ready || die "update requires an already healthy installation"
  [ -d "$REPO_ROOT/.git" ] || die "repository clone is missing"
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || die "repository has uncommitted changes"
  branch=$(git -C "$REPO_ROOT" branch --show-current)
  [ "$branch" = main ] || die "safe updates must run from the main branch, not $branch"

  git -C "$REPO_ROOT" pull --ff-only origin main
  bun_bin=$(bun_command)
  BUN_BIN="$bun_bin" "$REPO_ROOT/scripts/notmuch_browser_build.sh" all

  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$STATE_DIR/backups/$stamp-before-git-update"
  install -d -m 700 "$backup"
  cp -p "$BIN_DIR/notmuch-browser" "$backup/notmuch-browser"
  cp -p "$BROWSER_CONTROL" "$backup/notmuch-browser-control"
  cp -p "$INDEX_CONTROL" "$backup/notmuch-browser-index-control"
  cp -p "$RUNIT_SETUP" "$backup/notmuch-browser-runit-setup"

  UPDATE_IN_PROGRESS=yes
  UPDATE_BACKUP=$backup
  export UPDATE_IN_PROGRESS UPDATE_BACKUP
  trap '
    if [ "${UPDATE_IN_PROGRESS:-no}" = yes ]; then
      cp -p "$UPDATE_BACKUP/notmuch-browser" "$BIN_DIR/notmuch-browser" 2>/dev/null || true
      cp -p "$UPDATE_BACKUP/notmuch-browser-control" "$BROWSER_CONTROL" 2>/dev/null || true
      cp -p "$UPDATE_BACKUP/notmuch-browser-index-control" "$INDEX_CONTROL" 2>/dev/null || true
      cp -p "$UPDATE_BACKUP/notmuch-browser-runit-setup" "$RUNIT_SETUP" 2>/dev/null || true
      sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser" >/dev/null 2>&1 || true
      sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index" >/dev/null 2>&1 || true
    fi
  ' EXIT HUP INT TERM

  sv down "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
  sv down "$ACTIVE_SERVICE_ROOT/notmuch-browser"
  if install -m 755 "$REPO_ROOT/notmuch-browser" "$BIN_DIR/notmuch-browser" &&
     install -m 755 "$REPO_ROOT/scripts/notmuch_browser_control.sh" "$BROWSER_CONTROL" &&
     install -m 755 "$REPO_ROOT/scripts/notmuch_browser_index_control.sh" "$INDEX_CONTROL" &&
     install -m 755 "$REPO_ROOT/scripts/notmuch_browser_runit_setup.sh" "$RUNIT_SETUP"; then
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
  else
    cp -p "$backup/notmuch-browser" "$BIN_DIR/notmuch-browser"
    cp -p "$backup/notmuch-browser-control" "$BROWSER_CONTROL"
    cp -p "$backup/notmuch-browser-index-control" "$INDEX_CONTROL"
    cp -p "$backup/notmuch-browser-runit-setup" "$RUNIT_SETUP"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
    die "install failed; the prior application files were restored from $backup"
  fi
  if ! "$RUNIT_SETUP" validate; then
    sv down "$ACTIVE_SERVICE_ROOT/notmuch-browser-index" || true
    sv down "$ACTIVE_SERVICE_ROOT/notmuch-browser" || true
    cp -p "$backup/notmuch-browser" "$BIN_DIR/notmuch-browser"
    cp -p "$backup/notmuch-browser-control" "$BROWSER_CONTROL"
    cp -p "$backup/notmuch-browser-index-control" "$INDEX_CONTROL"
    cp -p "$backup/notmuch-browser-runit-setup" "$RUNIT_SETUP"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
    die "new version failed validation; prior application files were restored from $backup"
  fi
  UPDATE_IN_PROGRESS=no
  trap - EXIT HUP INT TERM
  say "status=git_update_complete"
  say "source_commit=$(git -C "$REPO_ROOT" rev-parse HEAD)"
  say "backup=$backup"
}

usage() {
  cat <<'EOF'
Usage: scripts/notmuch_browser_fresh_vm_setup.sh COMMAND [ARGS]

Beginner workflow:
  inspect
      Read-only environment report.
  status
      Read-only setup plus service report.
  next
      Print exactly one next stage and command. It never formats disks, installs
      packages, writes credentials, or starts the long initial index.
  acknowledge archives-restored
      Reverify the exact historical package/tree/counts and record the gate.
  configure-notmuch "Your Name" "you@example.com"
      Write the safe Mailstore-wide notmuch configuration. local-maildir is
      intentionally indexed; only named test/secondary archives are ignored.
  initial-index
      Pause active mail/index loops, back up existing state, run resumable
      notmuch new without a short timeout, and require 48,720 archive paths.
  build-install
      Reproduce and install the complete Go/templ/HTMX/Tailwind/chi browser.
  enable-services
      Enable the browser and 60-second incremental index loop under user runit.
  validate
      Verify archive/index markers, localhost health, read-only browser policy,
      and the index service.
  update
      On a clean main branch, pull --ff-only, rebuild, back up, install, validate,
      and restore the previous application files automatically on failure.
  help
      Show this help.

Run `next` after each completed stage. See
docs/NOTMUCH_GO_BROWSER_SERVICE_GUIDE.html for the complete beginner guide.
EOF
}

command_name=${1:-help}
case "$command_name" in
  inspect) inspect ;;
  status) status ;;
  next) print_next ;;
  acknowledge)
    [ "${2:-}" = archives-restored ] ||
      die "usage: acknowledge archives-restored"
    acknowledge_archive
    ;;
  configure-notmuch)
    shift
    configure_notmuch "$@"
    ;;
  initial-index) initial_index ;;
  build-install) build_install ;;
  enable-services) enable_services ;;
  validate) validate_installation ;;
  update) update_installation ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
