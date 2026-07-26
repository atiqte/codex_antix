#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 04: read-only enrollment backup, capacity, and command-path preflight.
G4_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G4_COMMIT=48dd71d0050bfd5379b23cbdb5b8dcc570c254d1
G4_BRANCH=atiqte/branch-codex
G4_MAIL_ROOT=/mail
G4_MAILSTORE=/mail/Mailstore
G4_CONFIG=/home/atiq/.config/notmuch/default/config
G4_DB=/mail/SearchIndex/notmuch/default
G4_STATE=/mail/AppData/notmuch-browser/source-enrollment
G4_LOG=/mail/Logs/notmuch-browser/source-enrollment
G4_BACKUP_ROOT=/mail/Backups/notmuch-browser
G4_BACKUP_POINTER="$G4_STATE/current-backup"
G4_MARKER="$G4_STATE/current-sources-acknowledged.env"
G4_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G4_HELPER="$G4_REPO/scripts/notmuch_browser_source_enroll.sh"
G4_GATE3_BATCH="$G4_REPO/docs/validation/notmuch-browser-multisource/batches/03-corrected-acknowledgement-identity-audit.sh"
G4_GATE3_LOG="$G4_REPO/docs/validation/notmuch-browser-multisource/logs/03-corrected-acknowledgement-identity-audit.log"
G4_GATE3_BATCH_SHA=9b65bbaa9224d2b6e27a2b11beeca099891ca1e703c3bd82189158bab9095d6b
G4_GATE3_LOG_SHA=33c5b7c79deed0f491afa2f5e0323623d1d20c089cfd246877a2321f9d3c26bd
G4_MIN_FREE_KIB=83886080

g4_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g4_equal() {
  local label=$1
  local actual=$2
  local expected=$3
  if [[ "$actual" != "$expected" ]]; then
    printf 'status=blocked\nreason=%s mismatch\nactual=%s\nexpected=%s\n' \
      "$label" "$actual" "$expected" >&2
    exit 1
  fi
  printf '%s=%s\n' "$label" "$actual"
}

g4_path_inventory_bytes() {
  find "$1" -type f \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    wc -c |
    tr -d ' '
}

printf '%s\n' 'gate=04-read-only-enrollment-backup-capacity-preflight'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_sizes_hashes_mounts_and_statuses_only'
printf '%s\n' 'authorized_write=none'

for tool in git bash sh find findmnt df du stat sha256sum notmuch awk sed grep sort wc tr paste curl python3 cp date; do
  command -v "$tool" >/dev/null 2>&1 || g4_die "missing required command: $tool"
done

cd "$G4_REPO"
g4_equal repository_commit "$(git rev-parse HEAD)" "$G4_COMMIT"
g4_equal repository_branch "$(git branch --show-current)" "$G4_BRANCH"
g4_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G4_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g4_die "repository is not clean"
printf '%s\n' repository_clean=yes
g4_equal gate_03_batch_sha256 \
  "$(sha256sum "$G4_GATE3_BATCH" | awk '{print $1}')" "$G4_GATE3_BATCH_SHA"
g4_equal gate_03_log_sha256 \
  "$(sha256sum "$G4_GATE3_LOG" | awk '{print $1}')" "$G4_GATE3_LOG_SHA"
g4_equal enrollment_helper_sha256 \
  "$(sha256sum "$G4_HELPER" | awk '{print $1}')" \
  61a96a587c8e25ddef290a118e95a335ca2f47481dec8925e57f49c6342d0fee
sh -n "$G4_HELPER"

g4_equal mail_fstype "$(findmnt -n -o FSTYPE --target "$G4_MAIL_ROOT")" xfs
g4_equal database_mount_target "$(findmnt -n -o TARGET --target "$G4_DB")" "$G4_MAIL_ROOT"
g4_equal backup_mount_target "$(findmnt -n -o TARGET --target "$G4_BACKUP_ROOT")" "$G4_MAIL_ROOT"
G4_FREE_KIB=$(df -Pk "$G4_MAIL_ROOT" | awk 'NR == 2 { print $4 }')
[[ "$G4_FREE_KIB" =~ ^[0-9]+$ ]] || g4_die "cannot read free space"
(( G4_FREE_KIB >= G4_MIN_FREE_KIB )) ||
  g4_die "less than 80 GiB is free on /mail"
