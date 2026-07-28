#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=${NOTMUCH_RECOVERY_REPO_ROOT:-$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)}
TRANSPORT="$REPO_ROOT/src/maildirpp_transport.py"

RECOVERY_ID=notmuch-browser-recovery-v1
SET_NAME=recovery-set.env
HISTORICAL_DIR=historical
DELTA_DIR=betterbird-delta

EXPECTED_HISTORICAL_ARCHIVE_SHA256=23292983c9ffb3590197a534aeddd03590a2b8d9f913732573fa1637b71045fe
EXPECTED_HISTORICAL_INVENTORY_SHA256=97332ffac27c85372d91486ceeb8d49dde2cc036d6b0d889cd73243b1e06067d
EXPECTED_HISTORICAL_CUR=48720
EXPECTED_HISTORICAL_NEW=0
EXPECTED_HISTORICAL_TMP=0
EXPECTED_HISTORICAL_METADATA=1
EXPECTED_HISTORICAL_BYTES=62430783277

EXPECTED_DELTA_CUR=247
EXPECTED_DELTA_NEW=0
EXPECTED_DELTA_TMP=0
EXPECTED_DELTA_METADATA=1
EXPECTED_DELTA_BYTES=436874381

if [ "${NOTMUCH_RECOVERY_TEST_MODE:-0}" = 1 ]; then
  EXPECTED_HISTORICAL_ARCHIVE_SHA256=${NOTMUCH_RECOVERY_TEST_HISTORICAL_ARCHIVE_SHA256:-$EXPECTED_HISTORICAL_ARCHIVE_SHA256}
  EXPECTED_HISTORICAL_INVENTORY_SHA256=${NOTMUCH_RECOVERY_TEST_HISTORICAL_INVENTORY_SHA256:-$EXPECTED_HISTORICAL_INVENTORY_SHA256}
  EXPECTED_HISTORICAL_CUR=${NOTMUCH_RECOVERY_TEST_HISTORICAL_CUR:-$EXPECTED_HISTORICAL_CUR}
  EXPECTED_HISTORICAL_NEW=${NOTMUCH_RECOVERY_TEST_HISTORICAL_NEW:-$EXPECTED_HISTORICAL_NEW}
  EXPECTED_HISTORICAL_TMP=${NOTMUCH_RECOVERY_TEST_HISTORICAL_TMP:-$EXPECTED_HISTORICAL_TMP}
  EXPECTED_HISTORICAL_METADATA=${NOTMUCH_RECOVERY_TEST_HISTORICAL_METADATA:-$EXPECTED_HISTORICAL_METADATA}
  EXPECTED_HISTORICAL_BYTES=${NOTMUCH_RECOVERY_TEST_HISTORICAL_BYTES:-$EXPECTED_HISTORICAL_BYTES}
  EXPECTED_DELTA_CUR=${NOTMUCH_RECOVERY_TEST_DELTA_CUR:-$EXPECTED_DELTA_CUR}
  EXPECTED_DELTA_NEW=${NOTMUCH_RECOVERY_TEST_DELTA_NEW:-$EXPECTED_DELTA_NEW}
  EXPECTED_DELTA_TMP=${NOTMUCH_RECOVERY_TEST_DELTA_TMP:-$EXPECTED_DELTA_TMP}
  EXPECTED_DELTA_METADATA=${NOTMUCH_RECOVERY_TEST_DELTA_METADATA:-$EXPECTED_DELTA_METADATA}
  EXPECTED_DELTA_BYTES=${NOTMUCH_RECOVERY_TEST_DELTA_BYTES:-$EXPECTED_DELTA_BYTES}
fi

say() {
  printf '%s\n' "$*"
}

die() {
  say "status=blocked"
  say "reason=$*"
  exit 1
}

safe_path() {
  case "$1" in
    ''|*'
'*) die "path must be nonempty and contain no newline" ;;
  esac
}

