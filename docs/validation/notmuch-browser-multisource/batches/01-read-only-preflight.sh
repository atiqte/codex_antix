#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 01: privacy-limited, read-only production and source preflight.
G1_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G1_COMMIT=7935502c1e618aa6480415c14b15d2329a4647b0
G1_BRANCH=atiqte/branch-codex
G1_MAIL_ROOT=/mail
G1_MAILSTORE=/mail/Mailstore
G1_CONFIG=/home/atiq/.config/notmuch/default/config
G1_DB=/mail/SearchIndex/notmuch/default
G1_BROWSER=/home/atiq/.local/bin/notmuch-browser
G1_BROWSER_CONTROL=/home/atiq/.local/bin/notmuch-browser-control
G1_INDEX_CONTROL=/home/atiq/.local/bin/notmuch-browser-index-control
G1_MBSYNC_CONTROL=/home/atiq/.local/bin/mbsync-provider-live-control
G1_RUNIT_HELPER=/home/atiq/.local/bin/notmuch-browser-runit-setup
G1_ENROLL_HELPER="$G1_REPO/scripts/notmuch_browser_source_enroll.sh"
G1_UNAVAILABLE=betterbird-post-main-archive-maildirpp-20260704-205827
G1_MIN_FREE_KIB=83886080

g1_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g1_equal() {
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

g1_count_paths() {
  local relative=$1
  find "$G1_MAILSTORE/$relative" -type f \
    \( -path '*/cur/*' -o -path '*/new/*' \) -print |
    wc -l |
    tr -d ' '
}

g1_count_symlinks() {
  find "$1" -type l -print | wc -l | tr -d ' '
}

g1_indexed_files() {
  local relative=$1
  notmuch --config="$G1_CONFIG" count --output=files "path:$relative/**"
}

printf '%s\n' 'gate=01-read-only-multisource-preflight'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_statuses_only'
printf '%s\n' 'mail_or_index_mutation_authorized=no'

for tool in git bash sh python3 find findmnt df sha256sum notmuch curl ss; do
  command -v "$tool" >/dev/null 2>&1 || g1_die "missing required command: $tool"
done

cd "$G1_REPO"
g1_equal repository_commit "$(git rev-parse HEAD)" "$G1_COMMIT"
g1_equal repository_branch "$(git branch --show-current)" "$G1_BRANCH"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g1_die "repository is not clean"
g1_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G1_COMMIT"
printf '%s\n' repository_clean=yes

for script in \
  scripts/notmuch_browser_source_enroll.sh \
  scripts/notmuch_browser_operator_run.sh \
  scripts/notmuch_browser_operator_record.sh; do
  [[ -f "$script" && ! -L "$script" ]] || g1_die "unsafe repository script: $script"
  printf 'script_sha256=%s:%s\n' "$script" "$(sha256sum "$script" | awk '{print $1}')"
done
sh -n scripts/notmuch_browser_source_enroll.sh
bash -n scripts/notmuch_browser_operator_run.sh scripts/notmuch_browser_operator_record.sh
printf '%s\n' repository_script_syntax=pass

g1_equal mail_fstype "$(findmnt -n -o FSTYPE --target "$G1_MAIL_ROOT")" xfs
G1_FREE_KIB=$(df -Pk "$G1_MAIL_ROOT" | awk 'NR == 2 { print $4 }')
[[ "$G1_FREE_KIB" =~ ^[0-9]+$ ]] || g1_die "cannot read /mail free space"
(( G1_FREE_KIB >= G1_MIN_FREE_KIB )) ||
  g1_die "less than 80 GiB is free on /mail"
printf 'mail_free_kib=%s\n' "$G1_FREE_KIB"

[[ -f "$G1_CONFIG" && ! -L "$G1_CONFIG" ]] || g1_die "unsafe notmuch config"
g1_equal database_path \
  "$(notmuch --config="$G1_CONFIG" config get database.path)" "$G1_DB"
g1_equal database_mail_root \
  "$(notmuch --config="$G1_CONFIG" config get database.mail_root)" "$G1_MAILSTORE"
g1_equal synchronize_flags \
  "$(notmuch --config="$G1_CONFIG" config get maildir.synchronize_flags)" false
g1_equal index_decrypt \
  "$(notmuch --config="$G1_CONFIG" config get index.decrypt)" false
G1_TAGS=$(notmuch --config="$G1_CONFIG" config get new.tags | LC_ALL=C sort | paste -sd' ' -)
g1_equal new_tags_sorted "$G1_TAGS" 'inbox unread'
G1_IGNORE=$(notmuch --config="$G1_CONFIG" config get new.ignore | LC_ALL=C sort | paste -sd' ' -)
G1_EXPECTED_IGNORE=$(printf '%s\n' \
  "$G1_UNAVAILABLE" local-maildir provider-inbox-test test-maildir |
  LC_ALL=C sort |
  paste -sd' ' -)
g1_equal current_new_ignore_sorted "$G1_IGNORE" "$G1_EXPECTED_IGNORE"

declare -A G1_EXPECTED_COUNTS=(
  [evolution/local-maildir]=48564
  [evolution/betterbird-delta-maildirpp-20260704]=247
  [evolution/provider-live-archive]=0
  [evolution/test-maildir]=4
  [mbsync/provider-inbox-test]=148
)
G1_SOURCES=(
  evolution/local-maildir
  evolution/betterbird-delta-maildirpp-20260704
  evolution/provider-live-archive
  evolution/test-maildir
  mbsync/provider-inbox-test
)
for relative in "${G1_SOURCES[@]}"; do
  source_path="$G1_MAILSTORE/$relative"
  [[ -d "$source_path" && ! -L "$source_path" ]] ||
    g1_die "approved source is missing or unsafe: $relative"
  g1_equal "source_message_paths[$relative]" \
    "$(g1_count_paths "$relative")" "${G1_EXPECTED_COUNTS[$relative]}"
  g1_equal "source_symlinks[$relative]" "$(g1_count_symlinks "$source_path")" 0
done
[[ ! -e "$G1_MAILSTORE/evolution/$G1_UNAVAILABLE" ]] ||
  g1_die "the unavailable legacy archive unexpectedly exists"
printf '%s\n' unavailable_legacy_archive=absent

G1_STATIC_TMP=$(find \
  "$G1_MAILSTORE/evolution/local-maildir" \
  "$G1_MAILSTORE/evolution/betterbird-delta-maildirpp-20260704" \
  "$G1_MAILSTORE/evolution/provider-live-archive" \
  "$G1_MAILSTORE/evolution/test-maildir" \
  "$G1_MAILSTORE/mbsync/provider-inbox-test" \
  -type f -path '*/tmp/*' -print | wc -l | tr -d ' ')
g1_equal approved_static_tmp_files "$G1_STATIC_TMP" 0
printf 'provider_live_message_paths=%s\n' "$(g1_count_paths mbsync/provider-live)"
printf 'provider_live_tmp_files=%s\n' \
  "$(find "$G1_MAILSTORE/mbsync/provider-live" -type f -path '*/tmp/*' -print | wc -l | tr -d ' ')"

printf '%s\n' source_inspection_begin=yes
"$G1_ENROLL_HELPER" inspect
printf '%s\n' source_inspection_end=yes

G1_TOTAL_MESSAGES=$(notmuch --config="$G1_CONFIG" count '*')
G1_TOTAL_FILES=$(notmuch --config="$G1_CONFIG" count --output=files '*')
[[ "$G1_TOTAL_MESSAGES" =~ ^[0-9]+$ && "$G1_TOTAL_FILES" =~ ^[0-9]+$ ]] ||
  g1_die "invalid notmuch counts"
(( G1_TOTAL_MESSAGES >= 1659 && G1_TOTAL_FILES >= 2872 )) ||
  g1_die "notmuch counts regressed below the reviewed baseline"
printf 'notmuch_messages=%s\n' "$G1_TOTAL_MESSAGES"
printf 'notmuch_files=%s\n' "$G1_TOTAL_FILES"
g1_equal indexed_local_maildir_files "$(g1_indexed_files evolution/local-maildir)" 0
g1_equal indexed_provider_inbox_test_files "$(g1_indexed_files mbsync/provider-inbox-test)" 0
g1_equal indexed_test_maildir_files "$(g1_indexed_files evolution/test-maildir)" 0
printf 'indexed_betterbird_delta_files=%s\n' \
  "$(g1_indexed_files evolution/betterbird-delta-maildirpp-20260704)"
printf 'indexed_provider_archive_files=%s\n' \
  "$(g1_indexed_files evolution/provider-live-archive)"
printf 'indexed_provider_live_files=%s\n' "$(g1_indexed_files mbsync/provider-live)"

for artifact in \
  "$G1_BROWSER" \
  "$G1_BROWSER_CONTROL" \
  "$G1_INDEX_CONTROL" \
  "$G1_MBSYNC_CONTROL" \
  "$G1_RUNIT_HELPER"; do
  [[ -f "$artifact" && ! -L "$artifact" ]] || g1_die "missing or unsafe artifact: $artifact"
  printf 'installed_sha256=%s:%s\n' "$artifact" "$(sha256sum "$artifact" | awk '{print $1}')"
done
"$G1_BROWSER_CONTROL" status
"$G1_INDEX_CONTROL" status
"$G1_MBSYNC_CONTROL" status
"$G1_RUNIT_HELPER" validate

G1_LISTENERS=$(ss -H -ltn 'sport = :8765' | awk '{print $4}')
g1_equal browser_listener "$G1_LISTENERS" '127.0.0.1:8765'
[[ -z "$(ss -H -ltn 'sport = :8876')" ]] || g1_die "candidate port 8876 is occupied"
printf '%s\n' candidate_port_8876=free

G1_HEALTH=$(curl -fsS --max-time 10 http://127.0.0.1:8765/healthz)
python3 -c \
  'import json,sys; d=json.load(sys.stdin); assert d["ok"] is True; assert d["read_only"] is True; assert d["mail_mutation"] is False; print("health_ok=true"); print("health_read_only=true"); print("health_mail_mutation=false"); print("health_messages="+str(d["messages"])); print("health_files="+str(d["files"]))' \
  <<<"$G1_HEALTH"

for lock in \
  /mail/AppData/notmuch-browser/index-refresh.lock \
  /mail/AppData/isync/provider-live-loop/lock; do
  if [[ -e "$lock" ]]; then
    printf 'lock_state=%s:present\n' "$lock"
  else
    printf 'lock_state=%s:absent\n' "$lock"
  fi
done

printf '%s\n' source_acknowledgement_executed=no
printf '%s\n' notmuch_new_executed=no
printf '%s\n' service_lifecycle_action_executed=no
printf '%s\n' mail_or_index_mutation_executed=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_01_read_only_preflight_pass
