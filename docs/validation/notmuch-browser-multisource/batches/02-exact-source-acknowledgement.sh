#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 02: revalidate exact static sources and write only their private marker.
G2_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G2_COMMIT=33222aff7f7ed7b779ad51ecf0f0fb8b3dde84b0
G2_BRANCH=atiqte/branch-codex
G2_CONFIG=/home/atiq/.config/notmuch/default/config
G2_HELPER="$G2_REPO/scripts/notmuch_browser_source_enroll.sh"
G2_MARKER=/mail/AppData/notmuch-browser/source-enrollment/current-sources-acknowledged.env
G2_BROWSER_SERVICE=/home/atiq/.runit/service/notmuch-browser
G2_INDEX_SERVICE=/home/atiq/.runit/service/notmuch-browser-index
G2_PROVIDER_CONTROL=/home/atiq/.local/bin/mbsync-provider-live-control
G2_GATE1_BATCH="$G2_REPO/docs/validation/notmuch-browser-multisource/batches/01-read-only-preflight.sh"
G2_GATE1_LOG="$G2_REPO/docs/validation/notmuch-browser-multisource/logs/01-read-only-preflight.log"
G2_GATE1_BATCH_SHA=01a177738f70c4d08b05f1ed5cbea1c4f03fccc77e91938abbeb2ca320237322
G2_GATE1_LOG_SHA=0b3a25a36dfcc6eb1cf5afd6985f58173e43a0de6b9e3f2aa24aa005b4a33a0e

