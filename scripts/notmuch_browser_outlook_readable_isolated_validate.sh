#!/bin/bash
set -euo pipefail

umask 077

readonly BUILD_POINTER="/mail/AppData/notmuch-browser/outlook-readable-build-current.json"
readonly BUILD_POINTER_SHA256="e088115d75e23620e36b2ca395bf6d55c3338ff28cde9513ce4f8fcc012fd6f7"
readonly ARCHIVE_SHA256="533235a5d16d43a504c7bd8e598127606076144b87c970e68f4fa7d0110a0e3c"
readonly BINARY_SHA256="e80fb11dc1e4dffe51e65f754ecd03ca94903a16f6294394f685c853bb0f5cd4"
readonly BINARY_SIZE="9769225"
readonly AUDIT_SHA256="fd78e9a022051fb49707ef1630dcb47cab116d5732988aa14fdaba1dda338c0b"
readonly PROD_BINARY="/home/atiq/.local/bin/notmuch-browser"
readonly PROD_CONTROL="/home/atiq/.local/bin/notmuch-browser-control"
readonly PROD_INDEX_CONTROL="/home/atiq/.local/bin/notmuch-browser-index-control"
readonly PROD_BINARY_SHA256="50e6b1adbcf32201496f6d6f5a3d53c060d0c39e1831ca1b5ecac3d48838f37e"
readonly PROD_CONTROL_SHA256="1b1277b0af3ab582ab307dd8763115ed754121c8a61643737888aa11d97b34b7"
readonly PROD_INDEX_CONTROL_SHA256="df07cd071d1976ea43b8c4c44655b60a179f9809a24995980bdf8e8958eae0b3"
readonly NOTMUCH_CONFIG="/home/atiq/.config/notmuch/default/config"
readonly PROD_TEMP="/mail/AppData/notmuch-browser/download-tmp"
readonly ISOLATED_POINTER="/mail/AppData/notmuch-browser/outlook-readable-isolated-current.json"
readonly MESSAGE_ID="552825156.202.1784038981529@MGPLMAPP01.mustang.de"
readonly CANDIDATE_BASE="http://127.0.0.1:8876"
readonly PRODUCTION_BASE="http://127.0.0.1:8765"

RUN="$HOME/codex-runs/notmuch-browser-outlook-readable-isolated-$(date +%Y%m%d-%H%M%S)"
SERVER_LOG="$RUN/server.log"
VALIDATION_LOG="$RUN/validation.log"
REPORT="$RUN/automated-report.json"
BUILD_ENV="$RUN/build.env"
ISOLATED_TEMP="/mail/AppData/notmuch-browser/outlook-readable-isolated-$(basename "$RUN")"
PID=""
PROCESS_START_TICKS=""
KEEP_CANDIDATE=0
POINTER_CREATED=0

mkdir -p "$HOME/codex-runs"
mkdir -m 700 "$RUN"

stop_exact_candidate() {
    if [ -z "$PID" ] || [ -z "$PROCESS_START_TICKS" ] || [ -z "${BINARY:-}" ]; then
        return
    fi
    if [ ! -r "/proc/$PID/stat" ]; then
        return
    fi
    current_exe=$(readlink "/proc/$PID/exe" 2>/dev/null || true)
    current_ticks=$(awk '{print $22}' "/proc/$PID/stat" 2>/dev/null || true)
    if [ "$current_exe" != "$BINARY" ] || [ "$current_ticks" != "$PROCESS_START_TICKS" ]; then
        echo "cleanup_signal_skipped=identity_mismatch" >&2
        return
    fi
    kill -TERM "$PID" 2>/dev/null || true
    for _ in $(seq 1 50); do
        if ! kill -0 "$PID" 2>/dev/null; then
            wait "$PID" 2>/dev/null || true
            return
        fi
        process_state=$(awk '{print $3}' "/proc/$PID/stat" 2>/dev/null || true)
        if [ "$process_state" = "Z" ]; then
            wait "$PID" 2>/dev/null || true
            return
        fi
        sleep 0.1
    done
    echo "cleanup_warning=candidate_did_not_stop_after_sigterm" >&2
}

