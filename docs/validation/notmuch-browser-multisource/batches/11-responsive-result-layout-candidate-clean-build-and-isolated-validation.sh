#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 11: clean-build and retain the responsive result-layout candidate on
# localhost:8876 after pinning the successful Gate 10 evidence.
G8_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G8_COMMIT=a1ec21a6516b36f4a3ac89ed0e2d7d40a0dbea53
G8_BRANCH=atiqte/branch-codex
G8_CONFIG=/home/atiq/.config/notmuch/default/config
G8_MAILSTORE=/mail/Mailstore
G8_STATE_ROOT=/mail/AppData/notmuch-browser
G8_CANDIDATE_ROOT="$G8_STATE_ROOT/multisource-layout-candidate"
G8_POINTER="$G8_STATE_ROOT/multisource-layout-candidate-current.env"
G8_LOG_ROOT=/mail/Logs/notmuch-browser/multisource-layout-candidate
G8_BROWSER_CONTROL=/home/atiq/.local/bin/notmuch-browser-control
G8_INDEX_CONTROL=/home/atiq/.local/bin/notmuch-browser-index-control
G8_MBSYNC_CONTROL=/home/atiq/.local/bin/mbsync-provider-live-control
G8_BUILD_SCRIPT="$G8_REPO/scripts/notmuch_browser_build.sh"
G8_GATE7_BATCH="$G8_REPO/docs/validation/notmuch-browser-multisource/batches/07-corrected-guarded-current-source-enrollment-retry.sh"
G8_GATE7_LOG="$G8_REPO/docs/validation/notmuch-browser-multisource/logs/07-corrected-guarded-current-source-enrollment-retry.log"
G8_GATE7_RECORD="$G8_REPO/docs/validation/notmuch-browser-multisource/records/07-corrected-guarded-current-source-enrollment-retry.env"
G8_GATE7_BATCH_SHA=0dcaf1eef95e3aae0ba4ea36da7f0b46d0ea36b023c79e7996cc5a5554cbbe4e
G8_GATE7_LOG_SHA=107c1431be976b85d3f7130ed862dfd39e3d40a62d82768b17f78f399440e773
G8_GATE7_RECORD_SHA=3ea6f0b059214a984d59dcdd52aac92bbcaa5dffbba2fb0ef00c3ca9622b5c66
G8_GATE8_BATCH="$G8_REPO/docs/validation/notmuch-browser-multisource/batches/08-multisource-candidate-clean-build-and-isolated-validation.sh"
G8_GATE8_LOG="$G8_REPO/docs/validation/notmuch-browser-multisource/logs/08-multisource-candidate-clean-build-and-isolated-validation.log"
G8_GATE8_RECORD="$G8_REPO/docs/validation/notmuch-browser-multisource/records/08-multisource-candidate-clean-build-and-isolated-validation.env"
G8_GATE8_BATCH_SHA=6643d3515fd16f752fd91fe66a70991ef948fe444d71fc78cba6b918485a6ed1
G8_GATE8_LOG_SHA=307828c94f9dac2d30901fb8c2fe96a3c970fc3ad342ea1889847438872a6262
G8_GATE8_RECORD_SHA=caa46b341322d9728620046def5be439ccf75930005c0efa816414293e7af1b3
G8_GATE9_BATCH="$G8_REPO/docs/validation/notmuch-browser-multisource/batches/09-corrected-multisource-candidate-clean-build-and-isolated-validation-retry.sh"
G8_GATE9_LOG="$G8_REPO/docs/validation/notmuch-browser-multisource/logs/09-corrected-multisource-candidate-clean-build-and-isolated-validation-retry.log"
G8_GATE9_RECORD="$G8_REPO/docs/validation/notmuch-browser-multisource/records/09-corrected-multisource-candidate-clean-build-and-isolated-validation-retry.env"
G8_GATE9_BATCH_SHA=13b1abef9f7700f10f1caca86b66309d9ea75edb7a14dc4d4c57dc0c54779a29
G8_GATE9_LOG_SHA=daa82e77c052dbf5a4f4ad9f663c1932ef32d8c69a1e4f74f26262c17866fe50
G8_GATE9_RECORD_SHA=7819de272cd044e0679c0f36550efb55ca9d2791453128873b25dd01ea86be90
G8_GATE10_BATCH="$G8_REPO/docs/validation/notmuch-browser-multisource/batches/10-scoped-match-all-fix-candidate-clean-build-and-isolated-validation.sh"
G8_GATE10_LOG="$G8_REPO/docs/validation/notmuch-browser-multisource/logs/10-scoped-match-all-fix-candidate-clean-build-and-isolated-validation.log"
G8_GATE10_RECORD="$G8_REPO/docs/validation/notmuch-browser-multisource/records/10-scoped-match-all-fix-candidate-clean-build-and-isolated-validation.env"
G8_GATE10_BATCH_SHA=95e8f140e744881e584d8c984b224718beac09b04568fcfc9562e69ae38d0436
G8_GATE10_LOG_SHA=086c0fd5da5dd8040babbe19764729f3f10a8d5dc43c8e0e2a01c41a71c56e3d
G8_GATE10_RECORD_SHA=67509e5195daff8a8684231e3c1d46c838a7fc1126d5dcfb6b1db9083742e53d
G8_GATE10_POINTER="$G8_STATE_ROOT/multisource-candidate-current.env"
G8_GATE10_POINTER_SHA=d8e111cad70382e227f811285b4fc0b77e83c900d22c89d30e925083b5f56b5c
G8_BUILD_SCRIPT_SHA=49f742ca3323b611ab62b225b5c01e1beb6af3e75ffd9b7191215e47f11d6207
G8_CSS="$G8_REPO/internal/notmuchbrowser/static/app.css"
G8_CSS_SHA=8c9eb34cd7cca700a05bdd07a3118a09950609f01d89d26f5dd1ad300531bb5d
G8_CSS_BYTES=25394
G8_PRODUCTION_BINARY=/home/atiq/.local/bin/notmuch-browser
G8_PRODUCTION_SHA=c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9
G8_CANDIDATE_SHA=5269c53393d96db1c3fe37f1160280ef9778fd3a7c795b1cf3db0a07c9c9649f
G8_CANDIDATE_BYTES=8147209
G8_CONFIG_SHA=50adc22cf114991e6b021fa0eefb91f10d636f34117c4c14c169bb09856446a7
G8_MARKER=/mail/AppData/notmuch-browser/source-enrollment/current-sources-acknowledged.env
G8_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G8_STARTED=no
G8_RETAIN=no
G8_PID=
G8_START_TICKS=

