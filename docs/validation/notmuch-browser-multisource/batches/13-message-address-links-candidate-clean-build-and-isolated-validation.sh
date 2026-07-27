#!/bin/bash
set -Eeuo pipefail

umask 077

# Gate 13: bind the reboot-stale Gate 12 evidence, clean-build the exact
# address-link source, validate it only on localhost:8876, and retain it for
# antiX and Windows GUI review. Real addresses and Message-IDs stay only in
# private mode-700 HTTP evidence and are never printed to the operator log.
G13_REPO=/home/atiq/orca/workspaces/codex_antix/branch-codex
G13_COMMIT=86cc59bd24f1265b06764053a196a0a411a64bcb
G13_BRANCH=atiqte/branch-codex
G13_CONFIG=/home/atiq/.config/notmuch/default/config
G13_STATE_ROOT=/mail/AppData/notmuch-browser
G13_CANDIDATE_ROOT="$G13_STATE_ROOT/multisource-address-links-candidate"
G13_POINTER="$G13_STATE_ROOT/multisource-address-links-candidate-current.env"
G13_LOG_ROOT=/mail/Logs/notmuch-browser/multisource-address-links-candidate
G13_BUILD_SCRIPT="$G13_REPO/scripts/notmuch_browser_build.sh"
G13_GATE12_BATCH="$G13_REPO/docs/validation/notmuch-browser-multisource/batches/12-sticky-sidebar-candidate-clean-build-and-isolated-validation.sh"
G13_GATE12_LOG="$G13_REPO/docs/validation/notmuch-browser-multisource/logs/12-sticky-sidebar-candidate-clean-build-and-isolated-validation.log"
G13_GATE12_RECORD="$G13_REPO/docs/validation/notmuch-browser-multisource/records/12-sticky-sidebar-candidate-clean-build-and-isolated-validation.env"
G13_GATE12_POINTER="$G13_STATE_ROOT/multisource-sticky-sidebar-candidate-current.env"
G13_GATE12_BATCH_SHA=6976acdf0313b8de3259670652bbc33b1e6eb3b6010073ad181148db706fafce
G13_GATE12_LOG_SHA=0d90892ac8d28fd95098eda3e25ce947901ed178b144b9b91f738580367dc5f2
G13_GATE12_RECORD_SHA=fcd18fb7240bcc47eb032c88d0b49f773e078b4a2a3ecd78c26ae6ed177d9933
G13_GATE12_POINTER_SHA=ccfc729599de8cf404e12d9133256c98ffdf0525dd7346bf9f9b7af63daa6ede
G13_GATE12_COMMIT=532c783324fbb02de83da807b766b2de360214fd
G13_GATE12_CANDIDATE_SHA=4f33c40777b3dc49abdecb59775c8b8aa4d207dd7933349766edae4d7e5bc105
G13_BUILD_SCRIPT_SHA=49f742ca3323b611ab62b225b5c01e1beb6af3e75ffd9b7191215e47f11d6207
G13_CSS="$G13_REPO/internal/notmuchbrowser/static/app.css"
G13_CSS_SHA=26d2dbb4338b1379f09620d142b69911bf4affb35da6caa721ccb3385b98a90a
G13_CSS_BYTES=25774
G13_PRODUCTION_BINARY=/home/atiq/.local/bin/notmuch-browser
G13_PRODUCTION_SHA=c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9
G13_CANDIDATE_SHA=b37b3b633188e5c1c9c34b6dbb9c58f5e2c391982437ded6f0d7efeecf68ed5b
G13_CANDIDATE_BYTES=8188169
G13_CONFIG_SHA=50adc22cf114991e6b021fa0eefb91f10d636f34117c4c14c169bb09856446a7
G13_MARKER=/mail/AppData/notmuch-browser/source-enrollment/current-sources-acknowledged.env
G13_MARKER_SHA=e17e3b4510a872fe6a4f733ac29f12f5a3d2d80eea65f60d9b80e1934078e914
G13_STARTED=no
G13_RETAIN=no
G13_PID=
G13_START_TICKS=

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

g13_pid_matches() {
  [[ -n "$G13_PID" && -d "/proc/$G13_PID" ]] || return 1
  [[ "$(readlink -f "/proc/$G13_PID/exe" 2>/dev/null || true)" == "$G13_BINARY" ]] ||
    return 1
  [[ "$(awk '{print $22}' "/proc/$G13_PID/stat" 2>/dev/null || true)" == "$G13_START_TICKS" ]]
}