on_exit() {
    rc=$?
    trap - EXIT HUP INT TERM
    if [ "$rc" -ne 0 ] && [ "$KEEP_CANDIDATE" -ne 1 ]; then
        stop_exact_candidate
        if [ -d "$ISOLATED_TEMP" ] && [ -z "$(find "$ISOLATED_TEMP" -mindepth 1 -print -quit 2>/dev/null)" ]; then
            rmdir "$ISOLATED_TEMP" 2>/dev/null || true
        fi
        if [ "$POINTER_CREATED" -eq 1 ]; then
            rm -f "$ISOLATED_POINTER"
        fi
        echo "failure_cleanup=attempted" >&2
        echo "failure_run=$RUN" >&2
        if [ -f "$SERVER_LOG" ]; then
            echo "== Candidate server log tail ==" >&2
            tail -n 40 "$SERVER_LOG" >&2 || true
        fi
    fi
    exit "$rc"
}

trap on_exit EXIT
trap 'exit 130' HUP INT TERM

require_empty_dir() {
    path=$1
    label=$2
    test -d "$path"
    if [ -n "$(find "$path" -mindepth 1 -print -quit)" ]; then
        echo "blocked: $label is not empty: $path" >&2
        exit 1
    fi
}

validate_health_file() {
    health_file=$1
    expected_addr=$2
    python3 - "$health_file" "$expected_addr" <<'PY'
import json
import sys

path, expected_addr = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)

expected = {
    "ok": True,
    "read_only": True,
    "mail_mutation": False,
    "downloads_enabled": True,
    "temporary_download_files": True,
    "viewer_mode": "single_email_go",
    "addr": expected_addr,
    "database_path": "/mail/SearchIndex/notmuch/default",
    "mail_root": "/mail/Mailstore",
}
for key, value in expected.items():
    if data.get(key) != value:
        raise SystemExit(f"blocked: health {key}={data.get(key)!r}, expected {value!r}")
for key in ("messages", "files"):
    if not isinstance(data.get(key), int) or data[key] < 0:
        raise SystemExit(f"blocked: invalid health {key}={data.get(key)!r}")
print("health_contract=PASS")
print(f"health_addr={data['addr']}")
print(f"health_messages={data['messages']}")
print(f"health_files={data['files']}")
PY
}

echo "== Outlook Readable isolated preflight =="
date --iso-8601=seconds

test ! -e "$ISOLATED_POINTER"
test "$(stat -c '%a' "$BUILD_POINTER")" = "600"
printf '%s  %s\n' "$BUILD_POINTER_SHA256" "$BUILD_POINTER" | sha256sum -c -

python3 - "$BUILD_POINTER" "$BUILD_ENV" <<'PY'
import json
import os
import shlex
import sys

pointer_path, output_path = sys.argv[1:]
with open(pointer_path, encoding="utf-8") as handle:
    data = json.load(handle)

expected = {
    "format": "notmuch-browser-outlook-readable-build-v1",
    "archive": "/home/atiq/notmuch-browser-outlook-readable-src-20260718-215557.tar.gz",
    "archive_sha256": "533235a5d16d43a504c7bd8e598127606076144b87c970e68f4fa7d0110a0e3c",
    "binary": "/home/atiq/codex-runs/notmuch-browser-outlook-readable-build-20260718-222714/notmuch-browser",
    "binary_sha256": "e80fb11dc1e4dffe51e65f754ecd03ca94903a16f6294394f685c853bb0f5cd4",
    "binary_size": 9769225,
    "audit_report": "/home/atiq/codex-runs/notmuch-browser-outlook-readable-build-20260718-222714/archive-audit.json",
    "audit_report_sha256": "fd78e9a022051fb49707ef1630dcb47cab116d5732988aa14fdaba1dda338c0b",
}
for key, value in expected.items():
    if data.get(key) != value:
        raise SystemExit(f"blocked: build pointer {key}={data.get(key)!r}, expected {value!r}")

