#!/usr/bin/env bash
set -euo pipefail
umask 077

readonly ARCHIVE="/home/atiq/notmuch-browser-readable-typography-src-20260719-071305.tar.gz"
readonly ARCHIVE_SHA256="50e368dcabcf453c471c2b2d774200f9d80fb2fd366952efe12ea99fd83574f1"
readonly BINARY="/home/atiq/codex-runs/notmuch-browser-readable-typography-build-20260719-071305/notmuch-browser"
readonly BINARY_SHA256="e68c33d1e369f8023e5b7fc619055b0ef7fa537a5013226176aac6a9f2435647"
readonly BUILD_REPORT="/home/atiq/codex-runs/notmuch-browser-readable-typography-build-20260719-071305/build-report.json"
readonly BUILD_REPORT_SHA256="c28f953f6b45051ee35d77fd34118078679f1f697e24f5ea5348749b89e99b5f"
readonly CONFIG="/home/atiq/.config/notmuch/default/config"
readonly PROD_BROWSER="/home/atiq/.local/bin/notmuch-browser"
readonly PROD_BROWSER_SHA256="50e6b1adbcf32201496f6d6f5a3d53c060d0c39e1831ca1b5ecac3d48838f37e"
readonly PROD_CONTROL="/home/atiq/.local/bin/notmuch-browser-control"
readonly PROD_CONTROL_SHA256="1b1277b0af3ab582ab307dd8763115ed754121c8a61643737888aa11d97b34b7"
readonly PROD_INDEX="/home/atiq/.local/bin/notmuch-browser-index-control"
readonly PROD_INDEX_SHA256="df07cd071d1976ea43b8c4c44655b60a179f9809a24995980bdf8e8958eae0b3"
readonly PROD_TEMP="/mail/AppData/notmuch-browser/download-tmp"
readonly POINTER="/mail/AppData/notmuch-browser/readable-typography-isolated-current.json"
readonly BASE="http://127.0.0.1:8876"
readonly PROD_BASE="http://127.0.0.1:8765"

RUN="/home/atiq/codex-runs/notmuch-browser-readable-typography-isolated-$(date +%Y%m%d-%H%M%S)"
ISOLATED_TEMP="/mail/AppData/notmuch-browser/readable-typography-isolated-$(date +%Y%m%d-%H%M%S)"
SERVER_LOG="$RUN/server.log"
PID=""
START_TICKS=""
RETAIN=0
TEMP_OWNED=0
POINTER_OWNED=0

die() {
    printf 'BLOCKED: %s\n' "$*" >&2
    exit 1
}

process_is_exact() {
    [ -n "$PID" ] || return 1
    [ -r "/proc/$PID/stat" ] || return 1
    [ "$(readlink "/proc/$PID/exe" 2>/dev/null || true)" = "$BINARY" ] || return 1
    if [ -n "$START_TICKS" ]; then
        [ "$(awk '{print $22}' "/proc/$PID/stat")" = "$START_TICKS" ] || return 1
    fi
}

cleanup() {
    rc=$?
    trap - EXIT
    if [ "$rc" -ne 0 ] && process_is_exact; then
        kill -TERM "$PID" 2>/dev/null || true
        for _ in $(seq 1 50); do
            [ ! -r "/proc/$PID/stat" ] && break
            sleep 0.1
        done
        if process_is_exact; then
            kill -KILL "$PID" 2>/dev/null || true
        fi
    fi
    if [ "$rc" -ne 0 ]; then
        if [ "$POINTER_OWNED" -eq 1 ] && [ -e "$POINTER" ]; then
            unlink "$POINTER"
        fi
        if [ "$TEMP_OWNED" -eq 1 ] && [ -d "$ISOLATED_TEMP" ] && [ -z "$(find "$ISOLATED_TEMP" -mindepth 1 -print -quit)" ]; then
            rmdir "$ISOLATED_TEMP"
        fi
        printf 'candidate_retained=no\n' >&2
        printf 'evidence_directory=%s\n' "$RUN" >&2
    elif [ "$RETAIN" -ne 1 ]; then
        printf 'BLOCKED: successful exit attempted without retained-state authorization\n' >&2
        exit 1
    fi
    exit "$rc"
}
trap cleanup EXIT