g8_die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

g8_equal() {
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

g8_pid_matches() {
  [[ -n "$G8_PID" && -d "/proc/$G8_PID" ]] || return 1
  [[ "$(readlink -f "/proc/$G8_PID/exe" 2>/dev/null || true)" == "$G8_BINARY" ]] ||
    return 1
  [[ "$(awk '{print $22}' "/proc/$G8_PID/stat" 2>/dev/null || true)" == "$G8_START_TICKS" ]]
}

g8_cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$rc" -ne 0 && "$G8_STARTED" == yes && "$G8_RETAIN" != yes ]]; then
    set +e
    if g8_pid_matches; then
      kill "$G8_PID" 2>/dev/null
      for _ in $(seq 1 100); do
        g8_pid_matches || break
        sleep 0.1
      done
    fi
    printf 'failed_candidate_process_alive=%s\n' \
      "$(g8_pid_matches && printf yes || printf no)"
    printf 'failed_candidate_port_8876_listeners=%s\n' \
      "$(ss -H -ltnp 'sport = :8876' | wc -l | tr -d ' ')"
    printf '%s\n' failed_candidate_files_preserved=yes
  fi
  exit "$rc"
}
trap g8_cleanup EXIT

g8_health_to_safe_lines() {
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

printf '%s\n' 'gate=11-responsive-result-layout-candidate-clean-build-and-isolated-validation'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_public_source_labels_and_statuses_only'
printf '%s\n' 'authorized_production_change=no'
printf '%s\n' 'authorized_candidate_build_and_isolated_start=yes'
printf '%s\n' 'authorized_mail_tag_index_config_mutation=no'

for tool in git bash sh go python3 find stat sha256sum curl ss awk sed grep sort wc tr \
  readlink nohup install date seq notmuch paste mktemp mv chmod env sleep; do
  command -v "$tool" >/dev/null 2>&1 || g8_die "missing required command: $tool"
done
[[ -x /home/atiq/.bun/bin/bun ]] || g8_die "pinned Bun executable is missing"

cd "$G8_REPO"
g8_equal repository_commit "$(git rev-parse HEAD)" "$G8_COMMIT"
g8_equal repository_branch "$(git branch --show-current)" "$G8_BRANCH"
g8_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G8_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g8_die "repository is not clean"
printf '%s\n' repository_clean_before=yes
g8_equal gate_10_batch_sha256 \
  "$(sha256sum "$G8_GATE10_BATCH" | awk '{print $1}')" "$G8_GATE10_BATCH_SHA"
g8_equal gate_10_log_sha256 \
  "$(sha256sum "$G8_GATE10_LOG" | awk '{print $1}')" "$G8_GATE10_LOG_SHA"
g8_equal gate_10_record_sha256 \
  "$(sha256sum "$G8_GATE10_RECORD" | awk '{print $1}')" "$G8_GATE10_RECORD_SHA"
grep -Fqx result=success "$G8_GATE10_RECORD" || g8_die "Gate 10 result is not success"
grep -Fqx privacy_review=automated_and_manual_review_passed "$G8_GATE10_RECORD" ||
  g8_die "Gate 10 privacy review is incomplete"
g8_equal gate_10_pointer_sha256 \
  "$(sha256sum "$G8_GATE10_POINTER" | awk '{print $1}')" "$G8_GATE10_POINTER_SHA"
printf '%s\n' gate_10_success_evidence_and_stale_pointer=verified
g8_equal gate_09_batch_sha256 \
  "$(sha256sum "$G8_GATE9_BATCH" | awk '{print $1}')" "$G8_GATE9_BATCH_SHA"
g8_equal gate_09_log_sha256 \
  "$(sha256sum "$G8_GATE9_LOG" | awk '{print $1}')" "$G8_GATE9_LOG_SHA"
g8_equal gate_09_record_sha256 \
  "$(sha256sum "$G8_GATE9_RECORD" | awk '{print $1}')" "$G8_GATE9_RECORD_SHA"
grep -Fqx result=failed "$G8_GATE9_RECORD" || g8_die "Gate 09 result is not failed"
grep -Fqx privacy_review=automated_and_manual_review_passed "$G8_GATE9_RECORD" ||
  g8_die "Gate 09 privacy review is incomplete"
printf '%s\n' gate_09_failed_evidence=verified
g8_equal gate_08_batch_sha256 \
  "$(sha256sum "$G8_GATE8_BATCH" | awk '{print $1}')" "$G8_GATE8_BATCH_SHA"
g8_equal gate_08_log_sha256 \
  "$(sha256sum "$G8_GATE8_LOG" | awk '{print $1}')" "$G8_GATE8_LOG_SHA"
g8_equal gate_08_record_sha256 \
  "$(sha256sum "$G8_GATE8_RECORD" | awk '{print $1}')" "$G8_GATE8_RECORD_SHA"
grep -Fqx result=failed "$G8_GATE8_RECORD" || g8_die "Gate 08 result is not failed"
grep -Fqx privacy_review=automated_and_manual_review_passed "$G8_GATE8_RECORD" ||
  g8_die "Gate 08 privacy review is incomplete"
printf '%s\n' gate_08_failed_evidence=verified
g8_equal gate_07_batch_sha256 \
  "$(sha256sum "$G8_GATE7_BATCH" | awk '{print $1}')" "$G8_GATE7_BATCH_SHA"
g8_equal gate_07_log_sha256 \
  "$(sha256sum "$G8_GATE7_LOG" | awk '{print $1}')" "$G8_GATE7_LOG_SHA"
g8_equal gate_07_record_sha256 \
  "$(sha256sum "$G8_GATE7_RECORD" | awk '{print $1}')" "$G8_GATE7_RECORD_SHA"
grep -Fqx result=success "$G8_GATE7_RECORD" || g8_die "Gate 07 result is not success"
grep -Fqx privacy_review=automated_and_manual_review_passed "$G8_GATE7_RECORD" ||
  g8_die "Gate 07 privacy review is incomplete"
printf '%s\n' gate_07_evidence=verified
g8_equal build_script_sha256 \
  "$(sha256sum "$G8_BUILD_SCRIPT" | awk '{print $1}')" "$G8_BUILD_SCRIPT_SHA"
g8_equal responsive_css_sha256 \
  "$(sha256sum "$G8_CSS" | awk '{print $1}')" "$G8_CSS_SHA"
g8_equal responsive_css_bytes "$(wc -c < "$G8_CSS" | tr -d ' ')" "$G8_CSS_BYTES"
g8_equal production_binary_sha256 \
  "$(sha256sum "$G8_PRODUCTION_BINARY" | awk '{print $1}')" "$G8_PRODUCTION_SHA"
g8_equal config_sha256 "$(sha256sum "$G8_CONFIG" | awk '{print $1}')" "$G8_CONFIG_SHA"
g8_equal marker_sha256 "$(sha256sum "$G8_MARKER" | awk '{print $1}')" "$G8_MARKER_SHA"
g8_equal final_new_ignore \
  "$(notmuch --config="$G8_CONFIG" config get new.ignore | paste -sd' ' -)" \
  betterbird-post-main-archive-maildirpp-20260704-205827

[[ ! -e "$G8_POINTER" ]] || g8_die "multi-source candidate pointer already exists"
[[ ! -e "$G8_CANDIDATE_ROOT" ]] || g8_die "responsive-layout candidate root already exists"
g8_equal port_8876_listeners_before "$(ss -H -ltnp 'sport = :8876' | wc -l | tr -d ' ')" 0
g8_equal production_port_8765_listener_count \
  "$(ss -H -ltnp 'sport = :8765' | awk '$4 == "127.0.0.1:8765" {count++} END {print count+0}')" 1
G8_PRODUCTION_HEALTH_BEFORE=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8765/healthz)
g8_health_to_safe_lines production_before "$G8_PRODUCTION_HEALTH_BEFORE"
[[ ! -e /mail/AppData/isync/provider-live-loop/lock ]] ||
  g8_die "mbsync lock is active"
