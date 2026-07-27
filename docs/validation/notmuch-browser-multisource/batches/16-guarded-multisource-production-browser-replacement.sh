#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 16: bind the exact cross-platform-accepted Gate 15 candidate, create and
# verify a complete production rollback backup, atomically replace only the
# browser binary under the existing per-user runit supervisor, validate the
# full production surface on localhost:8765, and retain Gate 15 on 8876 until
# production GUI review. Real addresses and Message-IDs stay private.
G13_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G13_COMMIT=1d331057a245e93c04efdd18c496d59ee8c8bcea
G13_BRANCH=atiqte/branch-codex
G13_CONFIG=/home/atiq/.config/notmuch/default/config
G13_STATE_ROOT=/mail/AppData/notmuch-browser
G13_GATE15_BATCH="$G13_REPO/docs/validation/notmuch-browser-multisource/batches/15-strong-address-copy-feedback-candidate-clean-build-and-isolated-validation.sh"
G13_GATE15_LOG="$G13_REPO/docs/validation/notmuch-browser-multisource/logs/15-strong-address-copy-feedback-candidate-clean-build-and-isolated-validation.log"
G13_GATE15_RECORD="$G13_REPO/docs/validation/notmuch-browser-multisource/records/15-strong-address-copy-feedback-candidate-clean-build-and-isolated-validation.env"
G13_GATE15_POINTER="$G13_STATE_ROOT/multisource-strong-copy-feedback-candidate-current.env"
G13_GATE15_BATCH_SHA=84fa9b905528bd45b21263fda69cd253acc69738ad5ab0cd42c183f1a7dd4ff8
G13_GATE15_LOG_SHA=b89e9d8309b7f2521ecd3d8612d922a80d9f5859b1c5a2dfc36f593a0118c25f
G13_GATE15_RECORD_SHA=9de342058934ae629564c14beea0c13a76b49d5448e2f1d6dc1aa4b693579d8b
G13_GATE15_POINTER_SHA=6ab743eaaf325b3542dd8d7112b0418c2fcf5c18adf6c47d4c955f9758b0d45a
G13_GATE15_COMMIT=71251c4e6809d443b2e312dfd25edc06ad8c98da
G13_CSS="$G13_REPO/internal/notmuchbrowser/static/app.css"
G13_CSS_SHA=4600ac8b13e72d758d947f8f8352c15d3883222414483d4765e2e2a6536f3619
G13_CSS_BYTES=26329
G13_JS="$G13_REPO/internal/notmuchbrowser/static/app.js"
G13_JS_SHA=792d1141785da910d35fd5f30a998c5cb2d22a5472fe90bf994242729a691e6a
G13_JS_BYTES=7464
G13_PRODUCTION_BINARY=/home/atiq/.local/bin/notmuch-browser
G13_OLD_PRODUCTION_SHA=c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9
G13_OLD_PRODUCTION_BYTES=8093961
G13_CANDIDATE_SHA=7f4099ed7cc5882928b5f9785689cd3adfa60993af83f0f8a17f325fcb7f1f1d
G13_CANDIDATE_BYTES=8192265
G13_BROWSER_CONTROL=/home/atiq/.local/bin/notmuch-browser-control
G13_INDEX_CONTROL=/home/atiq/.local/bin/notmuch-browser-index-control
G13_RUNIT_SETUP=/home/atiq/.local/bin/notmuch-browser-runit-setup
G13_BROWSER_CONTROL_SHA=4b8231a2c886dfb1247d4dfa6b3de043e67d230e4fad1bc202b7452936ca04a8
G13_INDEX_CONTROL_SHA=1ddf93c9c5f9943bcc9b4f744f3e835e6c12f0df83a8a467ac061d2b38f6b007
G13_RUNIT_SETUP_SHA=598762b0f98147460cff3e937b69a47b7aa531e9e4e80807c4f75e540fdc0c77
G13_BROWSER_SERVICE=/home/atiq/.runit/service/notmuch-browser
G13_INDEX_SERVICE=/home/atiq/.runit/service/notmuch-browser-index
G13_BROWSER_DEF=/home/atiq/.runit/usersv/notmuch-browser
G13_INDEX_DEF=/home/atiq/.runit/usersv/notmuch-browser-index
G13_ICEWM_STARTUP=/home/atiq/.icewm/startup
G13_ICEWM_STARTUP_SHA=831fe2d74d91252f41986e170603474370c39f0a00dd54f6e5f095db2970a284
G13_BACKUP_ROOT=/mail/Backups/notmuch-browser
G13_ROLLBACK_POINTER="$G13_STATE_ROOT/multisource-production-rollback-current.env"
G13_PRODUCTION_POINTER="$G13_STATE_ROOT/multisource-production-current.env"
G13_ROLLOUT_ROOT="$G13_STATE_ROOT/multisource-production-rollout"
G13_DOWNLOAD_TMP="$G13_STATE_ROOT/download-tmp"
G13_CONFIG_SHA=50adc22cf114991e6b021fa0eefb91f10d636f34117c4c14c169bb09856446a7
G13_MARKER=/mail/AppData/notmuch-browser/source-enrollment/current-sources-acknowledged.env
G13_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G13_INSTALL_STARTED=no
G13_INSTALL_COMMITTED=no
G13_INSTALL_TEMP=
G13_BACKUP=
G13_ROLLBACK_LOG=