health_contract() {
    local file=$1
    local expected_addr=$2
    python3 - "$file" "$expected_addr" <<'PY'
import json
import sys

path, expected_addr = sys.argv[1:]
with open(path, "r", encoding="utf-8") as handle:
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
        raise SystemExit(f"health mismatch: {key}={data.get(key)!r}, expected {value!r}")
if not isinstance(data.get("messages"), int) or data["messages"] < 1:
    raise SystemExit("health messages is not a positive integer")
if not isinstance(data.get("files"), int) or data["files"] < data["messages"]:
    raise SystemExit("health files is invalid")
print(f"{expected_addr}_messages={data['messages']}")
print(f"{expected_addr}_files={data['files']}")
print(f"{expected_addr}_health=PASS")
PY
}

echo "== Exact identities and production preflight =="
printf '%s  %s\n' \
    "$ARCHIVE_SHA256" "$ARCHIVE" \
    "$BINARY_SHA256" "$BINARY" \
    "$BUILD_REPORT_SHA256" "$BUILD_REPORT" \
    "$PROD_BROWSER_SHA256" "$PROD_BROWSER" \
    "$PROD_CONTROL_SHA256" "$PROD_CONTROL" \
    "$PROD_INDEX_SHA256" "$PROD_INDEX" |
    sha256sum -c -

[ "$(stat -c '%s' "$ARCHIVE")" -eq 76778 ] || die "archive size changed"
[ "$(stat -c '%s' "$BINARY")" -eq 9761033 ] || die "candidate binary size changed"
[ -f "$CONFIG" ] || die "notmuch config is absent"
[ ! -e "$POINTER" ] || die "isolated pointer already exists: $POINTER"
[ ! -e "$RUN" ] || die "run directory already exists"
[ ! -e "$ISOLATED_TEMP" ] || die "isolated temp path already exists"

candidate_processes="$(python3 - "$BINARY" <<'PY'
import os
import pathlib
import sys

expected = sys.argv[1]
count = 0
for proc in pathlib.Path("/proc").glob("[0-9]*"):
    try:
        if os.readlink(proc / "exe") == expected:
            count += 1
    except OSError:
        pass
print(count)
PY
)"
[ "$candidate_processes" -eq 0 ] || die "exact candidate process already runs"

port_before="$(ss -H -ltnp | awk '$4 ~ /:8876$/')"
[ -z "$port_before" ] || die "port 8876 is already in use"

prod_listener="$(ss -H -ltnp | awk '$4 == "127.0.0.1:8765"')"
[ "$(printf '%s\n' "$prod_listener" | awk 'NF {n++} END {print n+0}')" -eq 1 ] ||
    die "production listener is not exactly one loopback socket"

[ -d "$PROD_TEMP" ] || die "production temp directory is absent"
[ -z "$(find "$PROD_TEMP" -mindepth 1 -print -quit)" ] ||
    die "production temp directory is not empty"

mkdir -m 700 "$RUN"
curl -fsS --max-time 30 "$PROD_BASE/healthz" -o "$RUN/production-health-before.json"
health_contract "$RUN/production-health-before.json" "127.0.0.1:8765"

echo "== Start exact loopback-only candidate =="
mkdir -m 700 "$ISOLATED_TEMP"
TEMP_OWNED=1
: > "$SERVER_LOG"
chmod 600 "$SERVER_LOG"

nohup "$BINARY" \
    --addr "127.0.0.1:8876" \
    --config "$CONFIG" \
    --download-tmp "$ISOLATED_TEMP" \
    > "$SERVER_LOG" 2>&1 < /dev/null &
PID=$!

