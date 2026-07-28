#!/bin/bash
set -Eeuo pipefail

umask 077

# Fresh-VM Recovery Gate 01:
# Verify the clean pushed release-candidate implementation and both canonical
# mail sources, prove XFS reflink support with a disposable metadata-only file,
# create a private recovery set under /mail/Backups, verify every split archive,
# and print only paths, counts, hashes, modes, capacity, and service health.
# No credentials, message headers, Message-IDs, filenames from mail trees,
# notmuch query output, or message content are printed.
R1_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
R1_COMMIT=10473e657012688180f1604dd757db8bf044ab50
R1_BRANCH=atiqte/branch-codex
R1_HELPER="$R1_REPO/scripts/notmuch_browser_recovery_kit.sh"
R1_HELPER_SHA=0992a80a2c3229a93d65d1d39e94bf739f6e3d28e1f459ad5f5caa8c60915a89
R1_TRANSPORT="$R1_REPO/src/maildirpp_transport.py"
R1_TRANSPORT_SHA=7af4d83d25556a39623d06d0d8de321b9569748e6da3cbe2b90d050dce3189e3
R1_HIST_SOURCE=/mail/import-staging/maildirpp-archive-export-20260701-215204
R1_HIST_MANIFEST_SHA=166bd3c1c92fee692dd28ad729e134182187e9304b5b0ee20651aaab7e79b9e7
R1_HIST_INVENTORY_FILE_SHA=97332ffac27c85372d91486ceeb8d49dde2cc036d6b0d889cd73243b1e06067d
R1_HIST_ARCHIVE_SHA=23292983c9ffb3590197a534aeddd03590a2b8d9f913732573fa1637b71045fe
R1_HIST_INVENTORY_SHA=97332ffac27c85372d91486ceeb8d49dde2cc036d6b0d889cd73243b1e06067d
R1_DELTA_SOURCE=/mail/Mailstore/evolution/betterbird-delta-maildirpp-20260704
R1_RECOVERY_ROOT=/mail/Backups/notmuch-browser-recovery-v1
R1_HIST_DEST="$R1_RECOVERY_ROOT/historical"
R1_DELTA_DEST="$R1_RECOVERY_ROOT/betterbird-delta"
R1_PRODUCTION_BINARY=/home/atiq/.local/bin/notmuch-browser
R1_PRODUCTION_SHA=7f4099ed7cc5882928b5f9785689cd3adfa60993af83f0f8a17f325fcb7f1f1d
R1_PROBE=

r1_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

r1_equal() {
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

r1_cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$R1_PROBE" && -d "$R1_PROBE" ]]; then
    unlink "$R1_PROBE/copy" 2>/dev/null || true
    unlink "$R1_PROBE/source" 2>/dev/null || true
    rmdir "$R1_PROBE" 2>/dev/null || true
  fi
  exit "$rc"
}
trap r1_cleanup EXIT

r1_health() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

label = sys.argv[1]
payload = json.loads(sys.argv[2])
if payload.get("ok") is not True:
    raise SystemExit(f"status=blocked\nreason={label} health is not ok")
if payload.get("read_only") is not True:
    raise SystemExit(f"status=blocked\nreason={label} is not read-only")
if payload.get("mail_mutation") is not False:
    raise SystemExit(f"status=blocked\nreason={label} reports mail mutation")
messages = payload.get("messages")
files = payload.get("files")
if not isinstance(messages, int) or messages < 1:
    raise SystemExit(f"status=blocked\nreason={label} message count is invalid")
if not isinstance(files, int) or files < 51946:
    raise SystemExit(f"status=blocked\nreason={label} file count is below baseline")
print(f"{label}_health_ok=true")
print(f"{label}_health_read_only=true")
print(f"{label}_health_mail_mutation=false")
print(f"{label}_health_messages={messages}")
print(f"{label}_health_files={files}")
PY
}

printf '%s\n' 'gate=fresh-vm-recovery-01-create-and-verify-canonical-set'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'authorized_write_scope=/mail/Backups/notmuch-browser-recovery-v1'
printf '%s\n' 'authorized_source_mail_mutation=no'
printf '%s\n' 'authorized_notmuch_config_tag_database_mutation=no'
printf '%s\n' 'authorized_service_lifecycle_action=no'
printf '%s\n' 'privacy_contract=paths_counts_hashes_modes_capacity_and_health_only'
printf '%s\n' 'failure_policy=preserve_partial_recovery_root_for_review'

for tool in git bash python3 sha256sum awk find wc install mv date cp cmp \
  chmod stat df findmnt curl unlink rmdir du dirname mktemp grep tr; do
  command -v "$tool" >/dev/null 2>&1 || r1_die "missing required command: $tool"