g13_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g13_equal() {
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

g13_pointer_value() {
  local pointer=$1
  local key=$2
  sed -n "s/^${key}=//p" "$pointer" | sed -n '1p'
}

g13_candidate_matches() {
  [[ -n "${G13_GATE15_PID:-}" && -d "/proc/$G13_GATE15_PID" ]] || return 1
  [[ "$(readlink -f "/proc/$G13_GATE15_PID/exe" 2>/dev/null || true)" == "$G13_GATE15_BINARY" ]] ||
    return 1
  [[ "$(awk '{print $22}' "/proc/$G13_GATE15_PID/stat" 2>/dev/null || true)" == "$G13_GATE15_START_TICKS" ]]
}

g13_cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$G13_INSTALL_TEMP" && -e "$G13_INSTALL_TEMP" ]]; then
    rm -f -- "$G13_INSTALL_TEMP"
  fi
  if [[ "$rc" -ne 0 && "$G13_INSTALL_STARTED" == yes &&
        "$G13_INSTALL_COMMITTED" != yes ]]; then
    set +e
    printf '%s\n' automatic_production_rollback=begin
    if [[ -x "$G13_BACKUP/rollback-browser.sh" ]]; then
      "$G13_BACKUP/rollback-browser.sh" > "$G13_ROLLBACK_LOG" 2>&1
      G13_ROLLBACK_EXIT=$?
    else
      G13_ROLLBACK_EXIT=127
    fi
    printf 'automatic_production_rollback_exit=%s\n' "$G13_ROLLBACK_EXIT"
    printf 'automatic_production_rollback_log=%s\n' "$G13_ROLLBACK_LOG"
    if [[ -f "$G13_ROLLBACK_LOG" ]]; then
      printf 'automatic_production_rollback_log_bytes=%s\n' \
        "$(wc -c < "$G13_ROLLBACK_LOG" | tr -d ' ')"
      printf 'automatic_production_rollback_log_sha256=%s\n' \
        "$(sha256sum "$G13_ROLLBACK_LOG" | awk '{print $1}')"
    fi
    printf 'production_binary_after_rollback_sha256=%s\n' \
      "$(sha256sum "$G13_PRODUCTION_BINARY" 2>/dev/null | awk '{print $1}')"
    if [[ -e "$G13_PRODUCTION_POINTER" ]]; then
      G13_FAILED_PRODUCTION_POINTER="$G13_PRODUCTION_POINTER.failed-$(date +%Y%m%d-%H%M%S)"
      mv "$G13_PRODUCTION_POINTER" "$G13_FAILED_PRODUCTION_POINTER"
      printf 'failed_production_pointer_archived=%s\n' "$G13_FAILED_PRODUCTION_POINTER"
    fi
    printf 'gate_15_candidate_alive_after_failure=%s\n' \
      "$(g13_candidate_matches && printf yes || printf no)"
  fi
  exit "$rc"
}
trap g13_cleanup EXIT

g13_health_to_safe_lines() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

label = sys.argv[1]
payload = json.loads(sys.argv[2])
if payload.get("ok") is not True:
    raise SystemExit(f"status=blocked\nreason={label} health ok is not true")
if payload.get("read_only") is not True:
    raise SystemExit(f"status=blocked\nreason={label} is not read-only")
if payload.get("mail_mutation") is not False:
    raise SystemExit(f"status=blocked\nreason={label} reports mail mutation")
messages = payload.get("messages")
files = payload.get("files")
if not isinstance(messages, int) or messages < 1:
    raise SystemExit(f"status=blocked\nreason={label} message count is invalid")
if not isinstance(files, int) or files < 51588:
    raise SystemExit(f"status=blocked\nreason={label} file count is below enrolled baseline")
print(f"{label}_health_ok=true")
print(f"{label}_health_read_only=true")
print(f"{label}_health_mail_mutation=false")
print(f"{label}_health_messages={messages}")
print(f"{label}_health_files={files}")
PY
}

g13_validate_css() {
  python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

css = Path(sys.argv[1]).read_text(encoding="utf-8")
rules = re.findall(r"\.app-sidebar\{([^}]+)\}", css)
if len(rules) < 2:
    raise SystemExit("status=blocked\nreason=sidebar CSS rules are incomplete")
desktop = rules[0]
if not all(value in desktop for value in (
    "position:sticky", "top:0", "align-self:start", "height:100dvh",
)):
    raise SystemExit("status=blocked\nreason=desktop sticky-sidebar contract failed")
if "position:relative" in desktop:
    raise SystemExit("status=blocked\nreason=obsolete relative desktop sidebar remains")
if not any(
    "position:fixed" in rule and "inset:0 auto 0 0" in rule
    for rule in rules[1:]
):
    raise SystemExit("status=blocked\nreason=mobile fixed-sidebar contract failed")
for required in (
    ".message-address-list{flex-wrap:wrap",
    ".message-address-entry{align-items:center",
    ".message-address-link{overflow-wrap:anywhere",
    ".message-address-entry .mini-copy-button{border-color:var(--line)",
    "width:18px",
    ".message-address-entry .mini-copy-button .icon{flex-basis:11px",
    ".message-address-entry .mini-copy-button.copied{color:#075d34",
    "background:#c8f3d8",
    "border-color:#18864f",
    "transform:scale(1.12)",
    "box-shadow:0 0 0 2px #18864f40",
):
    if required not in css:
        raise SystemExit("status=blocked\nreason=strong address copy feedback CSS contract failed")
print("desktop_sidebar_position=sticky")
print("desktop_sidebar_height=100dvh")
print("mobile_sidebar_position=fixed")
print("message_address_wrapping_css=pass")
print("message_address_copy_button_size=18px")
print("message_address_copy_icon_size=11px")
print("message_address_copy_noticeable_resting_state=pass")
print("message_address_copy_feedback_fill=#c8f3d8")
print("message_address_copy_feedback_border=#18864f")
print("message_address_copy_feedback_icon=#075d34")
print("message_address_copy_feedback_ring=2px")
print("message_address_copy_feedback_scale=1.12")
PY
}

printf '%s\n' 'gate=16-guarded-multisource-production-browser-replacement'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_public_source_labels_and_statuses_only'
printf '%s\n' 'authorized_production_browser_binary_replacement=yes'
printf '%s\n' 'authorized_production_control_config_index_mail_change=no'
printf '%s\n' 'authorized_gate_15_candidate_stop=no'
printf '%s\n' 'automatic_failure_rollback=old_binary_and_browser_service'
printf '%s\n' 'authorized_mail_tag_index_config_mutation=no'

for tool in git bash sh python3 find stat sha256sum curl ss awk sed grep sort wc tr \
  readlink install date seq notmuch paste mktemp mv chmod sleep cp sv rm dirname cat; do
  command -v "$tool" >/dev/null 2>&1 || g13_die "missing required command: $tool"
done

cd "$G13_REPO"
g13_equal repository_commit "$(git rev-parse HEAD)" "$G13_COMMIT"
g13_equal repository_branch "$(git branch --show-current)" "$G13_BRANCH"
g13_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G13_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g13_die "repository is not clean"
printf '%s\n' repository_clean_before=yes

g13_equal gate_15_batch_sha256 \
  "$(sha256sum "$G13_GATE15_BATCH" | awk '{print $1}')" "$G13_GATE15_BATCH_SHA"
g13_equal gate_15_log_sha256 \
  "$(sha256sum "$G13_GATE15_LOG" | awk '{print $1}')" "$G13_GATE15_LOG_SHA"