values = {
    "ARCHIVE": data["archive"],
    "AUDIT_REPORT": data["audit_report"],
    "BINARY": data["binary"],
    "BUILD_RUN": data["run"],
}
fd = os.open(output_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    for key, value in values.items():
        handle.write(f"{key}={shlex.quote(value)}\n")
PY

# shellcheck disable=SC1090
. "$BUILD_ENV"

test "$(stat -c '%a' "$ARCHIVE")" = "600"
test "$(stat -c '%a' "$AUDIT_REPORT")" = "600"
test "$(stat -c '%a' "$BINARY")" = "700"
test "$(stat -c '%s' "$BINARY")" = "$BINARY_SIZE"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE" | sha256sum -c -
printf '%s  %s\n' "$AUDIT_SHA256" "$AUDIT_REPORT" | sha256sum -c -
printf '%s  %s\n' "$BINARY_SHA256" "$BINARY" | sha256sum -c -

for process_dir in /proc/[0-9]*; do
    if [ -e "$process_dir/exe" ] && [ "$(readlink "$process_dir/exe" 2>/dev/null || true)" = "$BINARY" ]; then
        echo "blocked: candidate binary is already running as PID ${process_dir##*/}" >&2
        exit 1
    fi
done

port_8876_lines=$(ss -H -ltnp | awk '$4 ~ /:8876$/')
if [ -n "$port_8876_lines" ]; then
    echo "blocked: port 8876 is already in use" >&2
    printf '%s\n' "$port_8876_lines" >&2
    exit 1
fi

printf '%s  %s\n' "$PROD_BINARY_SHA256" "$PROD_BINARY" | sha256sum -c -
printf '%s  %s\n' "$PROD_CONTROL_SHA256" "$PROD_CONTROL" | sha256sum -c -
printf '%s  %s\n' "$PROD_INDEX_CONTROL_SHA256" "$PROD_INDEX_CONTROL" | sha256sum -c -

production_port_lines=$(ss -H -ltnp | awk '$4 ~ /:8765$/')
test "$(printf '%s\n' "$production_port_lines" | sed '/^$/d' | wc -l)" -eq 1
production_listener=$(printf '%s\n' "$production_port_lines" | awk '$4 == "127.0.0.1:8765"')
test "$(printf '%s\n' "$production_listener" | sed '/^$/d' | wc -l)" -eq 1

curl -fsS "$PRODUCTION_BASE/healthz" > "$RUN/production-health-before.json"
validate_health_file "$RUN/production-health-before.json" "127.0.0.1:8765"
require_empty_dir "$PROD_TEMP" "production download temp"

for family in "Aptos" "Iosevka SS14" "Inter Variable" "AporeticSansMonoNerdFont"; do
    resolved=$(fc-match -f '%{family}|%{style}|%{file}\n' "$family" | head -n 1)
    case "$resolved" in
        "$family"*) ;;
        *) echo "blocked: font did not resolve exactly: $family -> $resolved" >&2; exit 1 ;;
    esac
    printf 'font=%s\n' "$resolved"
done

mkdir -m 700 "$ISOLATED_TEMP"
: > "$SERVER_LOG"
chmod 600 "$SERVER_LOG"

echo "== Start exact isolated candidate =="
nohup "$BINARY" \
    --addr "127.0.0.1:8876" \
    --config "$NOTMUCH_CONFIG" \
    --download-tmp "$ISOLATED_TEMP" \
    > "$SERVER_LOG" 2>&1 < /dev/null &
PID=$!

for _ in $(seq 1 20); do
    if [ -r "/proc/$PID/stat" ]; then
        PROCESS_START_TICKS=$(awk '{print $22}' "/proc/$PID/stat")
        break
    fi
    sleep 0.05
done
test -n "$PROCESS_START_TICKS"

for _ in $(seq 1 80); do
    if curl -fsS "$CANDIDATE_BASE/healthz" > "$RUN/candidate-health-start.json" 2>/dev/null; then
        break
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "blocked: candidate exited during startup" >&2
        exit 1
    fi
    sleep 0.25
done

test -s "$RUN/candidate-health-start.json"
validate_health_file "$RUN/candidate-health-start.json" "127.0.0.1:8876"
test "$(readlink "/proc/$PID/exe")" = "$BINARY"
test "$(awk '{print $22}' "/proc/$PID/stat")" = "$PROCESS_START_TICKS"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id)
COMMAND_LINE=$(tr '\0' ' ' < "/proc/$PID/cmdline" | sed 's/ $//')

candidate_listener=$(ss -H -ltnp | awk '$4 == "127.0.0.1:8876"')
test "$(printf '%s\n' "$candidate_listener" | sed '/^$/d' | wc -l)" -eq 1
case "$candidate_listener" in
    *"pid=$PID,"*) ;;
    *) echo "blocked: 8876 listener does not belong to PID $PID" >&2; exit 1 ;;
esac

echo "candidate_pid=$PID"
echo "candidate_boot_id=$BOOT_ID"
echo "candidate_start_ticks=$PROCESS_START_TICKS"
echo "candidate_command=$COMMAND_LINE"
echo "candidate_listener=$candidate_listener"