[[ ! -e /mail/AppData/notmuch-browser/index-refresh.lock ]] ||
  g8_die "index refresh lock is active"
printf '%s\n' preflight_locks=absent

G8_STAMP=$(date +%Y%m%d-%H%M%S)
G8_RUN_DIR="$G8_CANDIDATE_ROOT/$G8_STAMP"
G8_BINARY="$G8_RUN_DIR/notmuch-browser"
G8_TEMP="$G8_RUN_DIR/download-tmp"
G8_EVIDENCE="$G8_RUN_DIR/http-evidence"
G8_LOG="$G8_LOG_ROOT/candidate-$G8_STAMP.log"
[[ ! -e "$G8_RUN_DIR" ]] || g8_die "timestamped candidate run directory already exists"
install -d -m 700 "$G8_RUN_DIR" "$G8_TEMP" "$G8_EVIDENCE" "$G8_LOG_ROOT"
chmod 700 "$G8_CANDIDATE_ROOT"
g8_equal candidate_root_mode "$(stat -c '%a' "$G8_CANDIDATE_ROOT")" 700

printf '%s\n' clean_build=begin
BUN_BIN=/home/atiq/.bun/bin/bun \
NOTMUCH_BROWSER_BUILD_OUTPUT="$G8_BINARY" \
  "$G8_BUILD_SCRIPT" all