for _ in $(seq 1 100); do
    if [ -r "/proc/$PID/stat" ] &&
       curl -fsS --max-time 2 "$BASE/healthz" -o "$RUN/candidate-health.json" 2>/dev/null; then
        break
    fi
    sleep 0.1
done

[ -r "/proc/$PID/stat" ] || die "candidate exited; inspect $SERVER_LOG"
START_TICKS="$(awk '{print $22}' "/proc/$PID/stat")"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id)"
CMDLINE="$(tr '\0' ' ' < "/proc/$PID/cmdline")"
EXPECTED_CMDLINE="$BINARY --addr 127.0.0.1:8876 --config $CONFIG --download-tmp $ISOLATED_TEMP "

process_is_exact || die "candidate process identity mismatch"
[ "$CMDLINE" = "$EXPECTED_CMDLINE" ] || die "candidate command line mismatch"

candidate_listener="$(ss -H -ltnp | awk '$4 == "127.0.0.1:8876"')"
[ "$(printf '%s\n' "$candidate_listener" | awk 'NF {n++} END {print n+0}')" -eq 1 ] ||
    die "candidate listener is not exactly one loopback socket"
case "$candidate_listener" in
    *"pid=$PID,"*) ;;
    *) die "candidate listener does not belong to PID $PID" ;;
esac

health_contract "$RUN/candidate-health.json" "127.0.0.1:8876"

echo "== Base routes, assets, and security contract =="
curl -fsS --max-time 30 -D "$RUN/root.headers" "$BASE/" -o "$RUN/root.html"
curl -fsS --max-time 30 "$BASE/search?q=tag%3Ainbox&limit=1" -o "$RUN/search.html"
curl -fsS --max-time 30 "$BASE/status" -o "$RUN/status.html"
curl -fsS --max-time 30 "$BASE/static/app.css" -o "$RUN/app.css"
curl -fsS --max-time 30 "$BASE/static/app.js" -o "$RUN/app.js"
curl -fsS --max-time 30 "$BASE/static/htmx.min.js" -o "$RUN/htmx.min.js"

printf '%s  %s\n' \
    "022967d486073a9c003b511e0d25ee0d9ebda9beec3040f53079f78c878836c7" "$RUN/app.css" \
    "ac7ef0afe0721ab87d2909658ed4e0dde51b16f1567674d9e0f7d987e74b3f81" "$RUN/app.js" \
    "71ea67185bfa8c98c39d31717c6fce5d852370fcdfd129db4543774d3145c0de" "$RUN/htmx.min.js" |
    sha256sum -c -

python3 - "$RUN/root.headers" "$RUN/root.html" "$RUN/search.html" "$RUN/status.html" <<'PY'
from pathlib import Path
import sys

headers = Path(sys.argv[1]).read_text(encoding="iso-8859-1").lower()
root = Path(sys.argv[2]).read_text(encoding="utf-8")
search = Path(sys.argv[3]).read_text(encoding="utf-8")
status = Path(sys.argv[4]).read_text(encoding="utf-8")

required_headers = [
    "x-content-type-options: nosniff",
    "referrer-policy: no-referrer",
    "cache-control: private, no-store",
    "style-src 'self' 'unsafe-inline'",
    "script-src 'self'",
    "frame-ancestors 'none'",
]
for value in required_headers:
    if value not in headers:
        raise SystemExit(f"missing security header contract: {value}")
if "script-src 'self' 'unsafe-inline'" in headers:
    raise SystemExit("inline scripts are unexpectedly permitted")
for name, body in [("root", root), ("search", search), ("status", status)]:
    if "<!doctype html" not in body.lower():
        raise SystemExit(f"{name} did not return an HTML document")
print("base_routes=PASS")
print("parent_csp_inline_styles_only=PASS")
PY