echo "== Automated HTTP, display, attachment, and ten-CID validation =="
python3 - \
    "$CANDIDATE_BASE" \
    "$PRODUCTION_BASE" \
    "$MESSAGE_ID" \
    "$ISOLATED_TEMP" \
    "$PROD_TEMP" \
    "$REPORT" <<'PY' | tee "$VALIDATION_LOG"
from concurrent.futures import ThreadPoolExecutor, as_completed
from html.parser import HTMLParser
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlencode, urljoin, urlparse
from urllib.request import Request, urlopen
import hashlib
import json
import os
import re
import sys
import time

candidate_base, production_base, message_id, isolated_temp, production_temp, report_path = sys.argv[1:]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def fetch(url_or_path, *, base=candidate_base, method="GET", htmx=False, timeout=120):
    url = url_or_path if url_or_path.startswith("http://") else urljoin(base + "/", url_or_path.lstrip("/"))
    headers = {"User-Agent": "notmuch-browser-isolated-validator/1"}
    if htmx:
        headers["HX-Request"] = "true"
    request = Request(url, method=method, headers=headers)
    started = time.monotonic()
    try:
        with urlopen(request, timeout=timeout) as response:
            data = response.read()
            return response.status, {k.lower(): v for k, v in response.headers.items()}, data, time.monotonic() - started
    except HTTPError as error:
        data = error.read()
        return error.code, {k.lower(): v for k, v in error.headers.items()}, data, time.monotonic() - started


class MessageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.iframes = []
        self.links = []
        self.text = []
        self.active_depth = 0
        self.active_text = []
        self.row_depth = 0
        self.current_row = []
        self.attachment_rows = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        classes = set((values.get("class") or "").split())
        if tag == "iframe":
            self.iframes.append(values)
        if tag == "a" and values.get("href"):
            self.links.append(values)
        if "is-active" in classes:
            self.active_depth = 1
        elif self.active_depth:
            self.active_depth += 1
        if "attachment-row" in classes:
            self.row_depth = 1
            self.current_row = []
        elif self.row_depth:
            self.row_depth += 1

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag):
        if self.active_depth:
            self.active_depth -= 1
        if self.row_depth:
            self.row_depth -= 1
            if self.row_depth == 0:
                self.attachment_rows.append(" ".join(self.current_row))
                self.current_row = []

    def handle_data(self, data):
        value = " ".join(data.split())
        if not value:
            return
        self.text.append(value)
        if self.active_depth:
            self.active_text.append(value)
        if self.row_depth:
            self.current_row.append(value)


class SrcdocParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.csp_values = []
        self.ids = set()
        self.tags = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        values = {key.lower(): value for key, value in attrs}
        self.tags.append(tag)
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "meta" and (values.get("http-equiv") or "").lower() == "content-security-policy":
            self.csp_values.append(values.get("content") or "")

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)


def parse_message(body):
    parser = MessageParser()
    parser.feed(body.decode("utf-8", errors="strict"))
    parser.close()
    require(len(parser.iframes) == 1, f"expected one message iframe, found {len(parser.iframes)}")
    iframe = parser.iframes[0]
    require("sandbox" in iframe, "message iframe is missing sandbox")
    require(iframe.get("referrerpolicy") == "no-referrer", "message iframe referrer policy changed")
    require(iframe.get("srcdoc"), "message iframe srcdoc is empty")
    srcdoc = iframe["srcdoc"]
    inner = SrcdocParser()
    inner.feed(srcdoc)
    inner.close()
    require(len(inner.csp_values) == 1, f"expected one iframe CSP meta value, found {len(inner.csp_values)}")
    return parser, srcdoc, inner


def message_path(display, images, *, duplicate=0):
    values = {"id": message_id, "dup": str(duplicate), "display": display, "images": images}
    return "/message?" + urlencode(values)


def verify_outer_headers(label, headers):
    csp = headers.get("content-security-policy", "")
    require("default-src 'self'" in csp, f"{label}: outer CSP missing default-src")
    require("object-src 'none'" in csp, f"{label}: outer CSP missing object-src")
    require("frame-ancestors 'none'" in csp, f"{label}: outer CSP missing frame-ancestors")
    require(headers.get("x-content-type-options") == "nosniff", f"{label}: nosniff missing")
    require(headers.get("referrer-policy") == "no-referrer", f"{label}: referrer policy changed")