g13_cleanup() {
  local rc=$?
  trap - EXIT
  if [[ "$rc" -ne 0 && "$G13_STARTED" == yes && "$G13_RETAIN" != yes ]]; then
    set +e
    if g13_pid_matches; then
      kill "$G13_PID" 2>/dev/null
      for _ in $(seq 1 100); do
        g13_pid_matches || break
        sleep 0.1
      done
    fi
    printf 'failed_candidate_process_alive=%s\n' \
      "$(g13_pid_matches && printf yes || printf no)"
    printf 'failed_candidate_port_8876_listeners=%s\n' \
      "$(ss -H -ltnp 'sport = :8876' | wc -l | tr -d ' ')"
    printf '%s\n' failed_candidate_files_preserved=yes
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
    ".message-address-entry .mini-copy-button{margin-left:2px",
):
    if required not in css:
        raise SystemExit("status=blocked\nreason=address wrapping CSS contract failed")
print("desktop_sidebar_position=sticky")
print("desktop_sidebar_height=100dvh")
print("mobile_sidebar_position=fixed")
print("message_address_wrapping_css=pass")
PY
}

printf '%s\n' 'gate=13-message-address-links-candidate-clean-build-and-isolated-validation'
printf 'gate_started=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' 'privacy_contract=counts_hashes_public_source_labels_and_statuses_only'
printf '%s\n' 'authorized_production_change=no'
printf '%s\n' 'authorized_candidate_build_and_isolated_start=yes'
printf '%s\n' 'authorized_mail_tag_index_config_mutation=no'

for tool in git bash sh go python3 find stat sha256sum curl ss awk sed grep sort wc tr \
  readlink nohup install date seq notmuch paste mktemp mv chmod env sleep; do
  command -v "$tool" >/dev/null 2>&1 || g13_die "missing required command: $tool"
done
[[ -x /home/atiq/.bun/bin/bun ]] || g13_die "pinned Bun executable is missing"

cd "$G13_REPO"
g13_equal repository_commit "$(git rev-parse HEAD)" "$G13_COMMIT"
g13_equal repository_branch "$(git branch --show-current)" "$G13_BRANCH"
g13_equal upstream_commit "$(git rev-parse '@{upstream}')" "$G13_COMMIT"
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g13_die "repository is not clean"
printf '%s\n' repository_clean_before=yes

g13_equal gate_12_batch_sha256 \
  "$(sha256sum "$G13_GATE12_BATCH" | awk '{print $1}')" "$G13_GATE12_BATCH_SHA"
g13_equal gate_12_log_sha256 \
  "$(sha256sum "$G13_GATE12_LOG" | awk '{print $1}')" "$G13_GATE12_LOG_SHA"
g13_equal gate_12_record_sha256 \
  "$(sha256sum "$G13_GATE12_RECORD" | awk '{print $1}')" "$G13_GATE12_RECORD_SHA"
grep -Fqx result=success "$G13_GATE12_RECORD" ||
  g13_die "Gate 12 result is not success"
grep -Fqx privacy_review=automated_and_manual_passed "$G13_GATE12_RECORD" ||
  g13_die "Gate 12 privacy review is incomplete"
g13_equal gate_12_pointer_sha256 \
  "$(sha256sum "$G13_GATE12_POINTER" | awk '{print $1}')" "$G13_GATE12_POINTER_SHA"
g13_equal gate_12_pointer_mode "$(stat -c '%a' "$G13_GATE12_POINTER")" 600
g13_equal gate_12_pointer_status \
  "$(g13_pointer_value "$G13_GATE12_POINTER" status)" retained_for_gui_review
g13_equal gate_12_pointer_commit \
  "$(g13_pointer_value "$G13_GATE12_POINTER" repository_commit)" "$G13_GATE12_COMMIT"
g13_equal gate_12_pointer_addr \
  "$(g13_pointer_value "$G13_GATE12_POINTER" addr)" 127.0.0.1:8876
g13_equal gate_12_pointer_binary_sha256 \
  "$(g13_pointer_value "$G13_GATE12_POINTER" binary_sha256)" "$G13_GATE12_CANDIDATE_SHA"
G13_GATE12_BINARY=$(g13_pointer_value "$G13_GATE12_POINTER" binary)
[[ -f "$G13_GATE12_BINARY" ]] || g13_die "Gate 12 candidate binary is missing"
g13_equal gate_12_binary_sha256 \
  "$(sha256sum "$G13_GATE12_BINARY" | awk '{print $1}')" "$G13_GATE12_CANDIDATE_SHA"