invalid_attachment="$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$BASE/attachment?cap=invalid")"
invalid_zip="$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$BASE/attachments.zip?cap=invalid")"
invalid_image="$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' "$BASE/inline-image?cap=invalid")"
post_root="$(curl -sS --max-time 30 -X POST -o /dev/null -w '%{http_code}' "$BASE/")"
[ "$invalid_attachment" = 403 ] || die "invalid attachment returned $invalid_attachment, expected 403"
[ "$invalid_zip" = 403 ] || die "invalid ZIP returned $invalid_zip, expected 403"
[ "$invalid_image" = 403 ] || die "invalid inline image returned $invalid_image, expected 403"
[ "$post_root" = 405 ] || die "POST root returned $post_root, expected 405"
printf 'rejection_codes=attachment:%s zip:%s image:%s post:%s\n' \
    "$invalid_attachment" "$invalid_zip" "$invalid_image" "$post_root"

[ -z "$(find "$ISOLATED_TEMP" -mindepth 1 -print -quit)" ] ||
    die "isolated temp is not empty after base checks"
[ -z "$(find "$PROD_TEMP" -mindepth 1 -print -quit)" ] ||
    die "production temp changed during candidate checks"

echo "== Reprove production and write private retained pointer =="
printf '%s  %s\n' \
    "$PROD_BROWSER_SHA256" "$PROD_BROWSER" \
    "$PROD_CONTROL_SHA256" "$PROD_CONTROL" \
    "$PROD_INDEX_SHA256" "$PROD_INDEX" |
    sha256sum -c -
curl -fsS --max-time 30 "$PROD_BASE/healthz" -o "$RUN/production-health-after.json"
health_contract "$RUN/production-health-after.json" "127.0.0.1:8765"
process_is_exact || die "candidate identity changed before pointer write"

python3 - \
    "$POINTER" "$ARCHIVE" "$ARCHIVE_SHA256" "$BINARY" "$BINARY_SHA256" \
    "$BUILD_REPORT" "$BUILD_REPORT_SHA256" "$RUN" "$SERVER_LOG" "$ISOLATED_TEMP" \
    "$PID" "$START_TICKS" "$BOOT_ID" "$CMDLINE" "$BASE" <<'PY'
import json
import os
from pathlib import Path
import sys
from datetime import datetime, timezone

(pointer, archive, archive_sha, binary, binary_sha, report, report_sha,
 run, server_log, temp_dir, pid, start_ticks, boot_id, cmdline, base) = sys.argv[1:]

data = {
    "format": "notmuch-browser-readable-typography-isolated-v1",
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "archive": archive,
    "archive_sha256": archive_sha,
    "binary": binary,
    "binary_bytes": Path(binary).stat().st_size,
    "binary_sha256": binary_sha,
    "build_report": report,
    "build_report_sha256": report_sha,
    "run_directory": run,
    "server_log": server_log,
    "temporary_directory": temp_dir,
    "pid": int(pid),
    "start_ticks": int(start_ticks),
    "boot_id": boot_id,
    "cmdline": cmdline,
    "base_url": base,
}
tmp = pointer + ".new"
with open(tmp, "x", encoding="utf-8", newline="\n") as handle:
    json.dump(data, handle, indent=2, sort_keys=True)
    handle.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, pointer)
PY
POINTER_OWNED=1

[ "$(stat -c '%a' "$POINTER")" = 600 ] || die "pointer mode is not 600"
[ "$(stat -c '%a' "$ISOLATED_TEMP")" = 700 ] || die "isolated temp mode is not 700"
RETAIN=1

echo "candidate_pid=$PID"
echo "candidate_start_ticks=$START_TICKS"
echo "candidate_binary_sha256=$BINARY_SHA256"
echo "candidate_listener=127.0.0.1:8876"
echo "candidate_temp_files=0"
echo "pointer=$POINTER"
echo "pointer_sha256=$(sha256sum "$POINTER" | awk '{print $1}')"
echo "server_log=$SERVER_LOG"
echo "candidate_retained=yes"
echo "production_installed=no"
echo "production_restarted=no"
echo "mail_index_operation_run=no"
echo "open_url=http://127.0.0.1:8876/"
echo "status=READABLE_TYPOGRAPHY_ISOLATED_START_PASS"
