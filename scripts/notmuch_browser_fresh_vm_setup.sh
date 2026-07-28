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
RECOVERY_HELPER=${NOTMUCH_FRESH_RECOVERY_HELPER:-"$REPO_ROOT/scripts/notmuch_browser_recovery_kit.sh"}
GUIDED_STATE=${NOTMUCH_FRESH_GUIDED_STATE:-"$STATE_DIR/guided-install.env"}

EXPECTED_GO_VERSION=${NOTMUCH_FRESH_GO_VERSION:-go1.26.5}
EXPECTED_BUN_VERSION=${NOTMUCH_FRESH_BUN_VERSION:-1.3.14}
EXPECTED_BUN_ARCHIVE_SHA256=951ee2aee855f08595aeec6225226a298d3fea83a3dcd6465c09cbccdf7e848f
EXPECTED_RECOVERY_SET_SHA256=${NOTMUCH_FRESH_EXPECTED_RECOVERY_SET_SHA256:-PENDING_CANONICAL_RECOVERY_SET}
EXPECTED_ARCHIVE_SHA256=23292983c9ffb3590197a534aeddd03590a2b8d9f913732573fa1637b71045fe
EXPECTED_INVENTORY_SHA256=97332ffac27c85372d91486ceeb8d49dde2cc036d6b0d889cd73243b1e06067d
EXPECTED_ARCHIVE_CUR=48720
EXPECTED_ARCHIVE_NEW=0
EXPECTED_ARCHIVE_TMP=0
EXPECTED_ARCHIVE_METADATA=1
EXPECTED_ARCHIVE_BYTES=62430783277
EXPECTED_DELTA_CUR=247
EXPECTED_TEST_MAILDIR_MESSAGES=4
if [ "${NOTMUCH_FRESH_TEST_MODE:-0}" = 1 ]; then
  EXPECTED_ARCHIVE_CUR=${NOTMUCH_FRESH_TEST_CUR:-$EXPECTED_ARCHIVE_CUR}
  EXPECTED_ARCHIVE_NEW=${NOTMUCH_FRESH_TEST_NEW:-$EXPECTED_ARCHIVE_NEW}
  EXPECTED_ARCHIVE_TMP=${NOTMUCH_FRESH_TEST_TMP:-$EXPECTED_ARCHIVE_TMP}
  EXPECTED_ARCHIVE_METADATA=${NOTMUCH_FRESH_TEST_METADATA:-$EXPECTED_ARCHIVE_METADATA}
  EXPECTED_ARCHIVE_BYTES=${NOTMUCH_FRESH_TEST_BYTES:-$EXPECTED_ARCHIVE_BYTES}
  EXPECTED_DELTA_CUR=${NOTMUCH_FRESH_TEST_DELTA_CUR:-$EXPECTED_DELTA_CUR}
  EXPECTED_TEST_MAILDIR_MESSAGES=${NOTMUCH_FRESH_TEST_MAILDIR_MESSAGES:-$EXPECTED_TEST_MAILDIR_MESSAGES}
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
  for tool in sudo git curl python3 rsync notmuch mbsync sv svlogd ssh ss unzip tar sha256sum findmnt; do
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
    [ -d "$MAILSTORE/mbsync/provider-inbox-test" ] &&
    [ -x "$MBSYNC_CONTROL" ] || return 1
  mbsync_status=$("$MBSYNC_CONTROL" status 2>/dev/null || true)
  printf '%s\n' "$mbsync_status" | grep -Eq 'loop=(running|alive)|loop_status=running' ||
    return 1
  printf '%s\n' "$mbsync_status" | grep -Eq 'paused=(no|false)' || return 1
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
  [ "$(notmuch_value new.ignore)" = "$IGNORE_VALUES" ] || return 1
  return 0
}

initial_index_ready() {
  [ -s "$INDEX_MARKER" ] &&
    grep -Fqx "archive_indexed_files=$EXPECTED_ARCHIVE_CUR" "$INDEX_MARKER"
}

browser_installed() {
  [ -s "$INSTALL_MARKER" ] || return 1
  [ -x "$BIN_DIR/notmuch-browser" ] &&
    [ -x "$BROWSER_CONTROL" ] &&
    [ -x "$INDEX_CONTROL" ] &&
    [ -x "$RUNIT_SETUP" ] || return 1
  sed -n '1,4p' "$INSTALL_MARKER" | sha256sum -c - >/dev/null 2>&1
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

release_ready() {
  release=$1
  valid_release_name "$release" || return 1
  [ -d "$REPO_ROOT/.git" ] || return 1
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || return 1
  release_commit=$(git -C "$REPO_ROOT" rev-parse "$release^{commit}" 2>/dev/null) ||
    return 1
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)" = "$release_commit" ]
}

valid_release_name() {
  printf '%s\n' "$1" |
    grep -Eq '^notmuch-browser-antix-v[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+)?$'
}

prepare_release_source() {
  release=$1
  valid_release_name "$release" || die "invalid release tag format: $release"
  [ -d "$REPO_ROOT/.git" ] || die "guided bootstrap requires a Git clone"
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] ||
    die "guided bootstrap requires a clean repository"
  release_commit=$(git -C "$REPO_ROOT" rev-parse "$release^{commit}" 2>/dev/null) ||
    die "release tag is unavailable; run git fetch --tags and retry: $release"
  releases="$STATE_DIR/releases"
  release_source="$releases/$release-$release_commit"
  if [ ! -d "$release_source/.git" ]; then
    install -d -m 700 "$STATE_DIR" "$releases"
    incoming="$release_source.incoming-$$"
    [ ! -e "$incoming" ] ||
      die "release-source staging already exists and requires review: $incoming"
    git clone --quiet --no-checkout "$REPO_ROOT" "$incoming"
    git -C "$incoming" checkout --quiet --detach "$release"
    [ "$(git -C "$incoming" rev-parse HEAD)" = "$release_commit" ] ||
      die "release-source checkout identity mismatch"
    [ -z "$(git -C "$incoming" status --porcelain)" ] ||
      die "release-source checkout is not clean"
    mv "$incoming" "$release_source"
  fi
  [ "$(git -C "$release_source" rev-parse HEAD)" = "$release_commit" ] ||
    die "retained release-source identity mismatch"
  [ -z "$(git -C "$release_source" status --porcelain)" ] ||
    die "retained release-source is not clean"
  RELEASE_SOURCE=$release_source
  RELEASE_COMMIT=$release_commit
  export RELEASE_SOURCE RELEASE_COMMIT
  say "release_source=$release_source"
  say "release_commit=$release_commit"
}