printf '%s\n' clean_build=complete
g8_equal candidate_binary_sha256 \
  "$(sha256sum "$G8_BINARY" | awk '{print $1}')" "$G8_CANDIDATE_SHA"
g8_equal candidate_binary_bytes "$(wc -c < "$G8_BINARY" | tr -d ' ')" "$G8_CANDIDATE_BYTES"
g8_equal candidate_binary_mode "$(stat -c '%a' "$G8_BINARY")" 755
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g8_die "clean build changed tracked repository files"
printf '%s\n' repository_clean_after_build=yes

nohup env \
  NOTMUCH_BROWSER_ADDR=127.0.0.1:8876 \
  NOTMUCH_BROWSER_CONFIG="$G8_CONFIG" \
  NOTMUCH_BROWSER_DOWNLOAD_TMP="$G8_TEMP" \
  "$G8_BINARY" \
    --addr 127.0.0.1:8876 \
    --config "$G8_CONFIG" \
    --download-tmp "$G8_TEMP" \
  > "$G8_LOG" 2>&1 &
G8_PID=$!
chmod 600 "$G8_LOG"
G8_STARTED=yes
for _ in $(seq 1 100); do
  [[ -r "/proc/$G8_PID/stat" ]] && break
  sleep 0.1
done
[[ -r "/proc/$G8_PID/stat" ]] || g8_die "candidate process did not start"
G8_START_TICKS=$(awk '{print $22}' "/proc/$G8_PID/stat")
g8_pid_matches || g8_die "candidate process identity mismatch"