g2_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g2_equal() {
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

g2_sv_pid() {
  local service=$1
  local status
  status=$(sv status "$service")
  sed -n 's/.*(pid \([0-9][0-9]*\)).*/\1/p' <<<"$status"
}

g2_provider_pid() {
  "$G2_PROVIDER_CONTROL" status |
    sed -n 's/^pid=//p' |
    sed -n '1p'
}

g2_marker_value() {
  local key=$1
  sed -n "s/^${key}=//p" "$G2_MARKER" | sed -n '1p'
}

g2_marker_equal() {
  local key=$1
  local expected=$2
  g2_equal "marker[$key]" "$(g2_marker_value "$key")" "$expected"
}

g2_require_line() {
  local text=$1
  local expected=$2
  grep -Fqx "$expected" <<<"$text" ||
    g2_die "source inspection drifted: $expected"
}

printf '%s\n' 'gate=02-exact-source-acknowledgement'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=source_counts_sizes_hashes_and_statuses_only'
printf '%s\n' 'authorized_write=private_acknowledgement_marker_only'

for tool in git sh sed grep stat sha256sum notmuch sv curl python3 awk paste wc id; do
  command -v "$tool" >/dev/null 2>&1 || g2_die "missing required command: $tool"
done

cd "$G2_REPO"
g2_equal repository_commit "$(git rev-parse HEAD)" "$G2_COMMIT"
g2_equal repository_branch "$(git branch --show-current)" "$G2_BRANCH"
g2_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G2_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g2_die "repository is not clean"
printf '%s\n' repository_clean=yes
g2_equal gate_01_batch_sha256 \
  "$(sha256sum "$G2_GATE1_BATCH" | awk '{print $1}')" "$G2_GATE1_BATCH_SHA"
g2_equal gate_01_log_sha256 \
  "$(sha256sum "$G2_GATE1_LOG" | awk '{print $1}')" "$G2_GATE1_LOG_SHA"
g2_equal enrollment_helper_sha256 \
  "$(sha256sum "$G2_HELPER" | awk '{print $1}')" \
  61a96a587c8e25ddef290a118e95a335ca2f47481dec8925e57f49c6342d0fee
sh -n "$G2_HELPER"

[[ ! -e "$G2_MARKER" ]] || g2_die "acknowledgement marker already exists"
for lock in \
  /mail/AppData/notmuch-browser/index-refresh.lock \
  /mail/AppData/isync/provider-live-loop/lock; do
  if [[ -e "$lock" ]]; then
    printf 'pre_ack_lock_state=%s:present-background-activity\n' "$lock"
  else
    printf 'pre_ack_lock_state=%s:absent\n' "$lock"
  fi
done

G2_BROWSER_PID_BEFORE=$(g2_sv_pid "$G2_BROWSER_SERVICE")
G2_INDEX_PID_BEFORE=$(g2_sv_pid "$G2_INDEX_SERVICE")
G2_PROVIDER_PID_BEFORE=$(g2_provider_pid)
[[ "$G2_BROWSER_PID_BEFORE" =~ ^[0-9]+$ ]] || g2_die "browser service is not running"
[[ "$G2_INDEX_PID_BEFORE" =~ ^[0-9]+$ ]] || g2_die "index service is not running"
[[ "$G2_PROVIDER_PID_BEFORE" =~ ^[0-9]+$ ]] || g2_die "provider loop is not running"
printf 'browser_pid_before=%s\n' "$G2_BROWSER_PID_BEFORE"
printf 'index_pid_before=%s\n' "$G2_INDEX_PID_BEFORE"
printf 'provider_pid_before=%s\n' "$G2_PROVIDER_PID_BEFORE"

G2_CONFIG_SHA_BEFORE=$(sha256sum "$G2_CONFIG" | awk '{print $1}')
G2_IGNORE_BEFORE=$(notmuch --config="$G2_CONFIG" config get new.ignore |
  LC_ALL=C sort |
  paste -sd' ' -)
printf 'config_sha256_before=%s\n' "$G2_CONFIG_SHA_BEFORE"
printf 'new_ignore_before=%s\n' "$G2_IGNORE_BEFORE"

printf '%s\n' pre_ack_inspection_begin=yes
G2_PRE_INSPECTION=$("$G2_HELPER" inspect)
printf '%s\n' "$G2_PRE_INSPECTION"
printf '%s\n' pre_ack_inspection_end=yes
g2_require_line "$G2_PRE_INSPECTION" \
  'source=evolution/local-maildir message_paths=48564 bytes=62420909898 symlinks=0 manifest_sha256=e4e78a9bff9bbdca5b5c8ea4ab4703aa34bcb6cb4069e2ef6834fe935619c6d6'
g2_require_line "$G2_PRE_INSPECTION" \
  'source=evolution/betterbird-delta-maildirpp-20260704 message_paths=247 bytes=436874381 symlinks=0 manifest_sha256=ec57b539cc6d577ef7162d88ee448ee7db6e1655b5eb583b00cd11a81985c6bb'
g2_require_line "$G2_PRE_INSPECTION" \
  'source=mbsync/provider-inbox-test message_paths=148 bytes=240550278 symlinks=0 manifest_sha256=d2084a07ea826428d0171a033b5774cd1bf29866ac0f583501fec4a81e400b7a'
g2_require_line "$G2_PRE_INSPECTION" \
  'source=evolution/test-maildir message_paths=4 bytes=1470 symlinks=0 manifest_sha256=8f66b42eb7b9d6f858254492aaaab7ea66ffb38c71e6ec39999787da3e361014'
g2_require_line "$G2_PRE_INSPECTION" \
  'source=evolution/provider-live-archive message_paths=0 bytes=0 symlinks=0 manifest_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
printf '%s\n' pre_ack_exact_source_manifest=pass

"$G2_HELPER" acknowledge-current

[[ -f "$G2_MARKER" && ! -L "$G2_MARKER" ]] ||
  g2_die "acknowledgement marker is missing or unsafe"
g2_equal marker_mode "$(stat -c '%a' "$G2_MARKER")" 600
g2_equal marker_owner "$(stat -c '%U' "$G2_MARKER")" "$(id -un)"
g2_equal marker_lines "$(wc -l < "$G2_MARKER" | tr -d ' ')" 16

g2_marker_equal evolution_local_maildir_message_paths 48564
g2_marker_equal evolution_local_maildir_bytes 62420909898
g2_marker_equal evolution_local_maildir_manifest_sha256 \
  e4e78a9bff9bbdca5b5c8ea4ab4703aa34bcb6cb4069e2ef6834fe935619c6d6
g2_marker_equal evolution_betterbird_delta_maildirpp_20260704_message_paths 247
g2_marker_equal evolution_betterbird_delta_maildirpp_20260704_bytes 436874381
g2_marker_equal evolution_betterbird_delta_maildirpp_20260704_manifest_sha256 \
  ec57b539cc6d577ef7162d88ee448ee7db6e1655b5eb583b00cd11a81985c6bb
g2_marker_equal mbsync_provider_inbox_test_message_paths 148
g2_marker_equal mbsync_provider_inbox_test_bytes 240550278
g2_marker_equal mbsync_provider_inbox_test_manifest_sha256 \
  d2084a07ea826428d0171a033b5774cd1bf29866ac0f583501fec4a81e400b7a
g2_marker_equal evolution_test_maildir_message_paths 4
g2_marker_equal evolution_test_maildir_bytes 1470
g2_marker_equal evolution_test_maildir_manifest_sha256 \
  8f66b42eb7b9d6f858254492aaaab7ea66ffb38c71e6ec39999787da3e361014
g2_marker_equal evolution_provider_live_archive_message_paths 0
g2_marker_equal evolution_provider_live_archive_bytes 0
g2_marker_equal evolution_provider_live_archive_manifest_sha256 \
  e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
G2_ACKNOWLEDGED_AT=$(g2_marker_value acknowledged_at)
[[ -n "$G2_ACKNOWLEDGED_AT" ]] || g2_die "acknowledgement timestamp is missing"
printf 'marker_acknowledged_at=%s\n' "$G2_ACKNOWLEDGED_AT"
printf 'marker_sha256=%s\n' "$(sha256sum "$G2_MARKER" | awk '{print $1}')"

printf '%s\n' post_ack_inspection_begin=yes
"$G2_HELPER" inspect
printf '%s\n' post_ack_inspection_end=yes

g2_equal config_sha256_after \
  "$(sha256sum "$G2_CONFIG" | awk '{print $1}')" "$G2_CONFIG_SHA_BEFORE"
g2_equal new_ignore_after \
  "$(notmuch --config="$G2_CONFIG" config get new.ignore | LC_ALL=C sort | paste -sd' ' -)" \
  "$G2_IGNORE_BEFORE"
g2_equal browser_pid_after "$(g2_sv_pid "$G2_BROWSER_SERVICE")" "$G2_BROWSER_PID_BEFORE"
g2_equal index_pid_after "$(g2_sv_pid "$G2_INDEX_SERVICE")" "$G2_INDEX_PID_BEFORE"
g2_equal provider_pid_after "$(g2_provider_pid)" "$G2_PROVIDER_PID_BEFORE"

G2_HEALTH=$(curl -fsS --max-time 10 http://127.0.0.1:8765/healthz)
python3 -c \
  'import json,sys; d=json.load(sys.stdin); assert d["ok"] is True; assert d["read_only"] is True; assert d["mail_mutation"] is False; print("health_ok=true"); print("health_read_only=true"); print("health_mail_mutation=false"); print("health_messages="+str(d["messages"])); print("health_files="+str(d["files"]))' \
  <<<"$G2_HEALTH"

for lock in \
  /mail/AppData/notmuch-browser/index-refresh.lock \
  /mail/AppData/isync/provider-live-loop/lock; do
  if [[ -e "$lock" ]]; then
    printf 'post_ack_lock_state=%s:present-background-activity\n' "$lock"
  else
    printf 'post_ack_lock_state=%s:absent\n' "$lock"
  fi
done
printf '%s\n' acknowledgement_marker_written=yes
printf '%s\n' notmuch_new_executed_by_gate=no
printf '%s\n' notmuch_config_changed=no
printf '%s\n' service_lifecycle_action_executed=no
printf '%s\n' maildir_mutation_executed=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_02_exact_source_acknowledgement_pass
