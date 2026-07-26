#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 03: corrected read-only acknowledgement and service-identity audit.
G3_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G3_COMMIT=6a57e65886df1614d1c572a5f2e77bbd7aca3bbc
G3_BRANCH=atiqte/branch-codex
G3_CONFIG=/home/atiq/.config/notmuch/default/config
G3_HELPER="$G3_REPO/scripts/notmuch_browser_source_enroll.sh"
G3_MARKER=/mail/AppData/notmuch-browser/source-enrollment/current-sources-acknowledged.env
G3_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G3_BROWSER=/home/atiq/.local/bin/notmuch-browser
G3_BROWSER_SERVICE=/home/atiq/.runit/service/notmuch-browser
G3_INDEX_SERVICE=/home/atiq/.runit/service/notmuch-browser-index
G3_PROVIDER_CONTROL=/home/atiq/.local/bin/mbsync-provider-live-control
G3_GATE2_BATCH="$G3_REPO/docs/validation/notmuch-browser-multisource/batches/02-exact-source-acknowledgement.sh"
G3_GATE2_LOG="$G3_REPO/docs/validation/notmuch-browser-multisource/logs/02-exact-source-acknowledgement.log"
G3_GATE2_BATCH_SHA=c1eea6787038a163e0a139e72ccaa7c3c4c6c3ad76f9abe35fc5c05e1920f59f
G3_GATE2_LOG_SHA=99e549b446e9d6c28ac1de6f2cea665251e01646326f3367e00803bd19841bc6