done
cp --help 2>&1 | grep -Fq -- '--reflink' ||
  r1_die "cp does not support --reflink"

cd "$R1_REPO"
r1_equal repository_commit "$(git rev-parse HEAD)" "$R1_COMMIT"
r1_equal repository_branch "$(git branch --show-current)" "$R1_BRANCH"
r1_equal upstream_commit "$(git rev-parse '@{upstream}')" "$R1_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  r1_die "repository is not clean"
printf '%s\n' repository_clean_before=yes
r1_equal recovery_helper_sha256 \
  "$(sha256sum "$R1_HELPER" | awk '{print $1}')" "$R1_HELPER_SHA"
r1_equal transport_sha256 \
  "$(sha256sum "$R1_TRANSPORT" | awk '{print $1}')" "$R1_TRANSPORT_SHA"
[[ -x "$R1_HELPER" ]] || r1_die "recovery helper is not executable"
R1_HEALTH_BEFORE=$(curl -fsS --max-time 20 http://127.0.0.1:8765/healthz)
r1_health production_before "$R1_HEALTH_BEFORE"

r1_equal mail_mount_target \
  "$(findmnt -n -o TARGET --target /mail)" /mail
r1_equal mail_mount_fstype \
  "$(findmnt -n -o FSTYPE --target /mail)" xfs
[[ "$(findmnt -n -o OPTIONS --target /mail)" == *rw* ]] ||
  r1_die "/mail is not writable"
r1_equal historical_source_mount \
  "$(findmnt -n -o TARGET --target "$R1_HIST_SOURCE")" /mail
r1_equal delta_source_mount \
  "$(findmnt -n -o TARGET --target "$R1_DELTA_SOURCE")" /mail
r1_equal recovery_parent_mount \
  "$(findmnt -n -o TARGET --target "$(dirname "$R1_RECOVERY_ROOT")")" /mail
[[ -d "$R1_HIST_SOURCE" && ! -L "$R1_HIST_SOURCE" ]] ||
  r1_die "historical source is missing or unsafe"
[[ -d "$R1_DELTA_SOURCE" && ! -L "$R1_DELTA_SOURCE" ]] ||
  r1_die "delta source is missing or unsafe"
[[ ! -e "$R1_RECOVERY_ROOT" ]] ||
  r1_die "recovery destination already exists and requires review"
R1_FREE_BEFORE=$(df -Pk /mail | awk 'NR == 2 {print $4}')
[[ "$R1_FREE_BEFORE" =~ ^[0-9]+$ ]] || r1_die "could not measure free space"
(( R1_FREE_BEFORE >= 94371840 )) ||
  r1_die "less than 90 GiB is free before recovery creation"
printf 'mail_free_kib_before=%s\n' "$R1_FREE_BEFORE"

r1_equal historical_manifest_file_sha256 \
  "$(sha256sum "$R1_HIST_SOURCE/manifest.json" | awk '{print $1}')" \
  "$R1_HIST_MANIFEST_SHA"
r1_equal historical_inventory_file_sha256 \
  "$(sha256sum "$R1_HIST_SOURCE/inventory.jsonl" | awk '{print $1}')" \
  "$R1_HIST_INVENTORY_FILE_SHA"
python3 - "$R1_HIST_SOURCE/manifest.json" \
  "$R1_HIST_ARCHIVE_SHA" "$R1_HIST_INVENTORY_SHA" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    manifest = json.load(handle)
if manifest["archive"]["sha256"] != sys.argv[2]:
    raise SystemExit("status=blocked\nreason=historical archive identity mismatch")
if manifest["inventory"]["sha256"] != sys.argv[3]:
    raise SystemExit("status=blocked\nreason=historical inventory identity mismatch")
print("historical_manifest_archive_identity=pass")
print("historical_manifest_inventory_identity=pass")
PY
python3 "$R1_TRANSPORT" verify-archive \
  --manifest "$R1_HIST_SOURCE/manifest.json"
"$R1_HELPER" inspect-delta "$R1_DELTA_SOURCE"

R1_PROBE=$(mktemp -d /mail/Backups/.notmuch-reflink-probe.XXXXXX)
chmod 700 "$R1_PROBE"
printf '%s\n' notmuch-browser-reflink-probe > "$R1_PROBE/source"
chmod 600 "$R1_PROBE/source"
cp --reflink=always --preserve=mode,timestamps \
  "$R1_PROBE/source" "$R1_PROBE/copy"
cmp -s "$R1_PROBE/source" "$R1_PROBE/copy" ||
  r1_die "XFS reflink probe bytes differ"
printf '%s\n' xfs_reflink_probe=pass
unlink "$R1_PROBE/copy"
unlink "$R1_PROBE/source"
rmdir "$R1_PROBE"
R1_PROBE=

install -d -m 700 "$R1_RECOVERY_ROOT" "$R1_HIST_DEST"
printf '%s\n' recovery_stage=historical_reflink_copy
cp --reflink=always --archive "$R1_HIST_SOURCE/." "$R1_HIST_DEST/"
find "$R1_HIST_DEST" -type d -exec chmod 700 {} +
find "$R1_HIST_DEST" -type f -exec chmod 600 {} +
[[ -z "$(find "$R1_HIST_DEST" -type l -print -quit)" ]] ||
  r1_die "historical recovery package contains a symlink"
r1_equal copied_historical_manifest_sha256 \
  "$(sha256sum "$R1_HIST_DEST/manifest.json" | awk '{print $1}')" \
  "$R1_HIST_MANIFEST_SHA"
r1_equal copied_historical_inventory_sha256 \
  "$(sha256sum "$R1_HIST_DEST/inventory.jsonl" | awk '{print $1}')" \
  "$R1_HIST_INVENTORY_FILE_SHA"

printf '%s\n' recovery_stage=betterbird_delta_pack
"$R1_HELPER" pack-delta "$R1_DELTA_SOURCE" "$R1_DELTA_DEST"
find "$R1_DELTA_DEST" -type d -exec chmod 700 {} +
find "$R1_DELTA_DEST" -type f -exec chmod 600 {} +
[[ -z "$(find "$R1_DELTA_DEST" -type l -print -quit)" ]] ||
  r1_die "delta recovery package contains a symlink"

printf '%s\n' recovery_stage=finalize_and_full_verify
"$R1_HELPER" finalize "$R1_RECOVERY_ROOT"
"$R1_HELPER" verify "$R1_RECOVERY_ROOT"
r1_equal recovery_root_mode "$(stat -c '%a' "$R1_RECOVERY_ROOT")" 700
r1_equal recovery_set_mode \
  "$(stat -c '%a' "$R1_RECOVERY_ROOT/recovery-set.env")" 600
R1_UNSAFE_DIRS=$(find "$R1_RECOVERY_ROOT" -type d ! -perm 700 | wc -l | tr -d ' ')
R1_UNSAFE_FILES=$(find "$R1_RECOVERY_ROOT" -type f ! -perm 600 | wc -l | tr -d ' ')
R1_SYMLINKS=$(find "$R1_RECOVERY_ROOT" -type l | wc -l | tr -d ' ')
r1_equal recovery_unsafe_directory_modes "$R1_UNSAFE_DIRS" 0
r1_equal recovery_unsafe_file_modes "$R1_UNSAFE_FILES" 0
r1_equal recovery_symlinks "$R1_SYMLINKS" 0
printf 'recovery_regular_files=%s\n' \
  "$(find "$R1_RECOVERY_ROOT" -type f | wc -l | tr -d ' ')"
printf 'recovery_apparent_bytes=%s\n' \
  "$(du -sb --apparent-size "$R1_RECOVERY_ROOT" | awk '{print $1}')"
printf 'recovery_set_sha256=%s\n' \
  "$(sha256sum "$R1_RECOVERY_ROOT/recovery-set.env" | awk '{print $1}')"

R1_FREE_AFTER=$(df -Pk /mail | awk 'NR == 2 {print $4}')
[[ "$R1_FREE_AFTER" =~ ^[0-9]+$ ]] || r1_die "could not measure final free space"
(( R1_FREE_AFTER >= 92274688 )) ||
  r1_die "less than 88 GiB remains; reflink/capacity result requires review"
printf 'mail_free_kib_after=%s\n' "$R1_FREE_AFTER"
printf 'mail_free_kib_consumed=%s\n' "$((R1_FREE_BEFORE - R1_FREE_AFTER))"

r1_equal production_binary_sha256 \
  "$(sha256sum "$R1_PRODUCTION_BINARY" | awk '{print $1}')" \
  "$R1_PRODUCTION_SHA"
R1_HEALTH_AFTER=$(curl -fsS --max-time 20 http://127.0.0.1:8765/healthz)
r1_health production_after "$R1_HEALTH_AFTER"
r1_equal repository_commit_after "$(git rev-parse HEAD)" "$R1_COMMIT"
r1_equal upstream_commit_after "$(git rev-parse '@{upstream}')" "$R1_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  r1_die "repository changed during recovery creation"
printf '%s\n' repository_clean_after=yes
printf '%s\n' source_mail_mutation_executed=no
printf '%s\n' notmuch_config_tag_database_mutation_executed=no
printf '%s\n' service_lifecycle_action_executed=no
printf 'recovery_root=%s\n' "$R1_RECOVERY_ROOT"
printf '%s\n' next_action=review_log_then_pin_recovery_set_sha256
printf '%s\n' status=fresh_vm_recovery_gate_01_pass
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