g13_equal gate_15_record_sha256 \
  "$(sha256sum "$G13_GATE15_RECORD" | awk '{print $1}')" "$G13_GATE15_RECORD_SHA"
grep -Fqx result=success "$G13_GATE15_RECORD" ||
  g13_die "Gate 15 result is not success"
grep -Fqx privacy_review=automated_and_manual_passed "$G13_GATE15_RECORD" ||
  g13_die "Gate 15 privacy review is incomplete"
grep -Fq 'antiX and Windows 11 through the SSH tunnel' "$G13_REPO/docs/PROJECT_STATE.md" ||
  g13_die "cross-platform Gate 15 acceptance is missing from project state"
grep -Fq 'antiX and Windows SSH-tunnel GUI PASS' \
  "$G13_REPO/docs/validation/notmuch-browser-multisource/INDEX.md" ||
  g13_die "cross-platform Gate 15 acceptance is missing from validation index"
printf '%s\n' gate_15_cross_platform_gui_acceptance=verified

g13_equal gate_15_pointer_sha256 \
  "$(sha256sum "$G13_GATE15_POINTER" | awk '{print $1}')" "$G13_GATE15_POINTER_SHA"
g13_equal gate_15_pointer_mode "$(stat -c '%a' "$G13_GATE15_POINTER")" 600
g13_equal gate_15_pointer_status \
  "$(g13_pointer_value "$G13_GATE15_POINTER" status)" retained_for_gui_review
g13_equal gate_15_pointer_commit \
  "$(g13_pointer_value "$G13_GATE15_POINTER" repository_commit)" "$G13_GATE15_COMMIT"
g13_equal gate_15_pointer_addr \
  "$(g13_pointer_value "$G13_GATE15_POINTER" addr)" 127.0.0.1:8876
g13_equal gate_15_pointer_binary_sha256 \
  "$(g13_pointer_value "$G13_GATE15_POINTER" binary_sha256)" "$G13_CANDIDATE_SHA"
G13_GATE15_BINARY=$(g13_pointer_value "$G13_GATE15_POINTER" binary)
[[ -f "$G13_GATE15_BINARY" ]] || g13_die "Gate 15 candidate binary is missing"
g13_equal gate_15_binary_sha256 \
  "$(sha256sum "$G13_GATE15_BINARY" | awk '{print $1}')" "$G13_CANDIDATE_SHA"
g13_equal gate_15_binary_bytes \
  "$(wc -c < "$G13_GATE15_BINARY" | tr -d ' ')" "$G13_CANDIDATE_BYTES"
G13_CURRENT_BOOT_ID=$(sed -n '1p' /proc/sys/kernel/random/boot_id)
G13_GATE15_BOOT_ID=$(g13_pointer_value "$G13_GATE15_POINTER" boot_id)
G13_GATE15_PID=$(g13_pointer_value "$G13_GATE15_POINTER" pid)
G13_GATE15_START_TICKS=$(g13_pointer_value "$G13_GATE15_POINTER" start_ticks)
g13_equal gate_15_pointer_boot_id "$G13_GATE15_BOOT_ID" "$G13_CURRENT_BOOT_ID"
[[ "$G13_GATE15_PID" =~ ^[0-9]+$ && -d "/proc/$G13_GATE15_PID" ]] ||
  g13_die "Gate 15 retained process is not running"
g13_equal gate_15_process_executable \
  "$(readlink -f "/proc/$G13_GATE15_PID/exe")" "$G13_GATE15_BINARY"
g13_equal gate_15_process_start_ticks \
  "$(awk '{print $22}' "/proc/$G13_GATE15_PID/stat")" "$G13_GATE15_START_TICKS"
g13_equal gate_15_port_8876_listener_count \
  "$(ss -H -ltnp 'sport = :8876' | grep -F "pid=$G13_GATE15_PID," | wc -l | tr -d ' ')" 1
G13_GATE15_HEALTH=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8876/healthz)
g13_health_to_safe_lines gate_15_before_install "$G13_GATE15_HEALTH"
printf '%s\n' gate_15_candidate_retained_as_fallback=yes

g13_equal strong_address_copy_feedback_css_sha256 \
  "$(sha256sum "$G13_CSS" | awk '{print $1}')" "$G13_CSS_SHA"
g13_equal strong_address_copy_feedback_css_bytes \
  "$(wc -c < "$G13_CSS" | tr -d ' ')" "$G13_CSS_BYTES"
g13_validate_css "$G13_CSS"
g13_equal strong_address_copy_feedback_js_sha256 \
  "$(sha256sum "$G13_JS" | awk '{print $1}')" "$G13_JS_SHA"
g13_equal strong_address_copy_feedback_js_bytes \
  "$(wc -c < "$G13_JS" | tr -d ' ')" "$G13_JS_BYTES"
grep -Fq 'button.dataset.copyFeedbackMs' "$G13_JS" ||
  g13_die "address feedback-duration JavaScript contract is missing"
grep -Fq 'feedbackDuration' "$G13_JS" ||
  g13_die "copy feedback timer JavaScript contract is missing"
g13_equal old_production_binary_sha256 \
  "$(sha256sum "$G13_PRODUCTION_BINARY" | awk '{print $1}')" "$G13_OLD_PRODUCTION_SHA"
g13_equal old_production_binary_bytes \
  "$(wc -c < "$G13_PRODUCTION_BINARY" | tr -d ' ')" "$G13_OLD_PRODUCTION_BYTES"
g13_equal installed_browser_control_sha256 \
  "$(sha256sum "$G13_BROWSER_CONTROL" | awk '{print $1}')" "$G13_BROWSER_CONTROL_SHA"
g13_equal installed_index_control_sha256 \
  "$(sha256sum "$G13_INDEX_CONTROL" | awk '{print $1}')" "$G13_INDEX_CONTROL_SHA"
g13_equal installed_runit_setup_sha256 \
  "$(sha256sum "$G13_RUNIT_SETUP" | awk '{print $1}')" "$G13_RUNIT_SETUP_SHA"
g13_equal repository_browser_control_sha256 \
  "$(sha256sum "$G13_REPO/scripts/notmuch_browser_control.sh" | awk '{print $1}')" \
  "$G13_BROWSER_CONTROL_SHA"
g13_equal repository_index_control_sha256 \
  "$(sha256sum "$G13_REPO/scripts/notmuch_browser_index_control.sh" | awk '{print $1}')" \
  "$G13_INDEX_CONTROL_SHA"