run_from_release_source() {
  release=$1
  recovery_root=$2
  prepare_release_source "$release"
  exec env \
    NOTMUCH_FRESH_RELEASE_REEXEC=1 \
    NOTMUCH_FRESH_REPO_ROOT="$RELEASE_SOURCE" \
    NOTMUCH_FRESH_STATE_DIR="$STATE_DIR" \
    NOTMUCH_FRESH_LOG_DIR="$LOG_DIR" \
    "$RELEASE_SOURCE/scripts/notmuch_browser_fresh_vm_setup.sh" \
    guided-install --release "$release" --recovery-root "$recovery_root"
}

recovery_value() {
  set_file=$1
  key=$2
  awk -F= -v wanted="$key" '
    $1 == wanted {
      count++
      value=substr($0, length($1) + 2)
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' "$set_file"
}

verify_recovery_root() {
  recovery_root=$1
  [ -x "$RECOVERY_HELPER" ] || die "missing recovery helper: $RECOVERY_HELPER"
  [ -f "$recovery_root/recovery-set.env" ] ||
    die "missing recovery set: $recovery_root/recovery-set.env"
  [ "$EXPECTED_RECOVERY_SET_SHA256" != PENDING_CANONICAL_RECOVERY_SET ] ||
    die "this release does not yet pin a pilot-verified recovery set"
  actual_set_sha=$(sha256sum "$recovery_root/recovery-set.env" | awk '{print $1}')
  [ "$actual_set_sha" = "$EXPECTED_RECOVERY_SET_SHA256" ] ||
    die "recovery-set SHA256 is $actual_set_sha, expected $EXPECTED_RECOVERY_SET_SHA256"
  "$RECOVERY_HELPER" verify "$recovery_root"
}

install_os_packages_guided() {
  if all_packages_ready; then
    say "guided_stage=os_packages"
    say "guided_result=already_ready"
    return
  fi
  command_exists sudo || die "sudo is required for operating-system packages"
  command_exists apt || die "apt is required on the target antiX VM"
  say "guided_stage=os_packages"
  sudo apt update
  sudo apt install -y git curl ca-certificates unzip xz-utils rsync python3 \
    notmuch isync libsasl2-modules runit-antix runit-service-ssh iproute2 \
    openssh-client openssh-server build-essential
  all_packages_ready || die "required operating-system tools remain incomplete"
  say "guided_result=installed_and_verified"
}

install_go_guided() {
  if go_ready; then
    say "guided_stage=go"
    say "guided_result=already_ready"
    return
  fi
  if [ -e /usr/local/go ]; then
    die "/usr/local/go exists but is not exactly $EXPECTED_GO_VERSION; it was not replaced"
  fi
  install -d -m 700 "$STATE_DIR/downloads"
  archive="$STATE_DIR/downloads/go1.26.5.linux-amd64.tar.gz"
  say "guided_stage=go"
  if [ ! -f "$archive" ]; then
    curl -fL https://go.dev/dl/go1.26.5.linux-amd64.tar.gz -o "$archive"
    chmod 600 "$archive"
  fi
  printf '%s  %s\n' \
    5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053 \
    "$archive" | sha256sum -c -
  incoming=/usr/local/.go1.26.5.notmuch-browser-incoming
  if [ -e "$incoming" ]; then
    [ -d "$incoming" ] && [ ! -L "$incoming" ] ||
      die "unsafe Go staging path requires review: $incoming"
  else
    sudo install -d -m 755 "$incoming"
  fi
  sudo tar -C "$incoming" --strip-components=1 -xzf "$archive"
  [ "$("$incoming/bin/go" version 2>/dev/null | awk '{print $3}')" = "$EXPECTED_GO_VERSION" ] ||
    die "staged Go toolchain did not validate"
  sudo mv "$incoming" /usr/local/go
  PATH="/usr/local/go/bin:$PATH"
  export PATH
  go_ready || die "verified Go installation did not produce $EXPECTED_GO_VERSION"
  say "guided_result=installed_and_verified"
}

install_bun_guided() {
  if bun_ready; then
    say "guided_stage=bun"
    say "guided_result=already_ready"
    return
  fi
  [ ! -e "$HOME/.bun/bin/bun" ] ||
    die "$HOME/.bun/bin/bun exists but is not exactly Bun $EXPECTED_BUN_VERSION"
  install -d -m 700 "$STATE_DIR/downloads" "$STATE_DIR/tool-staging" "$HOME/.bun" \
    "$HOME/.bun/bin"
  archive="$STATE_DIR/downloads/bun-linux-x64-v1.3.14.zip"
  incoming="$STATE_DIR/tool-staging/bun-v1.3.14"
  say "guided_stage=bun"
  if [ ! -f "$archive" ]; then
    curl -fL \
      https://github.com/oven-sh/bun/releases/download/bun-v1.3.14/bun-linux-x64.zip \
      -o "$archive"
    chmod 600 "$archive"
  fi
  printf '%s  %s\n' "$EXPECTED_BUN_ARCHIVE_SHA256" "$archive" |
    sha256sum -c -
  staged_bun_version=$(
    "$incoming/bun-linux-x64/bun" --version 2>/dev/null || true
  )
  if [ ! -x "$incoming/bun-linux-x64/bun" ] ||
     [ "$staged_bun_version" != "$EXPECTED_BUN_VERSION" ]; then
    if [ -e "$incoming" ]; then
      [ -d "$incoming" ] && [ ! -L "$incoming" ] ||
        die "unsafe Bun staging path requires review: $incoming"
    else
      install -d -m 700 "$incoming"
    fi
    unzip -oq "$archive" -d "$incoming"
  fi
  install -m 755 "$incoming/bun-linux-x64/bun" "$HOME/.bun/bin/bun"
  bun_ready || die "verified Bun installation did not produce $EXPECTED_BUN_VERSION"
  say "guided_result=installed_and_verified"
}

configure_mbsync_guided() {
  if mbsync_ready; then
    say "guided_stage=mbsync"
    say "guided_result=already_ready"
    return
  fi
  helper="$REPO_ROOT/scripts/mbsync_provider_inbox_setup.sh"
  [ -x "$helper" ] || die "missing mbsync setup helper: $helper"
  say "guided_stage=mbsync"
  say "guided_notice=the IMAP app password prompt is hidden and is never copied into this setup state"
  "$helper" create-layout
  "$helper" write-config
  "$helper" list
  "$helper" dry-run
  "$helper" sync-once
  "$helper" production-layout
  "$helper" write-production-config
  "$helper" production-list
  "$helper" production-sync
  "$helper" write-autosync
  "$helper" install-autosync-startup
  "$helper" autosync-validate
  mbsync_ready || die "mbsync configuration or automatic loop did not validate"
  say "guided_result=configured_and_verified"
}

destination_empty_or_absent() {
  path=$1
  [ ! -e "$path" ] && return 0
  [ -d "$path" ] || return 1
  [ -z "$(find "$path" -mindepth 1 -print -quit)" ]
}

restore_package() {
  manifest=$1
  destination=$2
  label=$3
  marker="$STATE_DIR/restore-$label.env"
  manifest_sha=$(sha256sum "$manifest" | awk '{print $1}')

  if [ -d "$destination" ]; then
    if verification=$(python3 "$REPO_ROOT/src/maildirpp_transport.py" verify-tree \
      --manifest "$manifest" --dest "$destination" 2>&1); then
      printf '%s\n' "$verification"
      [ ! -e "$marker" ] || unlink "$marker"
      say "$label=already_restored_and_verified"
      return
    fi
  fi

  install -d -m 700 "$STATE_DIR"
  if [ -f "$marker" ]; then
    [ "$(recovery_value "$marker" manifest_sha256)" = "$manifest_sha" ] &&
      [ "$(recovery_value "$marker" destination)" = "$destination" ] ||
      die "$label restore marker does not match the requested package"
  else
    destination_empty_or_absent "$destination" ||
      die "$label destination contains unverified data: $destination"
    marker_tmp=$(mktemp "$STATE_DIR/.restore-$label.XXXXXX")
    {
      say "manifest_sha256=$manifest_sha"
      say "destination=$destination"
    } > "$marker_tmp"
    chmod 600 "$marker_tmp"
    mv "$marker_tmp" "$marker"
  fi

  if [ -e "$destination" ]; then
    python3 "$REPO_ROOT/src/maildirpp_transport.py" unpack \
      --manifest "$manifest" --dest "$destination" --allow-non-empty-dest
  else
    python3 "$REPO_ROOT/src/maildirpp_transport.py" unpack \
      --manifest "$manifest" --dest "$destination"
  fi
  python3 "$REPO_ROOT/src/maildirpp_transport.py" verify-tree \
    --manifest "$manifest" --dest "$destination"
  unlink "$marker"
  say "$label=restored_and_verified"
}

test_fixture_ready() {
  root="$MAILSTORE/evolution/test-maildir"
  [ -d "$root/cur" ] && [ -d "$root/new" ] && [ -d "$root/tmp" ] || return 1
  [ "$(find "$root/cur" -type f | wc -l | tr -d ' ')" = "$EXPECTED_TEST_MAILDIR_MESSAGES" ] ||
    return 1
  [ -z "$(find "$root/new" "$root/tmp" -type f -print -quit)" ] || return 1
  for name in 01-plain 02-addresses 03-html-images 04-attachment; do
    [ -f "$root/cur/$name" ] || return 1
  done
}

test_fixture_destination_empty_or_absent() {
  root=$1
  [ ! -e "$root" ] && return 0
  [ -d "$root" ] || return 1
  [ -z "$(find "$root" -mindepth 1 -maxdepth 1 \
    ! -name cur ! -name new ! -name tmp -print -quit)" ] || return 1
  for part in cur new tmp; do
    [ ! -e "$root/$part" ] || [ -d "$root/$part" ] || return 1
  done
  [ -z "$(find "$root" -mindepth 2 -print -quit)" ]
}

create_test_fixture() {
  root="$MAILSTORE/evolution/test-maildir"
  if test_fixture_ready; then
    say "test_maildir=already_ready"
    return
  fi
  test_fixture_destination_empty_or_absent "$root" ||
    die "test-maildir exists with unexpected content: $root"
  install -d -m 700 "$root" "$root/cur" "$root/new" "$root/tmp"
  cat > "$root/cur/01-plain" <<'EOF'
Message-ID: <notmuch-browser-fixture-01@example.test>
Date: Mon, 01 Jun 2026 09:00:01 +0000
From: Fixture Sender <sender@example.test>
To: Fixture Reader <reader@example.test>
Subject: Fixture 01 plain message
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Plain deterministic setup fixture.
EOF
  cat > "$root/cur/02-addresses" <<'EOF'
Message-ID: <notmuch-browser-fixture-02@example.test>
Date: Tue, 02 Jun 2026 10:02:03 +0000
From: Address Fixture <from@example.test>
To: First Reader <first@example.test>, second@example.test
Cc: Copy Reader <copy@example.test>
Bcc: Blind Reader <blind@example.test>
Subject: Fixture 02 address controls
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

Deterministic From, To, Cc, and Bcc address-link fixture.
EOF
  cat > "$root/cur/03-html-images" <<'EOF'
Message-ID: <notmuch-browser-fixture-03@example.test>
Date: Wed, 03 Jun 2026 11:04:05 +0000
From: HTML Fixture <html@example.test>
To: Fixture Reader <reader@example.test>
Subject: Fixture 03 confirmed images
MIME-Version: 1.0
Content-Type: multipart/related; boundary="fixture-related"

--fixture-related
Content-Type: text/html; charset=UTF-8

<html><body><p>Deterministic HTML fixture.</p><img src="cid:fixture-dot"><img src="https://example.test/remote.png"></body></html>
--fixture-related
Content-Type: image/gif
Content-Transfer-Encoding: base64
Content-ID: <fixture-dot>
Content-Disposition: inline; filename="fixture.gif"

R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==
--fixture-related--
EOF
  cat > "$root/cur/04-attachment" <<'EOF'
Message-ID: <notmuch-browser-fixture-04@example.test>
Date: Thu, 04 Jun 2026 12:06:07 +0000
From: Attachment Fixture <attachment@example.test>
To: Fixture Reader <reader@example.test>
Subject: Fixture 04 attachment
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="fixture-mixed"

--fixture-mixed
Content-Type: text/plain; charset=UTF-8

Deterministic attachment fixture.
--fixture-mixed
Content-Type: text/plain; name="fixture.txt"
Content-Disposition: attachment; filename="fixture.txt"
Content-Transfer-Encoding: base64

Zml4dHVyZSBhdHRhY2htZW50Cg==
--fixture-mixed--
EOF
  chmod 600 "$root/cur/01-plain" "$root/cur/02-addresses" \
    "$root/cur/03-html-images" "$root/cur/04-attachment"
  test_fixture_ready || die "deterministic test-maildir fixture failed validation"
  say "test_maildir=created_and_verified"
}

restore_recovery_set() {
  recovery_root=$1
  verify_recovery_root "$recovery_root"
  historical_dir=$(recovery_value "$recovery_root/recovery-set.env" historical_dir)
  delta_dir=$(recovery_value "$recovery_root/recovery-set.env" delta_dir)
  ARCHIVE_MANIFEST="$recovery_root/$historical_dir/manifest.json"
  export ARCHIVE_MANIFEST
  restore_package "$ARCHIVE_MANIFEST" "$ARCHIVE_DEST" historical_archive
  restore_package "$recovery_root/$delta_dir/manifest.json" \
    "$MAILSTORE/evolution/betterbird-delta-maildirpp-20260704" betterbird_delta
  install -d -m 700 "$MAILSTORE/evolution/provider-live-archive" \
    "$MAILSTORE/evolution/provider-live-archive/cur" \
    "$MAILSTORE/evolution/provider-live-archive/new" \
    "$MAILSTORE/evolution/provider-live-archive/tmp"
  create_test_fixture
  say "status=recovery_sources_restored"
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

source_path_parity() {
  source_root=$1
  expected_exact=$2
  label=$3
  stamp=$4
  [ -d "$source_root" ] || die "missing approved source root: $source_root"
  expected_paths=$(mktemp "$STATE_DIR/.source-expected.XXXXXX")
  actual_paths=$(mktemp "$STATE_DIR/.source-indexed.XXXXXX")
  find "$source_root" -type f \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    LC_ALL=C sort > "$expected_paths"
  notmuch --config="$CONFIG" search --output=files '*' |
    awk -v prefix="$source_root/" 'index($0, prefix) == 1 { print }' |
    LC_ALL=C sort > "$actual_paths"
  expected_count=$(wc -l < "$expected_paths" | tr -d ' ')
  actual_count=$(wc -l < "$actual_paths" | tr -d ' ')
  if [ "$expected_exact" != dynamic ] && [ "$expected_count" != "$expected_exact" ]; then
    die "$label source path count is $expected_count, expected $expected_exact"
  fi
  if ! cmp -s "$expected_paths" "$actual_paths"; then
    diff -u "$expected_paths" "$actual_paths" > "$LOG_DIR/$label-index-path-diff-$stamp.txt" || true
    die "$label path parity failed: indexed $actual_count of $expected_count"
  fi
  path_sha=$(sha256sum "$actual_paths" | awk '{print $1}')
  rm -f "$expected_paths" "$actual_paths"
  printf '%s|%s\n' "$actual_count" "$path_sha"
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

  delta_parity=$(source_path_parity \
    "$MAILSTORE/evolution/betterbird-delta-maildirpp-20260704" \
    "$EXPECTED_DELTA_CUR" betterbird-delta "$stamp")
  delta_count=${delta_parity%%|*}
  delta_path_sha=${delta_parity#*|}
  provider_test_parity=$(source_path_parity \
    "$MAILSTORE/mbsync/provider-inbox-test" dynamic provider-inbox-test "$stamp")
  provider_test_count=${provider_test_parity%%|*}
  provider_test_path_sha=${provider_test_parity#*|}
  provider_live_parity=$(source_path_parity \
    "$MAILSTORE/mbsync/provider-live" dynamic provider-live "$stamp")
  provider_live_count=${provider_live_parity%%|*}
  provider_live_path_sha=${provider_live_parity#*|}
  provider_archive_parity=$(source_path_parity \
    "$MAILSTORE/evolution/provider-live-archive" 0 provider-live-archive "$stamp")
  provider_archive_count=${provider_archive_parity%%|*}
  provider_archive_path_sha=${provider_archive_parity#*|}
  test_parity=$(source_path_parity \
    "$MAILSTORE/evolution/test-maildir" "$EXPECTED_TEST_MAILDIR_MESSAGES" \
    test-maildir "$stamp")
  test_count=${test_parity%%|*}
  test_path_sha=${test_parity#*|}

  marker_tmp=$(mktemp "$STATE_DIR/.initial-index.XXXXXX")
  {
    say "archive_indexed_files=$actual_count"
    say "archive_paths_sha256=$path_sha"
    say "betterbird_delta_indexed_files=$delta_count"
    say "betterbird_delta_paths_sha256=$delta_path_sha"
    say "provider_inbox_test_indexed_files=$provider_test_count"
    say "provider_inbox_test_paths_sha256=$provider_test_path_sha"
    say "provider_live_indexed_files=$provider_live_count"
    say "provider_live_paths_sha256=$provider_live_path_sha"
    say "provider_live_archive_indexed_files=$provider_archive_count"
    say "provider_live_archive_paths_sha256=$provider_archive_path_sha"
    say "test_maildir_indexed_files=$test_count"
    say "test_maildir_paths_sha256=$test_path_sha"
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
  say "approved_source_path_parity=pass"
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
    "$MAIL_ROOT/Logs/notmuch-browser" "$MAIL_ROOT/Backups/notmuch-browser" \
    "$STATE_DIR/backups"
  install -d -m 755 "$BIN_DIR"
  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$STATE_DIR/backups/$stamp-before-browser-install"
  install -d -m 700 "$backup"
  stage="$BIN_DIR/.notmuch-browser-install-$stamp-$$"
  [ ! -e "$stage" ] || die "unexpected install staging path: $stage"
  install -d -m 700 "$stage"
  install -m 755 "$REPO_ROOT/notmuch-browser" "$stage/notmuch-browser"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_control.sh" \
    "$stage/notmuch-browser-control"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_index_control.sh" \
    "$stage/notmuch-browser-index-control"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_runit_setup.sh" \
    "$stage/notmuch-browser-runit-setup"
  install -m 755 "$REPO_ROOT/scripts/notmuch_browser_fresh_vm_setup.sh" \
    "$stage/notmuch-browser-fresh-vm-setup"
  sha256sum "$stage/notmuch-browser" "$stage/notmuch-browser-control" \
    "$stage/notmuch-browser-index-control" "$stage/notmuch-browser-runit-setup" \
    "$stage/notmuch-browser-fresh-vm-setup" > "$stage/artifacts.sha256"
  chmod 600 "$stage/artifacts.sha256"

  for name in notmuch-browser notmuch-browser-control notmuch-browser-index-control notmuch-browser-runit-setup notmuch-browser-fresh-vm-setup; do
    [ ! -e "$BIN_DIR/$name" ] || cp -p "$BIN_DIR/$name" "$backup/$name"
  done
  [ ! -f "$INSTALL_MARKER" ] ||
    cp -p "$INSTALL_MARKER" "$backup/browser-installed.env"
  install_in_progress=yes
  export install_in_progress backup
  trap '
    if [ "${install_in_progress:-no}" = yes ]; then
      for restore_name in notmuch-browser notmuch-browser-control notmuch-browser-index-control notmuch-browser-runit-setup notmuch-browser-fresh-vm-setup; do
        if [ -f "$backup/$restore_name" ]; then
          cp -p "$backup/$restore_name" "$BIN_DIR/$restore_name" 2>/dev/null || true
        else
          unlink "$BIN_DIR/$restore_name" 2>/dev/null || true
        fi
      done
      if [ -f "$backup/browser-installed.env" ]; then
        cp -p "$backup/browser-installed.env" "$INSTALL_MARKER" 2>/dev/null || true
      else
        unlink "$INSTALL_MARKER" 2>/dev/null || true
      fi
    fi
  ' EXIT HUP INT TERM
  for name in notmuch-browser notmuch-browser-control notmuch-browser-index-control notmuch-browser-runit-setup notmuch-browser-fresh-vm-setup; do
    mv "$stage/$name" "$BIN_DIR/$name"
  done

  marker_tmp=$(mktemp "$STATE_DIR/.browser-installed.XXXXXX")
  {
    sha256sum "$BIN_DIR/notmuch-browser" "$BROWSER_CONTROL" "$INDEX_CONTROL" "$RUNIT_SETUP"
    say "installed_at=$(date -Is 2>/dev/null || date)"
    say "source_commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || say unknown)"
    say "backup=$backup"
  } > "$marker_tmp"
  chmod 600 "$marker_tmp"
  mv "$marker_tmp" "$INSTALL_MARKER"
  browser_installed || die "installed browser artifacts did not match their marker"
  install_in_progress=no
  trap - EXIT HUP INT TERM
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

validate_fixture_contracts() {
  catalog=$(curl -fsS --max-time 20 http://127.0.0.1:8765/)
  for label in \
    "Live provider" \
    "Provider inbox test" \
    "Historical local archive" \
    "Betterbird delta" \
    "Provider live archive" \
    "Evolution test mail"; do
    printf '%s\n' "$catalog" | grep -Fq "$label" ||
      die "GUI source catalog is missing: $label"
  done

  fixture_search=$(curl -fsS --max-time 30 --get \
    --data-urlencode 'q=*' \
    --data-urlencode 'folder=evolution/test-maildir' \
    http://127.0.0.1:8765/search)
  for subject in \
    "Fixture 01 plain message" \
    "Fixture 02 address controls" \
    "Fixture 03 confirmed images" \
    "Fixture 04 attachment"; do
    printf '%s\n' "$fixture_search" | grep -Fq "$subject" ||
      die "deterministic fixture search is missing: $subject"
  done

  address_page=$(curl -fsS --max-time 30 --get \
    --data-urlencode 'id=notmuch-browser-fixture-02@example.test' \
    --data-urlencode 'folder=evolution/test-maildir' \
    http://127.0.0.1:8765/message)
  for contract in \
    'mailto:from@example.test' \
    'mailto:first@example.test' \
    'mailto:copy@example.test' \
    'mailto:blind@example.test' \
    'data-copy-text="from@example.test"' \
    'data-copy-feedback-ms="2200"'; do
    printf '%s\n' "$address_page" | grep -Fq "$contract" ||
      die "address fixture contract is missing"
  done

  attachment_page=$(curl -fsS --max-time 30 --get \
    --data-urlencode 'id=notmuch-browser-fixture-04@example.test' \
    --data-urlencode 'folder=evolution/test-maildir' \
    http://127.0.0.1:8765/message)
  printf '%s\n' "$attachment_page" | grep -Fq 'fixture.txt' ||
    die "attachment fixture contract is missing"
  say "source_catalog_contract=pass"
  say "test_maildir_four_message_contract=pass"
  say "address_link_copy_feedback_contract=pass"
  say "attachment_contract=pass"
}

validate_full() {
  validate_installation
  validate_fixture_contracts
  say "status=fresh_vm_full_validation_passed"
}

validate_post_reboot() {
  [ -s "$GUIDED_STATE" ] ||
    die "guided installation state is missing; complete guided-install first"
  completed_boot=$(recovery_value "$GUIDED_STATE" completed_boot_id)
  current_boot=$(cat /proc/sys/kernel/random/boot_id)
  [ -n "$completed_boot" ] && [ "$current_boot" != "$completed_boot" ] ||
    die "a changed antiX boot has not yet been observed"
  validate_full
  mbsync_ready || die "mbsync automatic loop did not recover after reboot"
  say "completed_boot_id=$completed_boot"
  say "current_boot_id=$current_boot"
  say "status=post_reboot_validation_passed"
}

prove_new_mail_indexing() {
  services_ready || die "browser/index services must be healthy"
  mbsync_ready || die "mbsync automatic loop must be running and unpaused"
  token="NOTMUCH-SETUP-$(date +%Y%m%d-%H%M%S)-$$"
  say "probe_subject=$token"
  say "action=send one email to the configured account with exactly this subject"
  printf 'Press Enter only after sending that message: ' >&2
  IFS= read -r ignored
  attempt=0
  while [ "$attempt" -lt 42 ]; do
    if notmuch --config="$CONFIG" count "subject:$token" 2>/dev/null |
       grep -Eq '^[1-9][0-9]*$'; then
      install -d -m 700 "$STATE_DIR"
      tmp=$(mktemp "$STATE_DIR/.new-mail-proof.XXXXXX")
      {
        say "probe_subject=$token"
        say "proved_at=$(date -Is 2>/dev/null || date)"
        say "boot_id=$(cat /proc/sys/kernel/random/boot_id)"
      } > "$tmp"
      chmod 600 "$tmp"
      mv "$tmp" "$STATE_DIR/automatic-new-mail-indexing.env"
      say "automatic_new_mail_indexing=pass"
      say "status=new_mail_probe_passed"
      return
    fi
    sleep 10
    attempt=$((attempt + 1))
  done
  die "the probe message did not become searchable within seven minutes"
}

support_report() {
  install -d -m 700 "$LOG_DIR"
  stamp=$(date +%Y%m%d-%H%M%S)
  report="$LOG_DIR/support-report-$stamp.txt"
  tmp=$(mktemp "$LOG_DIR/.support-report.XXXXXX")
  {
    say "schema_version=1"
    say "created_at=$(date -Is 2>/dev/null || date)"
    say "boot_id=$(cat /proc/sys/kernel/random/boot_id)"
    say "mail_fstype=$(mail_fstype)"
    say "mail_free_kib=$(free_kib || true)"
    say "go_version=$(go version 2>/dev/null || say unavailable)"
    bun_bin=$(bun_command 2>/dev/null || true)
    if [ -n "$bun_bin" ]; then
      say "bun_version=$("$bun_bin" --version 2>/dev/null || say unavailable)"
    else
      say "bun_version=unavailable"
    fi
    if [ -x "$BIN_DIR/notmuch-browser" ]; then
      say "browser_sha256=$(sha256sum "$BIN_DIR/notmuch-browser" | awk '{print $1}')"
    else
      say "browser_sha256=unavailable"
    fi
    say "new_ignore=$(notmuch_value new.ignore | tr '\n' ',' | sed 's/,$//')"
    say "browser_service=$(sv status "$ACTIVE_SERVICE_ROOT/notmuch-browser" 2>/dev/null || say unavailable)"
    say "index_service=$(sv status "$ACTIVE_SERVICE_ROOT/notmuch-browser-index" 2>/dev/null || say unavailable)"
    health=$(curl -fsS --max-time 20 http://127.0.0.1:8765/healthz 2>/dev/null || true)
    if printf '%s\n' "$health" | grep -Fq '"ok":true'; then
      say "health_ok=yes"
    else
      say "health_ok=no"
    fi
    say "mbsync_lock=$([ -e "$MAIL_ROOT/AppData/isync/provider-live-loop/lock" ] && say present || say absent)"
    say "refresh_lock=$([ -e "$MAIL_ROOT/AppData/notmuch-browser/index-refresh.lock" ] && say present || say absent)"
    say "download_tmp_files=$(find "$MAIL_ROOT/AppData/notmuch-browser/download-tmp" -type f 2>/dev/null | wc -l | tr -d ' ')"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$report"
  say "support_report=$report"
  say "support_report_sha256=$(sha256sum "$report" | awk '{print $1}')"
  say "status=support_report_created"
}

write_guided_state() {
  release=$1
  recovery_root=$2
  install -d -m 700 "$STATE_DIR"
  tmp=$(mktemp "$STATE_DIR/.guided-install.XXXXXX")
  {
    say "schema_version=1"
    say "release=$release"
    say "source_commit=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || say unknown)"
    say "recovery_set_sha256=$(sha256sum "$recovery_root/recovery-set.env" | awk '{print $1}')"
    say "historical_archive_sha256=$EXPECTED_ARCHIVE_SHA256"
    say "historical_archive_cur=$EXPECTED_ARCHIVE_CUR"
    say "betterbird_delta_cur=$EXPECTED_DELTA_CUR"
    say "test_maildir_messages=$EXPECTED_TEST_MAILDIR_MESSAGES"
    say "completed_boot_id=$(cat /proc/sys/kernel/random/boot_id)"
    say "completed_at=$(date -Is 2>/dev/null || date)"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$GUIDED_STATE"
}

prompt_notmuch_identity() {
  if [ -n "${NOTMUCH_FRESH_NOTMUCH_NAME:-}" ]; then
    guided_name=$NOTMUCH_FRESH_NOTMUCH_NAME
  else
    printf 'Your display name for notmuch: ' >&2
    IFS= read -r guided_name
  fi
  if [ -n "${NOTMUCH_FRESH_NOTMUCH_EMAIL:-}" ]; then
    guided_email=$NOTMUCH_FRESH_NOTMUCH_EMAIL
  else
    printf 'Your primary email address for notmuch: ' >&2
    IFS= read -r guided_email
  fi
  [ -n "$guided_name" ] || die "notmuch display name must not be empty"
  case "$guided_email" in
    *@*.*) ;;
    *) die "notmuch primary email does not look valid" ;;
  esac
}

verify_guided_mail_preflight() {
  mail_ready || die "$MAIL_ROOT must already be a dedicated XFS mount"
  available=$(free_kib)
  [ -n "$available" ] || die "could not measure free space on $MAIL_ROOT"
  [ "$available" -ge "$MIN_FREE_KIB" ] ||
    die "only $available KiB free; at least $MIN_FREE_KIB KiB is required"
}

guided_install() {
  release=
  recovery_root=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --release)
        [ "$#" -ge 2 ] || die "--release requires a value"
        release=$2
        shift 2
        ;;
      --recovery-root)
        [ "$#" -ge 2 ] || die "--recovery-root requires a value"
        recovery_root=$2
        shift 2
        ;;
      *) die "unknown guided-install argument: $1" ;;
    esac
  done
  [ -n "$release" ] || die "guided-install requires --release TAG"
  [ -n "$recovery_root" ] || die "guided-install requires --recovery-root PATH"
  case "$recovery_root" in
    /*) ;;
    *) die "--recovery-root must be an absolute path" ;;
  esac

  if [ "${NOTMUCH_FRESH_TEST_MODE:-0}" != 1 ] &&
     [ "${NOTMUCH_FRESH_RELEASE_REEXEC:-0}" != 1 ]; then
    verify_guided_mail_preflight
    run_from_release_source "$release" "$recovery_root"
  fi

  say "guided_stage=preflight"
  verify_guided_mail_preflight
  if [ "${NOTMUCH_FRESH_TEST_MODE:-0}" != 1 ]; then
    release_ready "$release" ||
      die "repository must be clean and checked out at exact release tag $release"
  fi
  verify_recovery_root "$recovery_root"
  say "guided_result=release_disk_recovery_verified"

  install_os_packages_guided
  install_go_guided
  install_bun_guided
  configure_mbsync_guided
  restore_recovery_set "$recovery_root"

  ARCHIVE_MANIFEST="$recovery_root/$(recovery_value "$recovery_root/recovery-set.env" historical_dir)/manifest.json"
  export ARCHIVE_MANIFEST
  if archive_acknowledged; then
    say "guided_stage=archive_acknowledgement"
    say "guided_result=already_ready"
  else
    acknowledge_archive
  fi
  if notmuch_config_ready; then
    say "guided_stage=notmuch_configuration"
    say "guided_result=already_ready"
  else
    prompt_notmuch_identity
    configure_notmuch "$guided_name" "$guided_email"
  fi
  if initial_index_ready; then
    say "guided_stage=initial_index"
    say "guided_result=already_ready"
  else
    initial_index
  fi
  if browser_installed; then
    say "guided_stage=browser_install"
    say "guided_result=already_ready"
  else
    build_install
  fi
  if services_ready; then
    say "guided_stage=services"
    say "guided_result=already_ready"
  else
    enable_services
  fi
  validate_installation
  write_guided_state "$release" "$recovery_root"
  say "guided_state=$GUIDED_STATE"
  say "status=guided_install_complete"
}

update_installation() {
  [ "$#" -eq 2 ] && [ "$1" = --release ] ||
    die "usage: update --release TAG"
  release=$2
  services_ready || die "update requires an already healthy installation"
  [ -d "$REPO_ROOT/.git" ] || die "repository clone is missing"
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] || die "repository has uncommitted changes"
  branch=$(git -C "$REPO_ROOT" branch --show-current)
  [ "$branch" = main ] || die "safe updates must run from the main branch, not $branch"

  git -C "$REPO_ROOT" pull --ff-only origin main
  git -C "$REPO_ROOT" fetch --tags origin
  prepare_release_source "$release"
  source_root=$RELEASE_SOURCE
  source_commit=$RELEASE_COMMIT
  bun_bin=$(bun_command)
  build_dir="$STATE_DIR/release-builds/$release-$source_commit"
  install -d -m 700 "$build_dir"
  build_binary="$build_dir/notmuch-browser"
  BUN_BIN="$bun_bin" NOTMUCH_BROWSER_BUILD_OUTPUT="$build_binary" \
    "$source_root/scripts/notmuch_browser_build.sh" all
  [ -x "$build_binary" ] || die "release build did not produce its binary"

  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$STATE_DIR/backups/$stamp-before-git-update"
  install -d -m 700 "$backup"
  cp -p "$BIN_DIR/notmuch-browser" "$backup/notmuch-browser"
  cp -p "$BROWSER_CONTROL" "$backup/notmuch-browser-control"
  cp -p "$INDEX_CONTROL" "$backup/notmuch-browser-index-control"
  cp -p "$RUNIT_SETUP" "$backup/notmuch-browser-runit-setup"
  [ ! -f "$INSTALL_MARKER" ] ||
    cp -p "$INSTALL_MARKER" "$backup/browser-installed.env"
  [ ! -e "$BIN_DIR/notmuch-browser-fresh-vm-setup" ] ||
    cp -p "$BIN_DIR/notmuch-browser-fresh-vm-setup" \
      "$backup/notmuch-browser-fresh-vm-setup"

  UPDATE_IN_PROGRESS=yes
  UPDATE_BACKUP=$backup
  export UPDATE_IN_PROGRESS UPDATE_BACKUP
  trap '
    if [ "${UPDATE_IN_PROGRESS:-no}" = yes ]; then
      cp -p "$UPDATE_BACKUP/notmuch-browser" "$BIN_DIR/notmuch-browser" 2>/dev/null || true
      cp -p "$UPDATE_BACKUP/notmuch-browser-control" "$BROWSER_CONTROL" 2>/dev/null || true
      cp -p "$UPDATE_BACKUP/notmuch-browser-index-control" "$INDEX_CONTROL" 2>/dev/null || true
      cp -p "$UPDATE_BACKUP/notmuch-browser-runit-setup" "$RUNIT_SETUP" 2>/dev/null || true
      if [ -f "$UPDATE_BACKUP/notmuch-browser-fresh-vm-setup" ]; then
        cp -p "$UPDATE_BACKUP/notmuch-browser-fresh-vm-setup" "$BIN_DIR/notmuch-browser-fresh-vm-setup" 2>/dev/null || true
      fi
      if [ -f "$UPDATE_BACKUP/browser-installed.env" ]; then
        cp -p "$UPDATE_BACKUP/browser-installed.env" "$INSTALL_MARKER" 2>/dev/null || true
      else
        unlink "$INSTALL_MARKER" 2>/dev/null || true
      fi
      sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser" >/dev/null 2>&1 || true
      sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index" >/dev/null 2>&1 || true
    fi
  ' EXIT HUP INT TERM

  sv down "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
  sv down "$ACTIVE_SERVICE_ROOT/notmuch-browser"
  if install -m 755 "$build_binary" "$BIN_DIR/notmuch-browser" &&
     install -m 755 "$source_root/scripts/notmuch_browser_control.sh" "$BROWSER_CONTROL" &&
     install -m 755 "$source_root/scripts/notmuch_browser_index_control.sh" "$INDEX_CONTROL" &&
     install -m 755 "$source_root/scripts/notmuch_browser_runit_setup.sh" "$RUNIT_SETUP" &&
     install -m 755 "$source_root/scripts/notmuch_browser_fresh_vm_setup.sh" \
       "$BIN_DIR/notmuch-browser-fresh-vm-setup"; then
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
  else
    cp -p "$backup/notmuch-browser" "$BIN_DIR/notmuch-browser"
    cp -p "$backup/notmuch-browser-control" "$BROWSER_CONTROL"
    cp -p "$backup/notmuch-browser-index-control" "$INDEX_CONTROL"
    cp -p "$backup/notmuch-browser-runit-setup" "$RUNIT_SETUP"
    [ ! -f "$backup/notmuch-browser-fresh-vm-setup" ] ||
      cp -p "$backup/notmuch-browser-fresh-vm-setup" \
        "$BIN_DIR/notmuch-browser-fresh-vm-setup"
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
    [ ! -f "$backup/notmuch-browser-fresh-vm-setup" ] ||
      cp -p "$backup/notmuch-browser-fresh-vm-setup" \
        "$BIN_DIR/notmuch-browser-fresh-vm-setup"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser"
    sv up "$ACTIVE_SERVICE_ROOT/notmuch-browser-index"
    die "new version failed validation; prior application files were restored from $backup"
  fi
  marker_tmp=$(mktemp "$STATE_DIR/.browser-installed.XXXXXX")
  {
    sha256sum "$BIN_DIR/notmuch-browser" "$BROWSER_CONTROL" "$INDEX_CONTROL" "$RUNIT_SETUP"
    say "installed_at=$(date -Is 2>/dev/null || date)"
    say "source_release=$release"
    say "source_commit=$source_commit"
    say "backup=$backup"
  } > "$marker_tmp"
  chmod 600 "$marker_tmp"
  mv "$marker_tmp" "$INSTALL_MARKER"
  browser_installed || die "updated artifacts did not match the new install marker"
  UPDATE_IN_PROGRESS=no
  trap - EXIT HUP INT TERM
  say "status=release_update_complete"
  say "source_release=$release"
  say "source_commit=$source_commit"
  say "backup=$backup"
}

usage() {
  cat <<'EOF'
Usage: scripts/notmuch_browser_fresh_vm_setup.sh COMMAND [ARGS]

Beginner workflow:
  guided-install --release TAG --recovery-root ABSOLUTE_PATH
      Run the complete resumable setup after /mail is safely mounted. Verify the
      pinned release and private recovery set, install exact prerequisites,
      securely configure mbsync/notmuch, restore approved sources, index, build,
      install, enable user runit, and validate. Rerun the identical command to
      resume after a safe block, interruption, logout, or reboot.
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
      intentionally indexed; only the unavailable legacy archive is ignored.
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
  validate --full
      Repeat base validation and prove the six-source catalog plus deterministic
      four-message address, copied-feedback, and attachment contracts.
  validate --post-reboot
      Require a changed boot ID, then repeat full validation and mbsync recovery.
  prove-new-mail-indexing
      Generate a harmless subject token, wait for the operator to send it, and
      prove that mbsync plus the index loop make it searchable without restart.
  support-report
      Write a private mode-600, credential-free status report and print its hash.
  update --release TAG
      On a clean main branch, pull --ff-only, fetch the explicitly approved
      release tag, build only that tag, back up, install, validate, and restore
      the previous application files automatically on failure.
  help
      Show this help.

Run `next` after each completed stage. See
docs/NOTMUCH_GO_BROWSER_SERVICE_GUIDE.html for the complete beginner guide.
EOF
}

command_name=${1:-help}
case "$command_name" in
  _test-restore-package)
    [ "${NOTMUCH_FRESH_TEST_MODE:-0}" = 1 ] ||
      die "internal test command is unavailable"
    [ "$#" -eq 4 ] || die "internal restore test requires MANIFEST DEST LABEL"
    restore_package "$2" "$3" "$4"
    ;;
  _test-create-fixture)
    [ "${NOTMUCH_FRESH_TEST_MODE:-0}" = 1 ] ||
      die "internal test command is unavailable"
    create_test_fixture
    ;;
  guided-install)
    shift
    guided_install "$@"
    ;;
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
  validate)
    case "${2:-}" in
      '') validate_installation ;;
      --full) [ "$#" -eq 2 ] || die "usage: validate --full"; validate_full ;;
      --post-reboot)
        [ "$#" -eq 2 ] || die "usage: validate --post-reboot"
        validate_post_reboot
        ;;
      *) die "usage: validate [--full|--post-reboot]" ;;
    esac
    ;;
  prove-new-mail-indexing) prove_new_mail_indexing ;;
  support-report) support_report ;;
  update)
    shift
    update_installation "$@"
    ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