printf 'mail_free_kib=%s\n' "$G4_FREE_KIB"

for directory in "$G4_DB" "$G4_STATE" "$G4_BACKUP_ROOT"; do
  [[ -d "$directory" && ! -L "$directory" ]] ||
    g4_die "required directory is missing or unsafe: $directory"
  [[ -r "$directory" && -w "$directory" && -x "$directory" ]] ||
    g4_die "required directory access is insufficient: $directory"
  printf 'directory_state=%s:mode=%s:owner=%s\n' \
    "$directory" "$(stat -c '%a' "$directory")" "$(stat -c '%U' "$directory")"
done
if [[ -e "$G4_LOG" ]]; then
  [[ -d "$G4_LOG" && ! -L "$G4_LOG" && -r "$G4_LOG" && -w "$G4_LOG" && -x "$G4_LOG" ]] ||
    g4_die "existing enrollment log directory is unsafe"
  printf 'prospective_log_directory=%s:existing-safe\n' "$G4_LOG"
else
  G4_LOG_PARENT=${G4_LOG%/*}
  [[ -d "$G4_LOG_PARENT" && ! -L "$G4_LOG_PARENT" &&
    -r "$G4_LOG_PARENT" && -w "$G4_LOG_PARENT" && -x "$G4_LOG_PARENT" ]] ||
    g4_die "enrollment log parent is unsafe"
  printf 'prospective_log_directory=%s:absent-parent-safe\n' "$G4_LOG"
fi

[[ -f "$G4_CONFIG" && ! -L "$G4_CONFIG" ]] || g4_die "unsafe notmuch config"
[[ -f "$G4_MARKER" && ! -L "$G4_MARKER" ]] || g4_die "unsafe acknowledgement marker"
g4_equal marker_sha256 "$(sha256sum "$G4_MARKER" | awk '{print $1}')" "$G4_MARKER_SHA"
g4_equal marker_mode "$(stat -c '%a' "$G4_MARKER")" 600
[[ ! -e "$G4_BACKUP_POINTER" ]] || g4_die "enrollment backup pointer already exists"
g4_equal prior_enrollment_backup_directories \
  "$(find "$G4_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'source-enrollment-*' -print | wc -l | tr -d ' ')" \
  0

G4_DB_KIB=$(du -sk "$G4_DB" | awk '{print $1}')
G4_DB_FILES=$(find "$G4_DB" -type f -print | wc -l | tr -d ' ')
G4_DB_MANIFEST_SHA=$(
  (
  cd "$G4_DB"
  find . -type f -printf '%P\t%s\t%T@\t%m\n' |
    LC_ALL=C sort |
    sha256sum |
    awk '{print $1}'
  )
)
[[ "$G4_DB_KIB" =~ ^[0-9]+$ && "$G4_DB_FILES" =~ ^[0-9]+$ ]] ||
  g4_die "database footprint is invalid"
printf 'database_kib=%s\n' "$G4_DB_KIB"
printf 'database_regular_files=%s\n' "$G4_DB_FILES"
printf 'database_manifest_sha256=%s\n' "$G4_DB_MANIFEST_SHA"

G4_BACKUP_EXISTING_KIB=$(du -sk "$G4_BACKUP_ROOT" | awk '{print $1}')
G4_ESTIMATED_REQUIRED_KIB=$((G4_DB_KIB * 3 + 1048576))
printf 'existing_backup_root_kib=%s\n' "$G4_BACKUP_EXISTING_KIB"
printf 'conservative_enrollment_backup_required_kib=%s\n' "$G4_ESTIMATED_REQUIRED_KIB"
(( G4_FREE_KIB >= G4_MIN_FREE_KIB + G4_ESTIMATED_REQUIRED_KIB )) ||
  g4_die "free space does not cover the 80 GiB floor plus conservative backup estimate"
printf '%s\n' backup_capacity_gate=pass

G4_TAG_DUMP_BYTES=$(notmuch --config="$G4_CONFIG" dump --format=batch-tag | wc -c | tr -d ' ')
G4_TAG_DUMP_SHA=$(notmuch --config="$G4_CONFIG" dump --format=batch-tag |
  sha256sum |
  awk '{print $1}')
G4_INDEXED_PATH_COUNT=$(notmuch --config="$G4_CONFIG" search --exclude=false --output=files '*' |
  wc -l |
  tr -d ' ')
G4_INDEXED_PATH_SHA=$(notmuch --config="$G4_CONFIG" search --exclude=false --output=files '*' |
  LC_ALL=C sort |
  sha256sum |
  awk '{print $1}')
printf 'tag_dump_bytes=%s\n' "$G4_TAG_DUMP_BYTES"
printf 'tag_dump_sha256=%s\n' "$G4_TAG_DUMP_SHA"
printf 'indexed_path_count_exclude_false=%s\n' "$G4_INDEXED_PATH_COUNT"
printf 'indexed_path_sha256_sorted=%s\n' "$G4_INDEXED_PATH_SHA"
printf '%s\n' exact_backup_command_paths=pass

printf 'local_maildir_path_inventory_bytes=%s\n' \
  "$(g4_path_inventory_bytes "$G4_MAILSTORE/evolution/local-maildir")"
printf 'betterbird_delta_path_inventory_bytes=%s\n' \
  "$(g4_path_inventory_bytes "$G4_MAILSTORE/evolution/betterbird-delta-maildirpp-20260704")"
printf 'provider_test_path_inventory_bytes=%s\n' \
  "$(g4_path_inventory_bytes "$G4_MAILSTORE/mbsync/provider-inbox-test")"
printf 'evolution_test_path_inventory_bytes=%s\n' \
  "$(g4_path_inventory_bytes "$G4_MAILSTORE/evolution/test-maildir")"
printf 'provider_archive_path_inventory_bytes=%s\n' \
  "$(g4_path_inventory_bytes "$G4_MAILSTORE/evolution/provider-live-archive")"

g4_equal database_path \
  "$(notmuch --config="$G4_CONFIG" config get database.path)" "$G4_DB"
g4_equal database_mail_root \
  "$(notmuch --config="$G4_CONFIG" config get database.mail_root)" "$G4_MAILSTORE"
g4_equal synchronize_flags \
  "$(notmuch --config="$G4_CONFIG" config get maildir.synchronize_flags)" false
g4_equal index_decrypt \
  "$(notmuch --config="$G4_CONFIG" config get index.decrypt)" false
G4_TAGS=$(notmuch --config="$G4_CONFIG" config get new.tags |
  LC_ALL=C sort |
  paste -sd' ' -)
g4_equal new_tags_sorted "$G4_TAGS" 'inbox unread'

G4_HEALTH=$(curl -fsS --max-time 10 http://127.0.0.1:8765/healthz)
python3 -c \
  'import json,sys; d=json.load(sys.stdin); assert d["ok"] is True; assert d["read_only"] is True; assert d["mail_mutation"] is False; print("health_ok=true"); print("health_read_only=true"); print("health_mail_mutation=false"); print("health_messages="+str(d["messages"])); print("health_files="+str(d["files"]))' \
  <<<"$G4_HEALTH"

for lock in \
  /mail/AppData/notmuch-browser/index-refresh.lock \
  /mail/AppData/isync/provider-live-loop/lock; do
  if [[ -e "$lock" ]]; then
    printf 'lock_state=%s:present-background-activity\n' "$lock"
  else
    printf 'lock_state=%s:absent\n' "$lock"
  fi
done

printf '%s\n' backup_created=no
printf '%s\n' acknowledgement_marker_rewritten=no
printf '%s\n' notmuch_new_executed_by_gate=no
printf '%s\n' notmuch_config_changed=no
printf '%s\n' service_lifecycle_action_executed=no
printf '%s\n' maildir_mutation_executed=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_04_read_only_enrollment_backup_capacity_preflight_pass