g3_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g3_equal() {
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

g3_service_status() {
  sv status "$1"
}

g3_primary_pid_from_status() {
  local status=$1
  local primary=${status%%;*}
  if [[ "$primary" =~ \(pid[[:space:]]([0-9]+)\) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  return 1
}

g3_log_pid_from_status() {
  local status=$1
  local log_clause=${status#*; run: log:}
  if [[ "$log_clause" =~ \(pid[[:space:]]([0-9]+)\) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return
  fi
  return 1
}

g3_assert_runsv_parent() {
  local label=$1
  local pid=$2
  local parent
  parent=$(awk '/^PPid:/ { print $2 }' "/proc/$pid/status")
  [[ "$parent" =~ ^[0-9]+$ ]] || g3_die "$label parent is invalid"
  g3_equal "${label}_parent_comm" "$(cat "/proc/$parent/comm")" runsv
  printf '%s_parent_pid=%s\n' "$label" "$parent"
}

g3_require_line() {
  local text=$1
  local expected=$2
  grep -Fqx "$expected" <<<"$text" ||
    g3_die "source inspection drifted: $expected"
}

printf '%s\n' 'gate=03-corrected-acknowledgement-identity-audit'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_process_identity_and_statuses_only'
printf '%s\n' 'authorized_write=none'

for tool in git bash sh sed grep stat sha256sum notmuch sv curl python3 awk paste wc id readlink ss; do
  command -v "$tool" >/dev/null 2>&1 || g3_die "missing required command: $tool"
done

cd "$G3_REPO"
g3_equal repository_commit "$(git rev-parse HEAD)" "$G3_COMMIT"
g3_equal repository_branch "$(git branch --show-current)" "$G3_BRANCH"
g3_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G3_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g3_die "repository is not clean"
printf '%s\n' repository_clean=yes
g3_equal gate_02_batch_sha256 \
  "$(sha256sum "$G3_GATE2_BATCH" | awk '{print $1}')" "$G3_GATE2_BATCH_SHA"
g3_equal gate_02_log_sha256 \
  "$(sha256sum "$G3_GATE2_LOG" | awk '{print $1}')" "$G3_GATE2_LOG_SHA"
g3_equal enrollment_helper_sha256 \
  "$(sha256sum "$G3_HELPER" | awk '{print $1}')" \
  61a96a587c8e25ddef290a118e95a335ca2f47481dec8925e57f49c6342d0fee
sh -n "$G3_HELPER"

[[ -f "$G3_MARKER" && ! -L "$G3_MARKER" ]] ||
  g3_die "acknowledgement marker is missing or unsafe"
g3_equal marker_sha256 "$(sha256sum "$G3_MARKER" | awk '{print $1}')" "$G3_MARKER_SHA"
g3_equal marker_mode "$(stat -c '%a' "$G3_MARKER")" 600
g3_equal marker_owner "$(stat -c '%U' "$G3_MARKER")" "$(id -un)"
g3_equal marker_lines "$(wc -l < "$G3_MARKER" | tr -d ' ')" 16

G3_INSPECTION=$("$G3_HELPER" inspect)
printf '%s\n' source_inspection_begin=yes
printf '%s\n' "$G3_INSPECTION"
printf '%s\n' source_inspection_end=yes
g3_require_line "$G3_INSPECTION" \
  'source=evolution/local-maildir message_paths=48564 bytes=62420909898 symlinks=0 manifest_sha256=e4e78a9bff9bbdca5b5c8ea4ab4703aa34bcb6cb4069e2ef6834fe935619c6d6'
g3_require_line "$G3_INSPECTION" \
  'source=evolution/betterbird-delta-maildirpp-20260704 message_paths=247 bytes=436874381 symlinks=0 manifest_sha256=ec57b539cc6d577ef7162d88ee448ee7db6e1655b5eb583b00cd11a81985c6bb'
g3_require_line "$G3_INSPECTION" \
  'source=mbsync/provider-inbox-test message_paths=148 bytes=240550278 symlinks=0 manifest_sha256=d2084a07ea826428d0171a033b5774cd1bf29866ac0f583501fec4a81e400b7a'
g3_require_line "$G3_INSPECTION" \
  'source=evolution/test-maildir message_paths=4 bytes=1470 symlinks=0 manifest_sha256=8f66b42eb7b9d6f858254492aaaab7ea66ffb38c71e6ec39999787da3e361014'
g3_require_line "$G3_INSPECTION" \
  'source=evolution/provider-live-archive message_paths=0 bytes=0 symlinks=0 manifest_sha256=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
printf '%s\n' marker_source_manifest_parity=pass

g3_equal config_sha256 \
  "$(sha256sum "$G3_CONFIG" | awk '{print $1}')" \
  9fc4a9bdaf9c55c8036f8c27842a336a2198d5a6df086b2d2f9ba3d5479fabd7
G3_IGNORE=$(notmuch --config="$G3_CONFIG" config get new.ignore |
  LC_ALL=C sort |
  paste -sd' ' -)
g3_equal current_new_ignore_sorted "$G3_IGNORE" \
  'betterbird-post-main-archive-maildirpp-20260704-205827 local-maildir provider-inbox-test test-maildir'

G3_BROWSER_STATUS=$(g3_service_status "$G3_BROWSER_SERVICE")
G3_INDEX_STATUS=$(g3_service_status "$G3_INDEX_SERVICE")
printf 'browser_service_status=%s\n' "$G3_BROWSER_STATUS"
printf 'index_service_status=%s\n' "$G3_INDEX_STATUS"
G3_BROWSER_PID=$(g3_primary_pid_from_status "$G3_BROWSER_STATUS") ||
  g3_die "cannot parse browser service PID"
G3_BROWSER_LOG_PID=$(g3_log_pid_from_status "$G3_BROWSER_STATUS") ||
  g3_die "cannot parse browser log PID"
G3_INDEX_PID=$(g3_primary_pid_from_status "$G3_INDEX_STATUS") ||
  g3_die "cannot parse index service PID"
G3_INDEX_LOG_PID=$(g3_log_pid_from_status "$G3_INDEX_STATUS") ||
  g3_die "cannot parse index log PID"
printf 'browser_service_pid=%s\n' "$G3_BROWSER_PID"
printf 'browser_log_pid=%s\n' "$G3_BROWSER_LOG_PID"
printf 'index_service_pid=%s\n' "$G3_INDEX_PID"
printf 'index_log_pid=%s\n' "$G3_INDEX_LOG_PID"
[[ "$G3_BROWSER_PID" != "$G3_BROWSER_LOG_PID" ]] ||
  g3_die "browser service and log PIDs are not distinct"
[[ "$G3_INDEX_PID" != "$G3_INDEX_LOG_PID" ]] ||
  g3_die "index service and log PIDs are not distinct"
g3_equal browser_executable "$(readlink -f "/proc/$G3_BROWSER_PID/exe")" "$G3_BROWSER"
g3_equal browser_binary_sha256 \
  "$(sha256sum "$G3_BROWSER" | awk '{print $1}')" \
  c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9
G3_INDEX_CMD=$(tr '\0' ' ' < "/proc/$G3_INDEX_PID/cmdline")
[[ "$G3_INDEX_CMD" == *notmuch-browser-index-control*" loop"* ]] ||
  g3_die "index service command line is unexpected"
printf '%s\n' index_service_command=expected-control-loop
g3_assert_runsv_parent browser "$G3_BROWSER_PID"
g3_assert_runsv_parent index "$G3_INDEX_PID"

G3_PROVIDER_PID=$("$G3_PROVIDER_CONTROL" status |
  sed -n 's/^pid=//p' |
  sed -n '1p')
[[ "$G3_PROVIDER_PID" =~ ^[0-9]+$ && -d "/proc/$G3_PROVIDER_PID" ]] ||
  g3_die "provider loop is not running"
printf 'provider_loop_pid=%s\n' "$G3_PROVIDER_PID"

G3_LISTENERS=$(ss -H -ltn 'sport = :8765' | awk '{print $4}')
g3_equal browser_listener "$G3_LISTENERS" '127.0.0.1:8765'
[[ -z "$(ss -H -ltn 'sport = :8876')" ]] || g3_die "candidate port 8876 is occupied"
printf '%s\n' candidate_port_8876=free
G3_HEALTH=$(curl -fsS --max-time 10 http://127.0.0.1:8765/healthz)
python3 -c \
  'import json,sys; d=json.load(sys.stdin); assert d["ok"] is True; assert d["read_only"] is True; assert d["mail_mutation"] is False; assert d["messages"] >= 1659; assert d["files"] >= 2872; print("health_ok=true"); print("health_read_only=true"); print("health_mail_mutation=false"); print("health_messages="+str(d["messages"])); print("health_files="+str(d["files"]))' \
  <<<"$G3_HEALTH"

for lock in \
  /mail/AppData/notmuch-browser/index-refresh.lock \
  /mail/AppData/isync/provider-live-loop/lock; do
  if [[ -e "$lock" ]]; then
    printf 'lock_state=%s:present-background-activity\n' "$lock"
  else
    printf 'lock_state=%s:absent\n' "$lock"
  fi
done

printf '%s\n' acknowledgement_marker_rewritten=no
printf '%s\n' notmuch_new_executed_by_gate=no
printf '%s\n' notmuch_config_changed=no
printf '%s\n' service_lifecycle_action_executed=no
printf '%s\n' maildir_mutation_executed=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_03_corrected_acknowledgement_identity_audit_pass