G8_CANDIDATE_HEALTH=
for _ in $(seq 1 60); do
  if G8_CANDIDATE_HEALTH=$(curl --silent --show-error --fail --max-time 5 \
    http://127.0.0.1:8876/healthz 2>/dev/null); then
    break
  fi
  sleep 1
done
[[ -n "$G8_CANDIDATE_HEALTH" ]] || g8_die "candidate health did not become ready"
g8_health_to_safe_lines candidate "$G8_CANDIDATE_HEALTH"
g8_equal candidate_port_8876_listener_count \
  "$(ss -H -ltnp 'sport = :8876' | awk '$4 == "127.0.0.1:8876" {count++} END {print count+0}')" 1
g8_equal candidate_executable "$(readlink -f "/proc/$G8_PID/exe")" "$G8_BINARY"
printf 'candidate_pid=%s\n' "$G8_PID"
printf 'candidate_start_ticks=%s\n' "$G8_START_TICKS"
printf 'candidate_boot_id=%s\n' "$(sed -n '1p' /proc/sys/kernel/random/boot_id)"
printf 'candidate_log_sha256_at_ready=%s\n' "$(sha256sum "$G8_LOG" | awk '{print $1}')"
grep -Fqx notmuch_browser_url=http://127.0.0.1:8876/ "$G8_LOG" ||
  g8_die "candidate startup URL marker is missing"
grep -Fqx viewer_mode=single_email_go "$G8_LOG" ||
  g8_die "candidate viewer-mode marker is missing"
grep -Fqx read_only=yes "$G8_LOG" ||
  g8_die "candidate read-only marker is missing"

curl --silent --show-error --fail --max-time 20 \
  --output "$G8_EVIDENCE/app.css" \
  http://127.0.0.1:8876/static/app.css
g8_equal candidate_served_css_sha256 \
  "$(sha256sum "$G8_EVIDENCE/app.css" | awk '{print $1}')" "$G8_CSS_SHA"
g8_equal candidate_served_css_bytes \
  "$(wc -c < "$G8_EVIDENCE/app.css" | tr -d ' ')" "$G8_CSS_BYTES"

curl --silent --show-error --fail --max-time 120 \
  --dump-header "$G8_EVIDENCE/root.headers" \
  --output "$G8_EVIDENCE/root.html" \
  'http://127.0.0.1:8876/?q=%2A&folder=all'
for spec in \
  'provider-live|mbsync/provider-live|nonempty' \
  'provider-inbox-test|mbsync/provider-inbox-test|nonempty' \
  'local-maildir|evolution/local-maildir|nonempty' \
  'betterbird-delta|evolution/betterbird-delta-maildirpp-20260704|nonempty' \
  'provider-live-archive|evolution/provider-live-archive|empty' \
  'test-maildir|evolution/test-maildir|nonempty'; do
  IFS='|' read -r slug folder expectation <<< "$spec"
  curl --silent --show-error --fail --max-time 120 \
    --header 'HX-Request: true' \
    --get \
    --data-urlencode 'q=*' \
    --data-urlencode "folder=$folder" \
    --data-urlencode 'limit=5' \
    --dump-header "$G8_EVIDENCE/$slug.headers" \
    --output "$G8_EVIDENCE/$slug.html" \
    http://127.0.0.1:8876/search
  printf 'saved_private_source_response=%s:%s\n' \
    "$slug" "$(sha256sum "$G8_EVIDENCE/$slug.html" | awk '{print $1}')"
done
curl --silent --show-error --fail --max-time 120 \
  --get \
  --data-urlencode 'q=*' \
  --data-urlencode 'folder=../private' \
  --output "$G8_EVIDENCE/invalid-folder.html" \
  http://127.0.0.1:8876/search

python3 - "$G8_EVIDENCE" <<'PY'
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
        self.ids = []
        self.text = []
        self._time = None
        self._path = None

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
        if tag == "span" and "path" in classes:
            self._path = []

    def handle_endtag(self, tag):
        if tag == "time" and self._time is not None:
            self.time_texts.append("".join(self._time).strip())
            self._time = None
        if tag == "span" and self._path is not None:
            self.ids.append("".join(self._path).strip())
            self._path = None

    def handle_data(self, data):
        self.text.append(data)
        if self._time is not None:
            self._time.append(data)
        if self._path is not None:
            self._path.append(data)


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
if len(page.groups) != 6:
    raise SystemExit("status=blocked\nreason=expected six approved source groups")
if page.rows < 1:
    raise SystemExit("status=blocked\nreason=All Mail returned no result rows")
print(f"root_folder_option_count={len(page.options)}")
print("root_approved_source_groups=6")
print(f"root_result_rows={page.rows}")

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
            raise SystemExit(f"status=blocked\nreason={slug} result row count is invalid")
        if expectation == "exact-four" and parsed.rows != 4:
            raise SystemExit(
                f"status=blocked\nreason={slug} did not return all four indexed messages"
            )
        if len(parsed.ids) != parsed.rows or len(set(parsed.ids)) != parsed.rows:
            raise SystemExit(f"status=blocked\nreason={slug} logical-message uniqueness failed")
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
        "newest_first=yes:unique_messages=yes:date_contract=yes"
    )