need_tools() {
  for tool in python3 sha256sum awk find wc install mv date; do
    command -v "$tool" >/dev/null 2>&1 || die "missing command: $tool"
  done
  [ -f "$TRANSPORT" ] || die "missing transport utility: $TRANSPORT"
}

manifest_value() {
  manifest=$1
  key=$2
  python3 - "$manifest" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    value = json.load(handle)
for part in sys.argv[2].split("."):
    value = value[part]
if isinstance(value, (dict, list)):
    raise SystemExit("manifest value is not scalar")
print(value)
PY
}

inspection_value() {
  key=$1
  awk -F= -v wanted="$key" '$1 == wanted { print substr($0, length($1) + 2); exit }'
}

set_value() {
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

assert_equal() {
  label=$1
  actual=$2
  expected=$3
  [ "$actual" = "$expected" ] ||
    die "$label is $actual, expected $expected"
}

inspect_tree() {
  source=$1
  safe_path "$source"
  [ -d "$source" ] || die "missing Maildir++ source: $source"
  python3 "$TRANSPORT" inspect --source "$source"
}

verify_inspection() {
  label=$1
  inspection=$2
  expected_cur=$3
  expected_new=$4
  expected_tmp=$5
  expected_metadata=$6
  expected_bytes=$7

  cur=$(printf '%s\n' "$inspection" | inspection_value cur_files)
  new=$(printf '%s\n' "$inspection" | inspection_value new_files)
  tmp=$(printf '%s\n' "$inspection" | inspection_value tmp_files)
  metadata=$(printf '%s\n' "$inspection" | inspection_value metadata_files)
  bytes=$(printf '%s\n' "$inspection" | inspection_value bytes_regular)
  assert_equal "$label cur count" "$cur" "$expected_cur"
  assert_equal "$label new count" "$new" "$expected_new"
  assert_equal "$label tmp count" "$tmp" "$expected_tmp"
  assert_equal "$label metadata count" "$metadata" "$expected_metadata"
  assert_equal "$label regular bytes" "$bytes" "$expected_bytes"
}

verify_package() {
  label=$1
  package_dir=$2
  expected_archive_sha=$3
  expected_inventory_sha=$4

  safe_path "$package_dir"
  manifest="$package_dir/manifest.json"
  inventory="$package_dir/inventory.jsonl"
  [ -f "$manifest" ] && [ ! -L "$manifest" ] ||
    die "$label manifest is missing or unsafe"
  [ -f "$inventory" ] && [ ! -L "$inventory" ] ||
    die "$label inventory is missing or unsafe"
  assert_equal "$label archive SHA256" \
    "$(manifest_value "$manifest" archive.sha256)" "$expected_archive_sha"
  assert_equal "$label inventory SHA256" \
    "$(manifest_value "$manifest" inventory.sha256)" "$expected_inventory_sha"
  python3 "$TRANSPORT" verify-archive --manifest "$manifest"
}

pack_delta() {
  source=$1
  output=$2
  safe_path "$source"
  safe_path "$output"
  [ -d "$source" ] || die "missing delta source: $source"
  [ ! -e "$output" ] || die "delta output already exists: $output"
  parent=$(dirname "$output")
  [ -d "$parent" ] || die "delta output parent is missing: $parent"

  inspection=$(inspect_tree "$source")
  verify_inspection delta "$inspection" \
    "$EXPECTED_DELTA_CUR" "$EXPECTED_DELTA_NEW" "$EXPECTED_DELTA_TMP" \
    "$EXPECTED_DELTA_METADATA" "$EXPECTED_DELTA_BYTES"

  stamp=$(date +%Y%m%d-%H%M%S)
  incoming="$output.incoming-$stamp-$$"
  [ ! -e "$incoming" ] || die "incoming delta path already exists: $incoming"
  say "status=delta_pack_running"
  say "incoming=$incoming"
  python3 "$TRANSPORT" pack --source "$source" --out "$incoming"
  python3 "$TRANSPORT" verify-archive --manifest "$incoming/manifest.json"
  mv "$incoming" "$output"
  say "delta_archive_sha256=$(manifest_value "$output/manifest.json" archive.sha256)"
  say "delta_inventory_sha256=$(manifest_value "$output/manifest.json" inventory.sha256)"
  say "status=delta_package_complete"
}

finalize_set() {
  root=$1
  safe_path "$root"
  [ -d "$root" ] || die "missing recovery root: $root"
  set_file="$root/$SET_NAME"
  [ ! -e "$set_file" ] || die "recovery set already finalized: $set_file"

  historical="$root/$HISTORICAL_DIR"
  delta="$root/$DELTA_DIR"
  verify_package historical "$historical" \
    "$EXPECTED_HISTORICAL_ARCHIVE_SHA256" \
    "$EXPECTED_HISTORICAL_INVENTORY_SHA256"

  delta_manifest="$delta/manifest.json"
  [ -f "$delta_manifest" ] || die "missing delta manifest: $delta_manifest"
  delta_archive_sha=$(manifest_value "$delta_manifest" archive.sha256)
  delta_inventory_sha=$(manifest_value "$delta_manifest" inventory.sha256)
  verify_package delta "$delta" "$delta_archive_sha" "$delta_inventory_sha"

  # The package manifest binds the packed source statistics. Recheck the exact
  # canonical current delta before publishing the top-level recovery identity.
  assert_equal "delta source regular bytes" \
    "$(manifest_value "$delta_manifest" source.regular_file_bytes)" \
    "$EXPECTED_DELTA_BYTES"
  assert_equal "delta source regular files" \
    "$(manifest_value "$delta_manifest" source.regular_files)" \
    "$((EXPECTED_DELTA_CUR + EXPECTED_DELTA_METADATA))"

  tmp=$(mktemp "$root/.recovery-set.XXXXXX")
  {
    say "schema_version=1"
    say "recovery_id=$RECOVERY_ID"
    say "historical_dir=$HISTORICAL_DIR"
    say "historical_archive_sha256=$EXPECTED_HISTORICAL_ARCHIVE_SHA256"
    say "historical_inventory_sha256=$EXPECTED_HISTORICAL_INVENTORY_SHA256"
    say "historical_cur=$EXPECTED_HISTORICAL_CUR"
    say "historical_bytes=$EXPECTED_HISTORICAL_BYTES"
    say "delta_dir=$DELTA_DIR"
    say "delta_archive_sha256=$delta_archive_sha"
    say "delta_inventory_sha256=$delta_inventory_sha"
    say "delta_cur=$EXPECTED_DELTA_CUR"
    say "delta_bytes=$EXPECTED_DELTA_BYTES"
    say "provider_inbox_source=guarded_mbsync_test_pull"
    say "provider_live_source=guarded_mbsync_production_pull"
    say "provider_live_archive=empty_maildir"
    say "test_maildir_source=deterministic_example_fixture"
    say "test_maildir_messages=4"
  } > "$tmp"
  chmod 600 "$tmp"
  mv "$tmp" "$set_file"
  say "recovery_set_sha256=$(sha256sum "$set_file" | awk '{print $1}')"
  say "status=recovery_set_finalized"
}

verify_set() {
  root=$1
  safe_path "$root"
  set_file="$root/$SET_NAME"
  [ -f "$set_file" ] && [ ! -L "$set_file" ] ||
    die "missing or unsafe recovery set manifest: $set_file"

  assert_equal recovery_id "$(set_value "$set_file" recovery_id)" "$RECOVERY_ID"
  assert_equal historical_dir "$(set_value "$set_file" historical_dir)" "$HISTORICAL_DIR"
  assert_equal delta_dir "$(set_value "$set_file" delta_dir)" "$DELTA_DIR"
  assert_equal historical_archive_sha256 \
    "$(set_value "$set_file" historical_archive_sha256)" \
    "$EXPECTED_HISTORICAL_ARCHIVE_SHA256"
  assert_equal historical_inventory_sha256 \
    "$(set_value "$set_file" historical_inventory_sha256)" \
    "$EXPECTED_HISTORICAL_INVENTORY_SHA256"
  assert_equal historical_cur "$(set_value "$set_file" historical_cur)" \
    "$EXPECTED_HISTORICAL_CUR"
  assert_equal historical_bytes "$(set_value "$set_file" historical_bytes)" \
    "$EXPECTED_HISTORICAL_BYTES"
  assert_equal delta_cur "$(set_value "$set_file" delta_cur)" "$EXPECTED_DELTA_CUR"
  assert_equal delta_bytes "$(set_value "$set_file" delta_bytes)" "$EXPECTED_DELTA_BYTES"
  assert_equal test_maildir_messages \
    "$(set_value "$set_file" test_maildir_messages)" 4

  historical_archive_sha=$(set_value "$set_file" historical_archive_sha256)
  historical_inventory_sha=$(set_value "$set_file" historical_inventory_sha256)
  delta_archive_sha=$(set_value "$set_file" delta_archive_sha256)
  delta_inventory_sha=$(set_value "$set_file" delta_inventory_sha256)
  verify_package historical "$root/$HISTORICAL_DIR" \
    "$historical_archive_sha" "$historical_inventory_sha"
  verify_package delta "$root/$DELTA_DIR" \
    "$delta_archive_sha" "$delta_inventory_sha"
  delta_manifest="$root/$DELTA_DIR/manifest.json"
  assert_equal "delta source regular bytes" \
    "$(manifest_value "$delta_manifest" source.regular_file_bytes)" \
    "$EXPECTED_DELTA_BYTES"
  assert_equal "delta source regular files" \
    "$(manifest_value "$delta_manifest" source.regular_files)" \
    "$((EXPECTED_DELTA_CUR + EXPECTED_DELTA_METADATA))"
  say "recovery_set_sha256=$(sha256sum "$set_file" | awk '{print $1}')"
  say "historical_archive=verified"
  say "betterbird_delta=verified"
  say "status=recovery_set_verified"
}

usage() {
  cat <<'EOF'
Usage: scripts/notmuch_browser_recovery_kit.sh COMMAND [ARGS]

Commands:
  inspect-delta SOURCE
      Read and verify only the canonical 247-message delta source.
  pack-delta SOURCE OUTPUT
      Pack the canonical delta into a new, versioned private package.
  finalize ROOT
      Verify ROOT/historical and ROOT/betterbird-delta, then atomically write
      the mode-600 recovery-set.env manifest. ROOT must not already be finalized.
  verify ROOT
      Reverify both split archives and every pinned recovery-set identity.

The recovery set contains private mail and must stay outside Git. This helper
never reads or stores credentials, message bodies, headers, or filenames in its
top-level manifest.
EOF
}

need_tools
command_name=${1:-help}
case "$command_name" in
  inspect-delta)
    [ "$#" -eq 2 ] || die "usage: inspect-delta SOURCE"
    inspection=$(inspect_tree "$2")
    verify_inspection delta "$inspection" \
      "$EXPECTED_DELTA_CUR" "$EXPECTED_DELTA_NEW" "$EXPECTED_DELTA_TMP" \
      "$EXPECTED_DELTA_METADATA" "$EXPECTED_DELTA_BYTES"
    printf '%s\n' "$inspection"
    say "status=delta_source_verified"
    ;;
  pack-delta)
    [ "$#" -eq 3 ] || die "usage: pack-delta SOURCE OUTPUT"
    pack_delta "$2" "$3"
    ;;
  finalize)
    [ "$#" -eq 2 ] || die "usage: finalize ROOT"
    finalize_set "$2"
    ;;
  verify)
    [ "$#" -eq 2 ] || die "usage: verify ROOT"
    verify_set "$2"
    ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