G13_CURRENT_BOOT_ID=$(sed -n '1p' /proc/sys/kernel/random/boot_id)
G13_GATE12_BOOT_ID=$(g13_pointer_value "$G13_GATE12_POINTER" boot_id)
[[ "$G13_CURRENT_BOOT_ID" != "$G13_GATE12_BOOT_ID" ]] ||
  g13_die "Gate 12 pointer is not from an older boot"
printf '%s\n' gate_12_accepted_evidence=verified
printf '%s\n' gate_12_pointer_boot_state=stale_after_reboot
g13_equal gate_12_stale_pointer_port_8876_listeners \
  "$(ss -H -ltnp 'sport = :8876' | wc -l | tr -d ' ')" 0
printf '%s\n' gate_12_files_and_pointer_preserved=yes

g13_equal build_script_sha256 \
  "$(sha256sum "$G13_BUILD_SCRIPT" | awk '{print $1}')" "$G13_BUILD_SCRIPT_SHA"
g13_equal address_link_css_sha256 \
  "$(sha256sum "$G13_CSS" | awk '{print $1}')" "$G13_CSS_SHA"
g13_equal address_link_css_bytes "$(wc -c < "$G13_CSS" | tr -d ' ')" "$G13_CSS_BYTES"
g13_validate_css "$G13_CSS"
g13_equal production_binary_sha256 \
  "$(sha256sum "$G13_PRODUCTION_BINARY" | awk '{print $1}')" "$G13_PRODUCTION_SHA"
g13_equal config_sha256 "$(sha256sum "$G13_CONFIG" | awk '{print $1}')" "$G13_CONFIG_SHA"
g13_equal marker_sha256 "$(sha256sum "$G13_MARKER" | awk '{print $1}')" "$G13_MARKER_SHA"
g13_equal final_new_ignore \
  "$(notmuch --config="$G13_CONFIG" config get new.ignore | paste -sd' ' -)" \
  betterbird-post-main-archive-maildirpp-20260704-205827

[[ ! -e "$G13_POINTER" ]] || g13_die "Gate 13 candidate pointer already exists"
[[ ! -e "$G13_CANDIDATE_ROOT" ]] || g13_die "Gate 13 candidate root already exists"
g13_equal port_8876_listeners_before \
  "$(ss -H -ltnp 'sport = :8876' | wc -l | tr -d ' ')" 0
g13_equal production_port_8765_listener_count \
  "$(ss -H -ltnp 'sport = :8765' | awk '$4 == "127.0.0.1:8765" {count++} END {print count+0}')" 1
G13_PRODUCTION_HEALTH_BEFORE=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8765/healthz)
g13_health_to_safe_lines production_before "$G13_PRODUCTION_HEALTH_BEFORE"
[[ ! -e /mail/AppData/isync/provider-live-loop/lock ]] ||
  g13_die "mbsync lock is active"
[[ ! -e /mail/AppData/notmuch-browser/index-refresh.lock ]] ||
  g13_die "index refresh lock is active"
printf '%s\n' preflight_locks=absent

G13_STAMP=$(date +%Y%m%d-%H%M%S)
G13_RUN_DIR="$G13_CANDIDATE_ROOT/$G13_STAMP"
G13_BINARY="$G13_RUN_DIR/notmuch-browser"
G13_TEMP="$G13_RUN_DIR/download-tmp"
G13_EVIDENCE="$G13_RUN_DIR/http-evidence"
G13_LOG="$G13_LOG_ROOT/candidate-$G13_STAMP.log"
install -d -m 700 "$G13_RUN_DIR" "$G13_TEMP" "$G13_EVIDENCE" "$G13_LOG_ROOT"
chmod 700 "$G13_CANDIDATE_ROOT"
g13_equal candidate_root_mode "$(stat -c '%a' "$G13_CANDIDATE_ROOT")" 700

printf '%s\n' clean_build=begin
BUN_BIN=/home/atiq/.bun/bin/bun \
NOTMUCH_BROWSER_BUILD_OUTPUT="$G13_BINARY" \
  "$G13_BUILD_SCRIPT" all
printf '%s\n' clean_build=complete
g13_equal candidate_binary_sha256 \
  "$(sha256sum "$G13_BINARY" | awk '{print $1}')" "$G13_CANDIDATE_SHA"