invalid = (root / "invalid-folder.html").read_text(encoding="utf-8")
if "Unknown mail folder selection." not in invalid:
    raise SystemExit("status=blocked\nreason=invalid folder was not rejected")
print("invalid_folder_rejected=yes")
PY

for header in \
  'content-security-policy:' \
  'cache-control: private, no-store' \
  'x-content-type-options: nosniff' \
  'referrer-policy: no-referrer'; do
  grep -Fqi "$header" "$G8_EVIDENCE/root.headers" ||
    g8_die "candidate root is missing security header: $header"
done
printf '%s\n' candidate_security_headers=pass
g8_equal candidate_static_css_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    http://127.0.0.1:8876/static/app.css)" 200
g8_equal candidate_static_js_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    http://127.0.0.1:8876/static/app.js)" 200
g8_equal candidate_status_route_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 60 \
    http://127.0.0.1:8876/status)" 200
g8_equal candidate_post_search_status \
  "$(curl --silent --request POST --output /dev/null --write-out '%{http_code}' \
    --max-time 20 http://127.0.0.1:8876/search)" 405
g8_equal candidate_download_temp_files \
  "$(find "$G8_TEMP" -maxdepth 1 -type f -print | wc -l | tr -d ' ')" 0

G8_PRODUCTION_HEALTH_AFTER=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8765/healthz)
g8_health_to_safe_lines production_after "$G8_PRODUCTION_HEALTH_AFTER"
g8_equal production_binary_sha256_after \
  "$(sha256sum "$G8_PRODUCTION_BINARY" | awk '{print $1}')" "$G8_PRODUCTION_SHA"
g8_equal production_port_8765_listener_count_after \
  "$(ss -H -ltnp 'sport = :8765' | awk '$4 == "127.0.0.1:8765" {count++} END {print count+0}')" 1
g8_pid_matches || g8_die "candidate identity changed during validation"

G8_POINTER_TMP=$(mktemp "$G8_STATE_ROOT/.multisource-candidate.XXXXXX")
{
  printf 'schema_version=1\n'
  printf 'status=retained_for_gui_review\n'
  printf 'repository_commit=%s\n' "$G8_COMMIT"
  printf 'binary=%s\n' "$G8_BINARY"
  printf 'binary_sha256=%s\n' "$G8_CANDIDATE_SHA"
  printf 'binary_bytes=%s\n' "$G8_CANDIDATE_BYTES"
  printf 'pid=%s\n' "$G8_PID"
  printf 'start_ticks=%s\n' "$G8_START_TICKS"
  printf 'boot_id=%s\n' "$(sed -n '1p' /proc/sys/kernel/random/boot_id)"
  printf 'addr=127.0.0.1:8876\n'
  printf 'log=%s\n' "$G8_LOG"
  printf 'download_tmp=%s\n' "$G8_TEMP"
  printf 'http_evidence=%s\n' "$G8_EVIDENCE"
  printf 'created_at=%s\n' "$(date --iso-8601=ns)"
} > "$G8_POINTER_TMP"
chmod 600 "$G8_POINTER_TMP"
mv "$G8_POINTER_TMP" "$G8_POINTER"
printf 'candidate_pointer=%s\n' "$G8_POINTER"
printf 'candidate_pointer_sha256=%s\n' "$(sha256sum "$G8_POINTER" | awk '{print $1}')"
printf 'candidate_pointer_mode=%s\n' "$(stat -c '%a' "$G8_POINTER")"
printf 'candidate_http_evidence_files=%s\n' \
  "$(find "$G8_EVIDENCE" -maxdepth 1 -type f -print | wc -l | tr -d ' ')"
(
  cd "$G8_EVIDENCE"
  find . -type f -printf '%P\n' |
    LC_ALL=C sort |
    while IFS= read -r file; do sha256sum "$file"; done |
    sha256sum |
    awk '{print "candidate_http_evidence_manifest_sha256=" $1}'
)
G8_RETAIN=yes
printf '%s\n' candidate_retained_for_gui_review=yes
printf '%s\n' production_changed=no
printf '%s\n' mail_tag_index_config_mutation_by_gate=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_11_responsive_result_layout_candidate_clean_build_and_isolated_validation_pass