g13_equal repository_runit_setup_sha256 \
  "$(sha256sum "$G13_REPO/scripts/notmuch_browser_runit_setup.sh" | awk '{print $1}')" \
  "$G13_RUNIT_SETUP_SHA"
g13_equal icewm_startup_sha256 \
  "$(sha256sum "$G13_ICEWM_STARTUP" | awk '{print $1}')" "$G13_ICEWM_STARTUP_SHA"
g13_equal config_sha256 "$(sha256sum "$G13_CONFIG" | awk '{print $1}')" "$G13_CONFIG_SHA"
g13_equal marker_sha256 "$(sha256sum "$G13_MARKER" | awk '{print $1}')" "$G13_MARKER_SHA"
g13_equal final_new_ignore \
  "$(notmuch --config="$G13_CONFIG" config get new.ignore | paste -sd' ' -)" \
  betterbird-post-main-archive-maildirpp-20260704-205827

g13_equal browser_service_target "$(readlink "$G13_BROWSER_SERVICE")" ../usersv/notmuch-browser
g13_equal index_service_target "$(readlink "$G13_INDEX_SERVICE")" ../usersv/notmuch-browser-index
[[ -f "$G13_BROWSER_DEF/.notmuch-browser-user-runit-managed" ]] ||
  g13_die "managed browser service marker is missing"
[[ -f "$G13_INDEX_DEF/.notmuch-browser-user-runit-managed" ]] ||
  g13_die "managed index service marker is missing"
[[ ! -e "$G13_BROWSER_DEF/down" ]] || g13_die "browser runit down marker is present"
[[ ! -e "$G13_INDEX_DEF/down" ]] || g13_die "index runit down marker is present"
sv status "$G13_BROWSER_SERVICE" | grep -Fq 'run:' ||
  g13_die "browser runit service is not running"
sv status "$G13_INDEX_SERVICE" | grep -Fq 'run:' ||
  g13_die "index runit service is not running"

G13_OLD_PRODUCTION_PID=$(sed -n '1p' "$G13_BROWSER_DEF/supervise/pid")
G13_INDEX_PID=$(sed -n '1p' "$G13_INDEX_DEF/supervise/pid")
[[ "$G13_OLD_PRODUCTION_PID" =~ ^[0-9]+$ && -d "/proc/$G13_OLD_PRODUCTION_PID" ]] ||
  g13_die "production browser PID is invalid"
[[ "$G13_INDEX_PID" =~ ^[0-9]+$ && -d "/proc/$G13_INDEX_PID" ]] ||
  g13_die "production index PID is invalid"
G13_OLD_PRODUCTION_START_TICKS=$(awk '{print $22}' "/proc/$G13_OLD_PRODUCTION_PID/stat")
G13_INDEX_START_TICKS=$(awk '{print $22}' "/proc/$G13_INDEX_PID/stat")
g13_equal old_production_process_executable \
  "$(readlink -f "/proc/$G13_OLD_PRODUCTION_PID/exe")" "$G13_PRODUCTION_BINARY"
g13_equal production_port_8765_listener_count \
  "$(ss -H -ltnp 'sport = :8765' | grep -F "pid=$G13_OLD_PRODUCTION_PID," | wc -l | tr -d ' ')" 1
G13_PRODUCTION_HEALTH_BEFORE=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8765/healthz)
g13_health_to_safe_lines production_before "$G13_PRODUCTION_HEALTH_BEFORE"
printf 'old_production_pid=%s\n' "$G13_OLD_PRODUCTION_PID"
printf 'old_production_start_ticks=%s\n' "$G13_OLD_PRODUCTION_START_TICKS"
printf 'index_pid_before=%s\n' "$G13_INDEX_PID"
printf 'index_start_ticks_before=%s\n' "$G13_INDEX_START_TICKS"

[[ ! -e "$G13_ROLLBACK_POINTER" ]] ||
  g13_die "Gate 16 rollback pointer already exists"
[[ ! -e "$G13_PRODUCTION_POINTER" ]] ||
  g13_die "Gate 16 production pointer already exists"
[[ ! -e "$G13_ROLLOUT_ROOT" ]] ||
  g13_die "Gate 16 production rollout root already exists"

G13_STAMP=$(date +%Y%m%d-%H%M%S)
G13_RUN_DIR="$G13_ROLLOUT_ROOT/$G13_STAMP"
G13_EVIDENCE="$G13_RUN_DIR/http-evidence"
G13_BACKUP="$G13_BACKUP_ROOT/$G13_STAMP-before-multisource-production"
G13_ROLLBACK_LOG="$G13_RUN_DIR/automatic-rollback.log"
install -d -m 700 "$G13_RUN_DIR" "$G13_EVIDENCE" "$G13_BACKUP"
chmod 700 "$G13_ROLLOUT_ROOT"

cp -p "$G13_PRODUCTION_BINARY" "$G13_BACKUP/notmuch-browser"
cp -p "$G13_BROWSER_CONTROL" "$G13_BACKUP/notmuch-browser-control"
cp -p "$G13_INDEX_CONTROL" "$G13_BACKUP/notmuch-browser-index-control"
cp -p "$G13_RUNIT_SETUP" "$G13_BACKUP/notmuch-browser-runit-setup"
cp -p "$G13_CONFIG" "$G13_BACKUP/notmuch-config"
cp -p "$G13_ICEWM_STARTUP" "$G13_BACKUP/icewm-startup"
cp -p "$G13_BROWSER_DEF/run" "$G13_BACKUP/browser-run"
cp -p "$G13_BROWSER_DEF/finish" "$G13_BACKUP/browser-finish"
cp -p "$G13_BROWSER_DEF/check" "$G13_BACKUP/browser-check"
cp -p "$G13_BROWSER_DEF/log/run" "$G13_BACKUP/browser-log-run"
cp -p "$G13_INDEX_DEF/run" "$G13_BACKUP/index-run"
cp -p "$G13_INDEX_DEF/finish" "$G13_BACKUP/index-finish"
cp -p "$G13_INDEX_DEF/check" "$G13_BACKUP/index-check"
cp -p "$G13_INDEX_DEF/log/run" "$G13_BACKUP/index-log-run"

cat > "$G13_BACKUP/state.env" <<EOF
schema_version=1
repository_commit=$G13_COMMIT
old_binary_sha256=$G13_OLD_PRODUCTION_SHA
new_binary_sha256=$G13_CANDIDATE_SHA
old_production_pid=$G13_OLD_PRODUCTION_PID
old_production_start_ticks=$G13_OLD_PRODUCTION_START_TICKS
index_pid=$G13_INDEX_PID
index_start_ticks=$G13_INDEX_START_TICKS
gate_15_pointer_sha256=$G13_GATE15_POINTER_SHA
created_at=$(date --iso-8601=ns)
EOF
chmod 600 "$G13_BACKUP/state.env"