g13_equal candidate_binary_bytes "$(wc -c < "$G13_BINARY" | tr -d ' ')" "$G13_CANDIDATE_BYTES"
g13_equal candidate_binary_mode "$(stat -c '%a' "$G13_BINARY")" 755
[[ -z "$(git status --porcelain --untracked-files=normal)" ]] ||
  g13_die "clean build changed tracked repository files"
printf '%s\n' repository_clean_after_build=yes

nohup env \
  NOTMUCH_BROWSER_ADDR=127.0.0.1:8876 \
  NOTMUCH_BROWSER_CONFIG="$G13_CONFIG" \
  NOTMUCH_BROWSER_DOWNLOAD_TMP="$G13_TEMP" \
  "$G13_BINARY" \
    --addr 127.0.0.1:8876 \
    --config "$G13_CONFIG" \
    --download-tmp "$G13_TEMP" \
  > "$G13_LOG" 2>&1 &
G13_PID=$!
chmod 600 "$G13_LOG"
G13_STARTED=yes
for _ in $(seq 1 100); do
  [[ -r "/proc/$G13_PID/stat" ]] && break
  sleep 0.1
done
[[ -r "/proc/$G13_PID/stat" ]] || g13_die "candidate process did not start"
G13_START_TICKS=$(awk '{print $22}' "/proc/$G13_PID/stat")
g13_pid_matches || g13_die "candidate process identity mismatch"