def inspect_message(label, display, requested_images, *, htmx, effective_images=None):
    if effective_images is None:
        effective_images = requested_images
    status, headers, body, elapsed = fetch(message_path(display, requested_images), htmx=htmx)
    require(status == 200, f"{label}: status {status}")
    verify_outer_headers(label, headers)
    if htmx:
        require("HX-Request" in headers.get("vary", ""), f"{label}: Vary lacks HX-Request")
    parser, srcdoc, inner = parse_message(body)
    frame_csp = inner.csp_values[0]
    visible = " ".join(parser.text)
    active = " ".join(parser.active_text)
    require(active == display.capitalize(), f"{label}: active display is {active!r}")
    require(len(parser.attachment_rows) == 1, f"{label}: expected one genuine attachment, found {len(parser.attachment_rows)}")
    require(".zip" in parser.attachment_rows[0].lower(), f"{label}: genuine ZIP attachment not found")
    zip_links = [link["href"] for link in parser.links if link.get("href", "").startswith("/attachments.zip?cap=")]
    require(len(zip_links) == 1, f"{label}: expected one Save All capability, found {len(zip_links)}")
    require("font-src 'none'" in frame_csp, f"{label}: iframe font-src changed")
    require("script-src 'none'" in frame_csp, f"{label}: iframe script-src changed")
    for forbidden_tag in ("script", "object", "embed", "iframe", "foreignobject"):
        require(forbidden_tag not in inner.tags, f"{label}: {forbidden_tag} element survived")
    office_readable_override = "notmuch-browser-office-readable" in inner.ids
    if display == "readable" and office_readable_override:
        require("font-size:10.5pt!important" in srcdoc, f"{label}: Readable font size missing")
        require("line-height:1.35!important" in srcdoc, f"{label}: Readable line height missing")
    if display == "original":
        require(not office_readable_override, f"{label}: Original contains Readable override")
    if effective_images == "blocked":
        require("Images blocked" in visible, f"{label}: blocked permission state missing")
        require("img-src 'none'" in frame_csp, f"{label}: blocked iframe CSP changed")
    elif effective_images == "embedded":
        require("Embedded images shown" in visible, f"{label}: embedded permission state missing")
        require(f"img-src {candidate_base} data:" in frame_csp, f"{label}: embedded iframe CSP changed")
        require(" http: https:" not in frame_csp, f"{label}: embedded mode permits remote images")
    else:
        require("Remote images allowed" in visible, f"{label}: remote permission state missing")
        require(f"img-src {candidate_base} data: http: https:" in frame_csp, f"{label}: remote iframe CSP changed")
    return {
        "label": label,
        "headers": headers,
        "parser": parser,
        "srcdoc": srcdoc,
        "office_readable_override": office_readable_override,
        "elapsed_ms": round(elapsed * 1000, 1),
    }


def link_queries(parser):
    output = []
    for link in parser.links:
        href = link.get("href", "")
        parsed = urlparse(href)
        if parsed.path == "/message":
            output.append((href, parse_qs(parsed.query)))
    return output


def temp_entries(path):
    entries = []
    for root, dirs, files in os.walk(path):
        for name in dirs + files:
            entries.append(os.path.join(root, name))
    return entries


def validate_display_policy(readable_embedded, original_embedded, readable_blocked, original_blocked):
    if readable_embedded["office_readable_override"]:
        require(readable_embedded["srcdoc"] != original_embedded["srcdoc"], "Office Readable and Original srcdoc unexpectedly match")
        require(readable_blocked["srcdoc"] != original_blocked["srcdoc"], "Office blocked Readable and Original srcdoc unexpectedly match")
        return "office-readable-override"
    require(readable_embedded["srcdoc"] == original_embedded["srcdoc"], "non-Office embedded Readable and Original srcdoc differ")
    require(readable_blocked["srcdoc"] == original_blocked["srcdoc"], "non-Office blocked Readable and Original srcdoc differ")
    return "non-office-sanitized-parity"


asset_expectations = {
    "/static/app.css": (23190, "022967d486073a9c003b511e0d25ee0d9ebda9beec3040f53079f78c878836c7"),
    "/static/app.js": (5476, "ac7ef0afe0721ab87d2909658ed4e0dde51b16f1567674d9e0f7d987e74b3f81"),
    "/static/htmx.min.js": (51238, "71ea67185bfa8c98c39d31717c6fce5d852370fcdfd129db4543774d3145c0de"),
}
asset_results = {}
for path, (expected_size, expected_sha) in asset_expectations.items():
    status, headers, data, _ = fetch(path)
    require(status == 200, f"asset {path}: status {status}")
    actual_sha = hashlib.sha256(data).hexdigest()
    require(len(data) == expected_size, f"asset {path}: size {len(data)}")
    require(actual_sha == expected_sha, f"asset {path}: SHA256 {actual_sha}")
    verify_outer_headers(path, headers)
    asset_results[path] = {"size": len(data), "sha256": actual_sha}
    print(f"asset={path} size={len(data)} sha256={actual_sha}")