cat > "$G13_BACKUP/rollback-browser.sh" <<'ROLLBACK'
#!/bin/bash
set -Eeuo pipefail
umask 077
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=/home/atiq/.local/bin/notmuch-browser
SERVICE=/home/atiq/.runit/service/notmuch-browser
OLD_SHA=c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9
TEMP=
cleanup() {
  if [[ -n "$TEMP" && -e "$TEMP" ]]; then rm -f -- "$TEMP"; fi
}
trap cleanup EXIT
[[ "$(sha256sum "$SCRIPT_DIR/notmuch-browser" | awk '{print $1}')" == "$OLD_SHA" ]]
sv -w 20 down "$SERVICE"
TEMP=$(mktemp /home/atiq/.local/bin/.notmuch-browser.rollback.XXXXXX)
install -m 755 "$SCRIPT_DIR/notmuch-browser" "$TEMP"
[[ "$(sha256sum "$TEMP" | awk '{print $1}')" == "$OLD_SHA" ]]
mv "$TEMP" "$TARGET"
TEMP=
sv -w 20 up "$SERVICE"
health=
for _ in $(seq 1 60); do
  if health=$(curl --silent --show-error --fail --max-time 5 \
    http://127.0.0.1:8765/healthz 2>/dev/null); then
    break
  fi
  sleep 1
done
[[ "$health" == *'"ok":true'* ]]
[[ "$health" == *'"read_only":true'* ]]
[[ "$health" == *'"mail_mutation":false'* ]]
[[ "$(sha256sum "$TARGET" | awk '{print $1}')" == "$OLD_SHA" ]]
printf '%s\n' rollback_status=old_production_browser_restored
printf 'rollback_binary_sha256=%s\n' "$OLD_SHA"
ROLLBACK
chmod 700 "$G13_BACKUP/rollback-browser.sh"
bash -n "$G13_BACKUP/rollback-browser.sh"

(
  cd "$G13_BACKUP"
  sha256sum \
    notmuch-browser \
    notmuch-browser-control \
    notmuch-browser-index-control \
    notmuch-browser-runit-setup \
    notmuch-config \
    icewm-startup \
    browser-run \
    browser-finish \
    browser-check \
    browser-log-run \
    index-run \
    index-finish \
    index-check \
    index-log-run \
    state.env \
    rollback-browser.sh > backup-inventory.sha256
  sha256sum -c backup-inventory.sha256 >/dev/null
)
G13_BACKUP_INVENTORY_SHA=$(sha256sum "$G13_BACKUP/backup-inventory.sha256" | awk '{print $1}')
G13_ROLLBACK_SCRIPT_SHA=$(sha256sum "$G13_BACKUP/rollback-browser.sh" | awk '{print $1}')
printf 'rollback_backup=%s\n' "$G13_BACKUP"
printf 'rollback_backup_inventory_sha256=%s\n' "$G13_BACKUP_INVENTORY_SHA"
printf 'rollback_script_sha256=%s\n' "$G13_ROLLBACK_SCRIPT_SHA"
printf 'rollback_backup_files=%s\n' \
  "$(find "$G13_BACKUP" -maxdepth 1 -type f -print | wc -l | tr -d ' ')"
printf 'rollback_backup_mode=%s\n' "$(stat -c '%a' "$G13_BACKUP")"

G13_ROLLBACK_POINTER_TMP=$(mktemp "$G13_STATE_ROOT/.multisource-production-rollback.XXXXXX")
{
  printf 'schema_version=1\n'
  printf 'status=ready_before_install\n'
  printf 'repository_commit=%s\n' "$G13_COMMIT"
  printf 'backup=%s\n' "$G13_BACKUP"
  printf 'backup_inventory_sha256=%s\n' "$G13_BACKUP_INVENTORY_SHA"
  printf 'rollback_script=%s\n' "$G13_BACKUP/rollback-browser.sh"
  printf 'rollback_script_sha256=%s\n' "$G13_ROLLBACK_SCRIPT_SHA"
  printf 'old_binary_sha256=%s\n' "$G13_OLD_PRODUCTION_SHA"
  printf 'new_binary_sha256=%s\n' "$G13_CANDIDATE_SHA"
  printf 'created_at=%s\n' "$(date --iso-8601=ns)"
} > "$G13_ROLLBACK_POINTER_TMP"
chmod 600 "$G13_ROLLBACK_POINTER_TMP"
mv "$G13_ROLLBACK_POINTER_TMP" "$G13_ROLLBACK_POINTER"
printf 'rollback_pointer=%s\n' "$G13_ROLLBACK_POINTER"
printf 'rollback_pointer_sha256=%s\n' \
  "$(sha256sum "$G13_ROLLBACK_POINTER" | awk '{print $1}')"
printf 'rollback_pointer_mode=%s\n' "$(stat -c '%a' "$G13_ROLLBACK_POINTER")"

G13_INSTALL_STARTED=yes
sv -w 20 down "$G13_BROWSER_SERVICE"
g13_equal production_port_8765_listeners_while_down \
  "$(ss -H -ltnp 'sport = :8765' | wc -l | tr -d ' ')" 0
G13_INSTALL_TEMP=$(mktemp /home/atiq/.local/bin/.notmuch-browser.gate16.XXXXXX)
install -m 755 "$G13_GATE15_BINARY" "$G13_INSTALL_TEMP"
g13_equal staged_production_binary_sha256 \
  "$(sha256sum "$G13_INSTALL_TEMP" | awk '{print $1}')" "$G13_CANDIDATE_SHA"
g13_equal staged_production_binary_bytes \
  "$(wc -c < "$G13_INSTALL_TEMP" | tr -d ' ')" "$G13_CANDIDATE_BYTES"
mv "$G13_INSTALL_TEMP" "$G13_PRODUCTION_BINARY"
G13_INSTALL_TEMP=
g13_equal installed_production_binary_sha256 \
  "$(sha256sum "$G13_PRODUCTION_BINARY" | awk '{print $1}')" "$G13_CANDIDATE_SHA"
g13_equal installed_production_binary_bytes \
  "$(wc -c < "$G13_PRODUCTION_BINARY" | tr -d ' ')" "$G13_CANDIDATE_BYTES"
g13_equal installed_production_binary_mode "$(stat -c '%a' "$G13_PRODUCTION_BINARY")" 755
sv -w 20 up "$G13_BROWSER_SERVICE"

G13_PRODUCTION_HEALTH=
for _ in $(seq 1 60); do
  if G13_PRODUCTION_HEALTH=$(curl --silent --show-error --fail --max-time 5 \
    http://127.0.0.1:8765/healthz 2>/dev/null); then
    break
  fi
  sleep 1
done
[[ -n "$G13_PRODUCTION_HEALTH" ]] || g13_die "new production health did not become ready"
g13_health_to_safe_lines production "$G13_PRODUCTION_HEALTH"
G13_NEW_PRODUCTION_PID=$(sed -n '1p' "$G13_BROWSER_DEF/supervise/pid")
[[ "$G13_NEW_PRODUCTION_PID" =~ ^[0-9]+$ && -d "/proc/$G13_NEW_PRODUCTION_PID" ]] ||
  g13_die "new production browser PID is invalid"
[[ "$G13_NEW_PRODUCTION_PID" != "$G13_OLD_PRODUCTION_PID" ]] ||
  g13_die "production browser PID did not change"
G13_NEW_PRODUCTION_START_TICKS=$(awk '{print $22}' "/proc/$G13_NEW_PRODUCTION_PID/stat")
g13_equal new_production_process_executable \
  "$(readlink -f "/proc/$G13_NEW_PRODUCTION_PID/exe")" "$G13_PRODUCTION_BINARY"
g13_equal production_port_8765_listener_count_after_start \
  "$(ss -H -ltnp 'sport = :8765' | grep -F "pid=$G13_NEW_PRODUCTION_PID," | wc -l | tr -d ' ')" 1
printf 'new_production_pid=%s\n' "$G13_NEW_PRODUCTION_PID"
printf 'new_production_start_ticks=%s\n' "$G13_NEW_PRODUCTION_START_TICKS"
g13_equal index_pid_unchanged "$(sed -n '1p' "$G13_INDEX_DEF/supervise/pid")" "$G13_INDEX_PID"
g13_equal index_start_ticks_unchanged \
  "$(awk '{print $22}' "/proc/$G13_INDEX_PID/stat")" "$G13_INDEX_START_TICKS"
g13_candidate_matches || g13_die "Gate 15 fallback candidate identity changed"
printf '%s\n' gate_15_fallback_candidate_still_running=yes

curl --silent --show-error --fail --max-time 20 \
  --output "$G13_EVIDENCE/app.css" \
  http://127.0.0.1:8765/static/app.css
g13_equal production_served_css_sha256 \
  "$(sha256sum "$G13_EVIDENCE/app.css" | awk '{print $1}')" "$G13_CSS_SHA"
g13_equal production_served_css_bytes \
  "$(wc -c < "$G13_EVIDENCE/app.css" | tr -d ' ')" "$G13_CSS_BYTES"
g13_validate_css "$G13_EVIDENCE/app.css"

curl --silent --show-error --fail --max-time 20 \
  --output "$G13_EVIDENCE/app.js" \
  http://127.0.0.1:8765/static/app.js
g13_equal production_served_js_sha256 \
  "$(sha256sum "$G13_EVIDENCE/app.js" | awk '{print $1}')" "$G13_JS_SHA"
g13_equal production_served_js_bytes \
  "$(wc -c < "$G13_EVIDENCE/app.js" | tr -d ' ')" "$G13_JS_BYTES"
grep -Fq 'button.dataset.copyFeedbackMs' "$G13_EVIDENCE/app.js" ||
  g13_die "served address feedback-duration JavaScript contract is missing"
grep -Fq 'feedbackDuration' "$G13_EVIDENCE/app.js" ||
  g13_die "served copy feedback timer JavaScript contract is missing"
printf '%s\n' production_served_copy_feedback_timer_contract=pass

curl --silent --show-error --fail --max-time 120 \
  --dump-header "$G13_EVIDENCE/root.headers" \
  --output "$G13_EVIDENCE/root.html" \
  'http://127.0.0.1:8765/?q=%2A&folder=all'
for spec in \
  'provider-live|mbsync/provider-live|nonempty' \
  'provider-inbox-test|mbsync/provider-inbox-test|nonempty' \
  'local-maildir|evolution/local-maildir|nonempty' \
  'betterbird-delta|evolution/betterbird-delta-maildirpp-20260704|nonempty' \
  'provider-live-archive|evolution/provider-live-archive|empty' \
  'test-maildir|evolution/test-maildir|exact-four'; do
  IFS='|' read -r slug folder expectation <<< "$spec"
  curl --silent --show-error --fail --max-time 120 \
    --header 'HX-Request: true' \
    --get \
    --data-urlencode 'q=*' \
    --data-urlencode "folder=$folder" \
    --data-urlencode 'limit=5' \
    --dump-header "$G13_EVIDENCE/$slug.headers" \
    --output "$G13_EVIDENCE/$slug.html" \
    http://127.0.0.1:8765/search
  printf 'saved_private_source_response=%s:%s\n' \
    "$slug" "$(sha256sum "$G13_EVIDENCE/$slug.html" | awk '{print $1}')"
done
curl --silent --show-error --fail --max-time 120 \
  --get \
  --data-urlencode 'q=*' \
  --data-urlencode 'folder=../private' \
  --output "$G13_EVIDENCE/invalid-folder.html" \
  http://127.0.0.1:8765/search

python3 - "$G13_EVIDENCE" <<'PY'
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
import re
import sys


class AuditParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.options = []
        self.groups = []
        self.rows = 0
        self.datetimes = []
        self.time_texts = []
        self.message_urls = []
        self.text = []
        self._time = None

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        classes = set(data.get("class", "").split())
        if tag == "option" and "value" in data:
            self.options.append(data["value"])
        if tag == "optgroup" and "label" in data:
            self.groups.append(data["label"])
        if tag == "tr" and "data-message-row" in data:
            self.rows += 1
        if tag == "time":
            self.datetimes.append(data.get("datetime", ""))
            self._time = []
        if tag == "a" and "subject" in classes:
            href = data.get("href", "")
            if href.startswith("/message?"):
                self.message_urls.append(href)

    def handle_endtag(self, tag):
        if tag == "time" and self._time is not None:
            self.time_texts.append("".join(self._time).strip())
            self._time = None

    def handle_data(self, data):
        self.text.append(data)
        if self._time is not None:
            self._time.append(data)


def parse(path):
    parser = AuditParser()
    parser.feed(path.read_text(encoding="utf-8"))
    return parser


root = Path(sys.argv[1])
page = parse(root / "root.html")
required_options = {
    "all",
    "mbsync/provider-live",
    "mbsync/provider-inbox-test",
    "evolution/local-maildir",
    "evolution/betterbird-delta-maildirpp-20260704",
    "evolution/provider-live-archive",
    "evolution/test-maildir",
}
if not required_options.issubset(set(page.options)):
    raise SystemExit("status=blocked\nreason=required GUI source option is missing")
if len(page.groups) != 6 or page.rows < 1 or not page.message_urls:
    raise SystemExit("status=blocked\nreason=All Mail GUI contract failed")
if "mailto:" in (root / "root.html").read_text(encoding="utf-8"):
    raise SystemExit("status=blocked\nreason=search result sender became a mailto link")
(root / "message.url").write_text(page.message_urls[0], encoding="utf-8")
print(f"root_folder_option_count={len(page.options)}")
print("root_approved_source_groups=6")
print(f"root_result_rows={page.rows}")
print("search_result_sender_plain_text=yes")

date_pattern = re.compile(
    r"^(Now|[1-9][0-9]* min ago|1 hour ago|"
    r"Today (0[1-9]|1[0-2]):[0-5][0-9]:[0-5][0-9] [AP]M|"
    r"Yesterday (0[1-9]|1[0-2]):[0-5][0-9]:[0-5][0-9] [AP]M|"
    r"(Mon|Tue|Wed|Thu|Fri|Sat|Sun), [0-3][0-9] "
    r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [0-9]{4}, "
    r"(0[1-9]|1[0-2]):[0-5][0-9]:[0-5][0-9] [AP]M)$"
)
for slug, expectation in (
    ("provider-live", "nonempty"),
    ("provider-inbox-test", "nonempty"),
    ("local-maildir", "nonempty"),
    ("betterbird-delta", "nonempty"),
    ("provider-live-archive", "empty"),
    ("test-maildir", "exact-four"),
):
    parsed = parse(root / f"{slug}.html")
    combined = " ".join(parsed.text)
    if "Newest first" not in combined:
        raise SystemExit(f"status=blocked\nreason={slug} lacks newest-first marker")
    if expectation == "empty":
        if parsed.rows != 0 or "No results" not in combined:
            raise SystemExit(f"status=blocked\nreason={slug} empty-source contract failed")
    else:
        if parsed.rows < 1 or parsed.rows > 5:
            raise SystemExit(f"status=blocked\nreason={slug} row count is invalid")
        if expectation == "exact-four" and parsed.rows != 4:
            raise SystemExit(f"status=blocked\nreason={slug} exact-four contract failed")
        if len(parsed.datetimes) != parsed.rows or any(not value for value in parsed.datetimes):
            raise SystemExit(f"status=blocked\nreason={slug} datetime markup is incomplete")
        moments = [datetime.fromisoformat(value) for value in parsed.datetimes]
        if any(left < right for left, right in zip(moments, moments[1:])):
            raise SystemExit(f"status=blocked\nreason={slug} rows are not newest first")
        if len(parsed.time_texts) != parsed.rows or any(
            not date_pattern.fullmatch(value) for value in parsed.time_texts
        ):
            raise SystemExit(f"status=blocked\nreason={slug} date display contract failed")
    print(
        f"source_validation={slug}:rows={parsed.rows}:"
        "newest_first=yes:date_contract=yes"
    )

invalid = (root / "invalid-folder.html").read_text(encoding="utf-8")
if "Unknown mail folder selection." not in invalid:
    raise SystemExit("status=blocked\nreason=invalid folder was not rejected")
print("invalid_folder_rejected=yes")
PY

G13_GATE15_EVIDENCE=$(g13_pointer_value "$G13_GATE15_POINTER" http_evidence)
[[ -d "$G13_GATE15_EVIDENCE" && -s "$G13_GATE15_EVIDENCE/message.url" ]] ||
  g13_die "Gate 15 private message sample is missing"
G13_MESSAGE_URL=$(sed -n '1p' "$G13_GATE15_EVIDENCE/message.url")
[[ "$G13_MESSAGE_URL" == /message\?* ]] ||
  g13_die "private message URL extraction failed"
curl --silent --show-error --fail --max-time 120 \
  --output "$G13_EVIDENCE/message.html" \
  "http://127.0.0.1:8765$G13_MESSAGE_URL"

python3 - "$G13_EVIDENCE/message.html" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote
import sys


class AddressParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.labels = []
        self.links = []
        self.copies = []
        self.feedback_durations = []
        self._dt = None

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        classes = set(data.get("class", "").split())
        if tag == "dt":
            self._dt = []
        if tag == "a" and "message-address-link" in classes:
            self.links.append(data.get("href", ""))
        if tag == "button" and data.get("aria-label", "").startswith("Copy email address "):
            self.copies.append(data.get("data-copy-text", ""))
            self.feedback_durations.append(data.get("data-copy-feedback-ms", ""))

    def handle_data(self, data):
        if self._dt is not None:
            self._dt.append(data)

    def handle_endtag(self, tag):
        if tag == "dt" and self._dt is not None:
            self.labels.append("".join(self._dt).strip())
            self._dt = None


parser = AddressParser()
parser.feed(Path(sys.argv[1]).read_text(encoding="utf-8"))
if "From" not in parser.labels or "To" not in parser.labels:
    raise SystemExit("status=blocked\nreason=message address field labels are missing")
if not parser.links:
    raise SystemExit("status=blocked\nreason=message has no rendered address link")
if len(parser.links) != len(parser.copies):
    raise SystemExit("status=blocked\nreason=address link/copy counts differ")
if len(parser.feedback_durations) != len(parser.copies):
    raise SystemExit("status=blocked\nreason=address feedback-duration count differs")
if any(value != "2200" for value in parser.feedback_durations):
    raise SystemExit("status=blocked\nreason=address feedback duration is not 2200ms")
decoded = []
for href in parser.links:
    if not href.startswith("mailto:") or "?" in href or "#" in href:
        raise SystemExit("status=blocked\nreason=unsafe mailto target rendered")
    decoded.append(unquote(href.removeprefix("mailto:")))
if decoded != parser.copies or any(not value for value in parser.copies):
    raise SystemExit("status=blocked\nreason=copy value differs from mailto address")
print(f"message_address_link_count={len(parser.links)}")
print(f"message_address_copy_count={len(parser.copies)}")
print("message_address_mailto_query_free=yes")
print("message_address_copy_values_raw=yes")
print("message_address_feedback_duration_ms=2200")
print("message_address_from_to_labels=yes")
print("bcc_rendering_fixture_in_gate_15=verified")
PY

for header in \
  'content-security-policy:' \
  'cache-control: private, no-store' \
  'x-content-type-options: nosniff' \
  'referrer-policy: no-referrer'; do
  grep -Fqi "$header" "$G13_EVIDENCE/root.headers" ||
    g13_die "production root is missing security header: $header"
done
printf '%s\n' production_security_headers=pass
g13_equal production_static_css_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    http://127.0.0.1:8765/static/app.css)" 200
g13_equal production_static_js_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    http://127.0.0.1:8765/static/app.js)" 200
g13_equal production_status_route_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 60 \
    http://127.0.0.1:8765/status)" 200
g13_equal production_post_search_status \
  "$(curl --silent --request POST --output /dev/null --write-out '%{http_code}' \
    --max-time 20 http://127.0.0.1:8765/search)" 405
if [[ -d "$G13_DOWNLOAD_TMP" ]]; then
  G13_DOWNLOAD_TEMP_COUNT=$(find "$G13_DOWNLOAD_TMP" -maxdepth 1 -type f \
    -name 'nmb-*' -print | wc -l | tr -d ' ')
else
  G13_DOWNLOAD_TEMP_COUNT=0
fi
g13_equal production_download_temp_files "$G13_DOWNLOAD_TEMP_COUNT" 0

G13_PRODUCTION_HEALTH_AFTER=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8765/healthz)
g13_health_to_safe_lines production_after "$G13_PRODUCTION_HEALTH_AFTER"
g13_equal production_binary_sha256_after \
  "$(sha256sum "$G13_PRODUCTION_BINARY" | awk '{print $1}')" "$G13_CANDIDATE_SHA"
g13_equal production_port_8765_listener_count_after \
  "$(ss -H -ltnp 'sport = :8765' | grep -F "pid=$G13_NEW_PRODUCTION_PID," | wc -l | tr -d ' ')" 1
g13_equal browser_control_sha256_after \
  "$(sha256sum "$G13_BROWSER_CONTROL" | awk '{print $1}')" "$G13_BROWSER_CONTROL_SHA"
g13_equal index_control_sha256_after \
  "$(sha256sum "$G13_INDEX_CONTROL" | awk '{print $1}')" "$G13_INDEX_CONTROL_SHA"
g13_equal runit_setup_sha256_after \
  "$(sha256sum "$G13_RUNIT_SETUP" | awk '{print $1}')" "$G13_RUNIT_SETUP_SHA"
g13_equal config_sha256_after "$(sha256sum "$G13_CONFIG" | awk '{print $1}')" "$G13_CONFIG_SHA"
g13_equal marker_sha256_after "$(sha256sum "$G13_MARKER" | awk '{print $1}')" "$G13_MARKER_SHA"
g13_equal icewm_startup_sha256_after \
  "$(sha256sum "$G13_ICEWM_STARTUP" | awk '{print $1}')" "$G13_ICEWM_STARTUP_SHA"
g13_candidate_matches || g13_die "Gate 15 fallback candidate identity changed during validation"
g13_equal gate_15_port_8876_listener_count_after \
  "$(ss -H -ltnp 'sport = :8876' | grep -F "pid=$G13_GATE15_PID," | wc -l | tr -d ' ')" 1
"$G13_RUNIT_SETUP" validate >/dev/null
printf '%s\n' production_user_runit_validation=pass

G13_POINTER_TMP=$(mktemp "$G13_STATE_ROOT/.multisource-production-current.XXXXXX")
{
  printf 'schema_version=1\n'
  printf 'status=installed_awaiting_production_gui_review\n'
  printf 'repository_commit=%s\n' "$G13_COMMIT"
  printf 'binary=%s\n' "$G13_PRODUCTION_BINARY"
  printf 'binary_sha256=%s\n' "$G13_CANDIDATE_SHA"
  printf 'binary_bytes=%s\n' "$G13_CANDIDATE_BYTES"
  printf 'pid=%s\n' "$G13_NEW_PRODUCTION_PID"
  printf 'start_ticks=%s\n' "$G13_NEW_PRODUCTION_START_TICKS"
  printf 'boot_id=%s\n' "$G13_CURRENT_BOOT_ID"
  printf 'addr=127.0.0.1:8765\n'
  printf 'rollback_pointer=%s\n' "$G13_ROLLBACK_POINTER"
  printf 'rollback_backup=%s\n' "$G13_BACKUP"
  printf 'gate_15_fallback_pointer=%s\n' "$G13_GATE15_POINTER"
  printf 'gate_15_fallback_pid=%s\n' "$G13_GATE15_PID"
  printf 'gate_15_fallback_addr=127.0.0.1:8876\n'
  printf 'http_evidence=%s\n' "$G13_EVIDENCE"
  printf 'created_at=%s\n' "$(date --iso-8601=ns)"
} > "$G13_POINTER_TMP"
chmod 600 "$G13_POINTER_TMP"
mv "$G13_POINTER_TMP" "$G13_PRODUCTION_POINTER"
printf 'production_pointer=%s\n' "$G13_PRODUCTION_POINTER"
printf 'production_pointer_sha256=%s\n' \
  "$(sha256sum "$G13_PRODUCTION_POINTER" | awk '{print $1}')"
printf 'production_pointer_mode=%s\n' "$(stat -c '%a' "$G13_PRODUCTION_POINTER")"
printf 'production_http_evidence_files=%s\n' \
  "$(find "$G13_EVIDENCE" -maxdepth 1 -type f -print | wc -l | tr -d ' ')"
(
  cd "$G13_EVIDENCE"
  find . -type f -printf '%P\n' |
    LC_ALL=C sort |
    while IFS= read -r file; do sha256sum "$file"; done |
    sha256sum |
    awk '{print "production_http_evidence_manifest_sha256=" $1}'
)
G13_INSTALL_COMMITTED=yes
printf '%s\n' production_browser_replaced=yes
printf '%s\n' gate_15_candidate_retained_for_fallback=yes
printf '%s\n' production_controls_config_index_service_unchanged=yes
printf '%s\n' automatic_rollback_invoked=no
printf '%s\n' mail_tag_index_config_mutation_by_gate=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_16_guarded_multisource_production_browser_replacement_pass