G13_CANDIDATE_HEALTH=
for _ in $(seq 1 60); do
  if G13_CANDIDATE_HEALTH=$(curl --silent --show-error --fail --max-time 5 \
    http://127.0.0.1:8876/healthz 2>/dev/null); then
    break
  fi
  sleep 1
done
[[ -n "$G13_CANDIDATE_HEALTH" ]] || g13_die "candidate health did not become ready"
g13_health_to_safe_lines candidate "$G13_CANDIDATE_HEALTH"
g13_equal candidate_port_8876_listener_count \
  "$(ss -H -ltnp 'sport = :8876' | awk '$4 == "127.0.0.1:8876" {count++} END {print count+0}')" 1
g13_equal candidate_executable "$(readlink -f "/proc/$G13_PID/exe")" "$G13_BINARY"
printf 'candidate_pid=%s\n' "$G13_PID"
printf 'candidate_start_ticks=%s\n' "$G13_START_TICKS"
printf 'candidate_boot_id=%s\n' "$G13_CURRENT_BOOT_ID"
grep -Fqx notmuch_browser_url=http://127.0.0.1:8876/ "$G13_LOG" ||
  g13_die "candidate startup URL marker is missing"
grep -Fqx viewer_mode=single_email_go "$G13_LOG" ||
  g13_die "candidate viewer-mode marker is missing"
grep -Fqx read_only=yes "$G13_LOG" ||
  g13_die "candidate read-only marker is missing"

curl --silent --show-error --fail --max-time 20 \
  --output "$G13_EVIDENCE/app.css" \
  http://127.0.0.1:8876/static/app.css
g13_equal candidate_served_css_sha256 \
  "$(sha256sum "$G13_EVIDENCE/app.css" | awk '{print $1}')" "$G13_CSS_SHA"
g13_equal candidate_served_css_bytes \
  "$(wc -c < "$G13_EVIDENCE/app.css" | tr -d ' ')" "$G13_CSS_BYTES"
g13_validate_css "$G13_EVIDENCE/app.css"

curl --silent --show-error --fail --max-time 120 \
  --dump-header "$G13_EVIDENCE/root.headers" \
  --output "$G13_EVIDENCE/root.html" \
  'http://127.0.0.1:8876/?q=%2A&folder=all'
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
    http://127.0.0.1:8876/search
  printf 'saved_private_source_response=%s:%s\n' \
    "$slug" "$(sha256sum "$G13_EVIDENCE/$slug.html" | awk '{print $1}')"
done
curl --silent --show-error --fail --max-time 120 \
  --get \
  --data-urlencode 'q=*' \
  --data-urlencode 'folder=../private' \
  --output "$G13_EVIDENCE/invalid-folder.html" \
  http://127.0.0.1:8876/search

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

G13_MESSAGE_URL=$(sed -n '1p' "$G13_EVIDENCE/message.url")
[[ "$G13_MESSAGE_URL" == /message\?* ]] ||
  g13_die "private message URL extraction failed"
curl --silent --show-error --fail --max-time 120 \
  --output "$G13_EVIDENCE/message.html" \
  "http://127.0.0.1:8876$G13_MESSAGE_URL"

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
print("message_address_from_to_labels=yes")
print("bcc_rendering_fixture_tested_by_clean_build=yes")
PY

for header in \
  'content-security-policy:' \
  'cache-control: private, no-store' \
  'x-content-type-options: nosniff' \
  'referrer-policy: no-referrer'; do
  grep -Fqi "$header" "$G13_EVIDENCE/root.headers" ||
    g13_die "candidate root is missing security header: $header"
done
printf '%s\n' candidate_security_headers=pass
g13_equal candidate_static_css_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    http://127.0.0.1:8876/static/app.css)" 200
g13_equal candidate_static_js_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 20 \
    http://127.0.0.1:8876/static/app.js)" 200
g13_equal candidate_status_route_status \
  "$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 60 \
    http://127.0.0.1:8876/status)" 200
g13_equal candidate_post_search_status \
  "$(curl --silent --request POST --output /dev/null --write-out '%{http_code}' \
    --max-time 20 http://127.0.0.1:8876/search)" 405
g13_equal candidate_download_temp_files \
  "$(find "$G13_TEMP" -maxdepth 1 -type f -print | wc -l | tr -d ' ')" 0

G13_PRODUCTION_HEALTH_AFTER=$(curl --silent --show-error --fail --max-time 10 \
  http://127.0.0.1:8765/healthz)
g13_health_to_safe_lines production_after "$G13_PRODUCTION_HEALTH_AFTER"
g13_equal production_binary_sha256_after \
  "$(sha256sum "$G13_PRODUCTION_BINARY" | awk '{print $1}')" "$G13_PRODUCTION_SHA"
g13_equal production_port_8765_listener_count_after \
  "$(ss -H -ltnp 'sport = :8765' | awk '$4 == "127.0.0.1:8765" {count++} END {print count+0}')" 1
g13_pid_matches || g13_die "candidate identity changed during validation"
[[ ! -e /mail/AppData/isync/provider-live-loop/lock ]] ||
  g13_die "mbsync lock appeared during validation"
[[ ! -e /mail/AppData/notmuch-browser/index-refresh.lock ]] ||
  g13_die "index refresh lock appeared during validation"
printf '%s\n' postflight_locks=absent

G13_POINTER_TMP=$(mktemp "$G13_STATE_ROOT/.multisource-address-links-candidate.XXXXXX")
{
  printf 'schema_version=1\n'
  printf 'status=retained_for_gui_review\n'
  printf 'repository_commit=%s\n' "$G13_COMMIT"
  printf 'binary=%s\n' "$G13_BINARY"
  printf 'binary_sha256=%s\n' "$G13_CANDIDATE_SHA"
  printf 'binary_bytes=%s\n' "$G13_CANDIDATE_BYTES"
  printf 'pid=%s\n' "$G13_PID"
  printf 'start_ticks=%s\n' "$G13_START_TICKS"
  printf 'boot_id=%s\n' "$G13_CURRENT_BOOT_ID"
  printf 'addr=127.0.0.1:8876\n'
  printf 'log=%s\n' "$G13_LOG"
  printf 'download_tmp=%s\n' "$G13_TEMP"
  printf 'http_evidence=%s\n' "$G13_EVIDENCE"
  printf 'created_at=%s\n' "$(date --iso-8601=ns)"
} > "$G13_POINTER_TMP"
chmod 600 "$G13_POINTER_TMP"
mv "$G13_POINTER_TMP" "$G13_POINTER"
printf 'candidate_pointer=%s\n' "$G13_POINTER"
printf 'candidate_pointer_sha256=%s\n' "$(sha256sum "$G13_POINTER" | awk '{print $1}')"
printf 'candidate_pointer_mode=%s\n' "$(stat -c '%a' "$G13_POINTER")"
printf 'candidate_http_evidence_files=%s\n' \
  "$(find "$G13_EVIDENCE" -maxdepth 1 -type f -print | wc -l | tr -d ' ')"
(
  cd "$G13_EVIDENCE"
  find . -type f -printf '%P\n' |
    LC_ALL=C sort |
    while IFS= read -r file; do sha256sum "$file"; done |
    sha256sum |
    awk '{print "candidate_http_evidence_manifest_sha256=" $1}'
)
G13_RETAIN=yes
printf '%s\n' candidate_retained_for_gui_review=yes
printf '%s\n' production_changed=no
printf '%s\n' mail_tag_index_config_mutation_by_gate=no
printf 'gate_finished=%s\n' "$(date --iso-8601=ns)"
printf '%s\n' status=gate_13_message_address_links_candidate_clean_build_and_isolated_validation_pass