for path, htmx in (("/", False), ("/search?q=tag%3Ainbox", False), ("/search?q=tag%3Ainbox", True), ("/status", False)):
    status, headers, body, elapsed = fetch(path, htmx=htmx)
    require(status == 200, f"route {path} htmx={htmx}: status {status}")
    require(body, f"route {path} htmx={htmx}: empty body")
    verify_outer_headers(path, headers)
    if htmx:
        require("HX-Request" in headers.get("vary", ""), "HTMX search lacks Vary: HX-Request")
    print(f"route={path} htmx={str(htmx).lower()} status={status} ms={elapsed * 1000:.1f}")

for path in ("/attachment?cap=invalid", "/attachments.zip?cap=invalid", "/inline-image?cap=invalid"):
    status, _, _, _ = fetch(path)
    require(status == 403, f"invalid capability {path}: status {status}")
    print(f"rejection={path} status={status}")

status, _, _, _ = fetch("/route-that-does-not-exist")
require(status == 404, f"missing route: status {status}")
print("missing_route_status=404")

method_paths = ("/", "/search", "/message", "/attachment", "/attachments.zip", "/inline-image", "/status", "/healthz")
for path in method_paths:
    status, headers, _, _ = fetch(path, method="POST")
    require(status == 405, f"POST {path}: status {status}")
    require(headers.get("allow") == "GET", f"POST {path}: Allow={headers.get('allow')!r}")
    print(f"method_rejection={path} status=405 allow=GET")

counts_converged = False
for _ in range(5):
    status, _, production_health_before_raw, _ = fetch("/healthz", base=production_base)
    require(status == 200, f"production health before status {status}")
    production_health_before = json.loads(production_health_before_raw)
    status, _, candidate_health_raw, _ = fetch("/healthz")
    require(status == 200, f"candidate health status {status}")
    candidate_health = json.loads(candidate_health_raw)
    status, _, production_health_after_raw, _ = fetch("/healthz", base=production_base)
    require(status == 200, f"production health after status {status}")
    production_health_after = json.loads(production_health_after_raw)
    candidate_counts = (candidate_health["messages"], candidate_health["files"])
    production_counts = {
        (production_health_before["messages"], production_health_before["files"]),
        (production_health_after["messages"], production_health_after["files"]),
    }
    if candidate_counts in production_counts:
        counts_converged = True
        break
    time.sleep(0.2)
for label, health, expected_addr in (
    ("candidate", candidate_health, "127.0.0.1:8876"),
    ("production-before", production_health_before, "127.0.0.1:8765"),
    ("production-after", production_health_after, "127.0.0.1:8765"),
):
    require(health.get("ok") is True, f"{label}: health not ok")
    require(health.get("read_only") is True, f"{label}: read_only changed")
    require(health.get("mail_mutation") is False, f"{label}: mail_mutation changed")
    require(health.get("addr") == expected_addr, f"{label}: addr changed")
    require(health.get("database_path") == "/mail/SearchIndex/notmuch/default", f"{label}: database path changed")
    require(health.get("mail_root") == "/mail/Mailstore", f"{label}: mail root changed")
require(counts_converged, f"candidate counts {candidate_counts} do not match live production {production_counts}")
print(f"candidate_health_counts={candidate_counts[0]}/{candidate_counts[1]}")

readable_blocked = inspect_message("readable-full-reload-reset", "readable", "remote", htmx=False, effective_images="blocked")
original_blocked = inspect_message("original-full-reload-reset", "original", "remote", htmx=False, effective_images="blocked")
readable_embedded = inspect_message("readable-embedded", "readable", "embedded", htmx=True)
original_embedded = inspect_message("original-embedded", "original", "embedded", htmx=True)
readable_remote = inspect_message("readable-remote", "readable", "remote", htmx=True)

display_classification = validate_display_policy(
    readable_embedded,
    original_embedded,
    readable_blocked,
    original_blocked,
)

print(f"display_classification={display_classification}")
print("readable_original_policy=PASS")

require("/inline-image?cap=" not in readable_blocked["srcdoc"], "blocked mode contains signed inline-image URLs")
require("/inline-image?cap=" not in original_blocked["srcdoc"], "Original blocked mode contains signed inline-image URLs")

inline_pattern = re.compile(r"http://127\.0\.0\.1:8876/inline-image\?cap=[A-Za-z0-9._~-]+")
readable_urls = sorted(set(inline_pattern.findall(readable_embedded["srcdoc"])))
original_urls = sorted(set(inline_pattern.findall(original_embedded["srcdoc"])))
remote_urls = sorted(set(inline_pattern.findall(readable_remote["srcdoc"])))
require(len(readable_urls) == 10, f"Readable embedded signed CID count is {len(readable_urls)}, expected 10")
require(original_urls == readable_urls, "Original and Readable signed CID sets differ")
require(remote_urls == readable_urls, "Remote and embedded signed CID sets differ")
print("signed_cid_urls=10")
print("genuine_attachment_rows=1")
print("save_all_capabilities=1")

readable_queries = link_queries(readable_embedded["parser"])
require(any(query.get("display") == ["original"] and query.get("images") == ["embedded"] for _, query in readable_queries), "Readable-to-Original switch does not preserve embedded permission")
require(all("images" not in query and "display" not in query for _, query in readable_queries if query.get("dup")), "Readable duplicate switch did not reset images or preserve Readable")
original_queries = link_queries(original_embedded["parser"])
require(any("display" not in query and query.get("images") == ["embedded"] for _, query in original_queries), "Original-to-Readable switch does not preserve embedded permission")
require(all(query.get("display") == ["original"] and "images" not in query for _, query in original_queries if query.get("dup")), "Original duplicate switch did not reset images or preserve Original")
print("display_switch_state=PASS")
print("duplicate_reset_state=PASS")


def fetch_inline(url):
    status, headers, data, elapsed = fetch(url, timeout=130)
    return {
        "url_sha256": hashlib.sha256(url.encode()).hexdigest(),
        "status": status,
        "content_type": headers.get("content-type", ""),
        "bytes": len(data),
        "elapsed_ms": round(elapsed * 1000, 1),
    }


inline_results = []
with ThreadPoolExecutor(max_workers=10) as pool:
    futures = [pool.submit(fetch_inline, url) for url in readable_urls]
    for future in as_completed(futures):
        inline_results.append(future.result())

statuses = sorted(result["status"] for result in inline_results)
require(statuses == [200] * 10, f"inline statuses are {statuses}")
require(all(result["content_type"].lower().startswith("image/") for result in inline_results), "an inline response is not an image")
require(all(result["bytes"] > 0 for result in inline_results), "an inline response is empty")
require(not any(result["status"] == 429 for result in inline_results), "an inline response returned 429")
max_elapsed = max(result["elapsed_ms"] for result in inline_results)
print("inline_status_200=10")
print("inline_status_429=0")
print(f"inline_max_elapsed_ms={max_elapsed:.1f}")

for _ in range(100):
    isolated_entries = temp_entries(isolated_temp)
    production_entries = temp_entries(production_temp)
    if not isolated_entries and not production_entries:
        break
    time.sleep(0.1)
require(not isolated_entries, f"isolated temp not empty: {isolated_entries[:5]}")
require(not production_entries, f"production temp not empty: {production_entries[:5]}")
print("isolated_temp_entries=0")
print("production_temp_entries=0")

report = {
    "format": "notmuch-browser-outlook-readable-isolated-report-v1",
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "message_id": message_id,
    "candidate_health": candidate_health,
    "production_health_before": production_health_before,
    "production_health_after": production_health_after,
    "assets": asset_results,
    "message_checks": {
        "readable_full_reload_reset_ms": readable_blocked["elapsed_ms"],
        "original_full_reload_reset_ms": original_blocked["elapsed_ms"],
        "readable_embedded_ms": readable_embedded["elapsed_ms"],
        "original_embedded_ms": original_embedded["elapsed_ms"],
        "readable_remote_ms": readable_remote["elapsed_ms"],
        "display_classification": display_classification,
        "genuine_attachment_rows": 1,
        "signed_cid_urls": 10,
    },
    "inline_results": sorted(inline_results, key=lambda item: item["url_sha256"]),
    "temporary_files": {"isolated": 0, "production": 0},
    "status": "PASS",
}
fd = os.open(report_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(report, handle, indent=2, sort_keys=True)
    handle.write("\n")
print("automated_status=PASS")
PY

test "$(stat -c '%a' "$REPORT")" = "600"
REPORT_SHA256=$(sha256sum "$REPORT" | awk '{print $1}')

echo "== Retain exact candidate for owner comparison =="
test "$(readlink "/proc/$PID/exe")" = "$BINARY"
test "$(awk '{print $22}' "/proc/$PID/stat")" = "$PROCESS_START_TICKS"
require_empty_dir "$ISOLATED_TEMP" "isolated download temp"
require_empty_dir "$PROD_TEMP" "production download temp"

printf '%s  %s\n' "$PROD_BINARY_SHA256" "$PROD_BINARY" | sha256sum -c -
printf '%s  %s\n' "$PROD_CONTROL_SHA256" "$PROD_CONTROL" | sha256sum -c -
printf '%s  %s\n' "$PROD_INDEX_CONTROL_SHA256" "$PROD_INDEX_CONTROL" | sha256sum -c -
curl -fsS "$PRODUCTION_BASE/healthz" > "$RUN/production-health-after.json"
validate_health_file "$RUN/production-health-after.json" "127.0.0.1:8765"

python3 - \
    "$ISOLATED_POINTER" \
    "$PID" \
    "$BOOT_ID" \
    "$PROCESS_START_TICKS" \
    "$BINARY" \
    "$BINARY_SHA256" \
    "$BUILD_POINTER" \
    "$BUILD_POINTER_SHA256" \
    "$ARCHIVE" \
    "$ARCHIVE_SHA256" \
    "$RUN" \
    "$SERVER_LOG" \
    "$VALIDATION_LOG" \
    "$REPORT" \
    "$REPORT_SHA256" \
    "$ISOLATED_TEMP" \
    "$MESSAGE_ID" <<'PY'
import json
import os
import sys
from datetime import datetime
from urllib.parse import urlencode

(
    pointer,
    pid,
    boot_id,
    start_ticks,
    binary,
    binary_sha256,
    build_pointer,
    build_pointer_sha256,
    archive,
    archive_sha256,
    run,
    server_log,
    validation_log,
    report,
    report_sha256,
    temp,
    message_id,
) = sys.argv[1:]

base = "http://127.0.0.1:8876/message?"
readable_url = base + urlencode({"id": message_id})
original_url = base + urlencode({"id": message_id, "display": "original"})
data = {
    "format": "notmuch-browser-outlook-readable-isolated-v1",
    "created_at": datetime.now().astimezone().isoformat(),
    "pid": int(pid),
    "boot_id": boot_id,
    "process_start_ticks": int(start_ticks),
    "binary": binary,
    "binary_sha256": binary_sha256,
    "build_pointer": build_pointer,
    "build_pointer_sha256": build_pointer_sha256,
    "archive": archive,
    "archive_sha256": archive_sha256,
    "run": run,
    "server_log": server_log,
    "validation_log": validation_log,
    "automated_report": report,
    "automated_report_sha256": report_sha256,
    "download_temp": temp,
    "message_id": message_id,
    "readable_url": readable_url,
    "original_url": original_url,
}
temporary = pointer + f".new.{pid}"
fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.replace(temporary, pointer)
PY

POINTER_CREATED=1

test "$(stat -c '%a' "$ISOLATED_POINTER")" = "600"
POINTER_SHA256=$(sha256sum "$ISOLATED_POINTER" | awk '{print $1}')

READABLE_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["readable_url"])' "$ISOLATED_POINTER")
ORIGINAL_URL=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["original_url"])' "$ISOLATED_POINTER")

KEEP_CANDIDATE=1

echo "candidate_retained=yes"
echo "isolated_pointer=$ISOLATED_POINTER"
echo "isolated_pointer_mode=600"
echo "isolated_pointer_sha256=$POINTER_SHA256"
echo "automated_report=$REPORT"
echo "automated_report_sha256=$REPORT_SHA256"
echo "server_log=$SERVER_LOG"
echo "readable_url=$READABLE_URL"
echo "original_url=$ORIGINAL_URL"
echo "production_binary_replaced=no"
echo "production_service_restarted=no"
echo "mail_index_operation_run=no"
echo "status=OUTLOOK_READABLE_ISOLATED_AUTOMATED_PASS_RETAINED"
