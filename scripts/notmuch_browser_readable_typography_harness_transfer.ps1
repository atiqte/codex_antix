[CmdletBinding()]
param(
    [string]$Remote = "atiq@192.168.254.128"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$localScript = Join-Path $PSScriptRoot "notmuch_browser_readable_typography_isolated_start.sh"
$incoming = "/home/atiq/codex-runs/notmuch-browser-readable-typography-isolated-start.sh.incoming-6aa02ac"
$final = "/home/atiq/codex-runs/notmuch-browser-readable-typography-isolated-start-6aa02ac.sh"
$expectedBytes = 12796
$expectedSHA256 = "6aa02ac861d7202eb2764ae835983bd8bc2a6fbff2d8d0facae3b035bef0d304"

function Invoke-RemoteBash {
    param(
        [Parameter(Mandatory)]
        [string]$Script,

        [Parameter(Mandatory)]
        [string]$FailureMessage
    )

    $Script | & ssh $Remote "bash -s"
    if ($LASTEXITCODE -ne 0) {
        throw $FailureMessage
    }
}

if (-not (Test-Path -LiteralPath $localScript -PathType Leaf)) {
    throw "Local validation script is absent: $localScript"
}

$bytes = [IO.File]::ReadAllBytes($localScript)
$actualSHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $localScript).Hash.ToLowerInvariant()
$crBytes = ($bytes | Where-Object { $_ -eq 13 }).Count

if ($bytes.Length -ne $expectedBytes) {
    throw "Local byte count mismatch: $($bytes.Length)"
}
if ($actualSHA256 -ne $expectedSHA256) {
    throw "Local SHA256 mismatch: $actualSHA256"
}
if ($crBytes -ne 0) {
    throw "Local script contains CR bytes: $crBytes"
}

"local_bytes=$($bytes.Length)"
"local_sha256=$actualSHA256"
"local_cr_bytes=$crBytes"

$remoteAddress = ($Remote -split "@")[-1]
if (-not (Test-NetConnection $remoteAddress -Port 22 -InformationLevel Quiet)) {
    throw "SSH port 22 is not reachable at $remoteAddress"
}
"ssh_port_22=reachable"

$preflight = @'
set -eu

INCOMING="__INCOMING__"
FINAL="__FINAL__"
POINTER="/mail/AppData/notmuch-browser/readable-typography-isolated-current.json"
BINARY="/home/atiq/codex-runs/notmuch-browser-readable-typography-build-20260719-071305/notmuch-browser"
PROD_TEMP="/mail/AppData/notmuch-browser/download-tmp"

test ! -e "$INCOMING"
test ! -e "$FINAL"
test ! -e "$POINTER"
test -d "$PROD_TEMP"
test -z "$(find "$PROD_TEMP" -mindepth 1 -print -quit)"

port="$(ss -H -ltnp | awk '$4 ~ /:8876$/')"
test -z "$port"

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
test "$candidate_processes" -eq 0

printf '%s  %s\n' \
  'e68c33d1e369f8023e5b7fc619055b0ef7fa537a5013226176aac6a9f2435647' \
  "$BINARY" \
  'c28f953f6b45051ee35d77fd34118078679f1f697e24f5ea5348749b89e99b5f' \
  '/home/atiq/codex-runs/notmuch-browser-readable-typography-build-20260719-071305/build-report.json' \
  '50e6b1adbcf32201496f6d6f5a3d53c060d0c39e1831ca1b5ecac3d48838f37e' \
  '/home/atiq/.local/bin/notmuch-browser' |
  sha256sum -c -

health="$(curl -fsS --max-time 30 http://127.0.0.1:8765/healthz)"
HEALTH_JSON="$health" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["HEALTH_JSON"])
expected = {
    "ok": True,
    "read_only": True,
    "mail_mutation": False,
    "downloads_enabled": True,
    "temporary_download_files": True,
    "addr": "127.0.0.1:8765",
    "database_path": "/mail/SearchIndex/notmuch/default",
    "mail_root": "/mail/Mailstore",
}
for key, value in expected.items():
    if data.get(key) != value:
        raise SystemExit(f"health mismatch: {key}={data.get(key)!r}, expected {value!r}")
print(f"production_messages={data['messages']}")
print(f"production_files={data['files']}")
print("production_health=PASS")
PY

echo "candidate_processes=$candidate_processes"
echo "port_8876=free"
echo "remote_preflight=PASS"
'@

$preflight = $preflight.Replace("__INCOMING__", $incoming).Replace("__FINAL__", $final)
Invoke-RemoteBash -Script $preflight -FailureMessage "Remote preflight failed"

& scp $localScript "${Remote}:$incoming"
if ($LASTEXITCODE -ne 0) {
    throw "SCP transfer failed"
}

$verification = @'
set -eu

INCOMING="__INCOMING__"
FINAL="__FINAL__"
EXPECTED_SHA256="__SHA256__"
POINTER="/mail/AppData/notmuch-browser/readable-typography-isolated-current.json"

test -f "$INCOMING"
test ! -e "$FINAL"
test ! -e "$POINTER"
test "$(stat -c '%s' "$INCOMING")" -eq 12796
test "$(sha256sum "$INCOMING" | awk '{print $1}')" = "$EXPECTED_SHA256"
test "$(LC_ALL=C tr -cd '\r' < "$INCOMING" | wc -c)" -eq 0
bash -n "$INCOMING"

python3 - "$INCOMING" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text(encoding="utf-8")
marker = "<<'PY'"
end = "\nPY\n"
blocks = []
position = 0
while marker in source[position:]:
    start = source.index(marker, position) + len(marker)
    start = source.index("\n", start) + 1
    stop = source.index(end, start)
    blocks.append(source[start:stop])
    position = stop + len(end)
for number, block in enumerate(blocks, 1):
    compile(block, f"<heredoc-{number}>", "exec")
if len(blocks) != 4:
    raise SystemExit(f"expected four embedded Python blocks, found {len(blocks)}")
print("embedded_python_blocks=4 PASS")
PY

port="$(ss -H -ltnp | awk '$4 ~ /:8876$/')"
test -z "$port"

health="$(curl -fsS --max-time 30 http://127.0.0.1:8765/healthz)"
HEALTH_JSON="$health" python3 - <<'PY'
import json
import os

data = json.loads(os.environ["HEALTH_JSON"])
for key, value in {
    "ok": True,
    "read_only": True,
    "mail_mutation": False,
    "addr": "127.0.0.1:8765",
}.items():
    if data.get(key) != value:
        raise SystemExit(f"health mismatch: {key}={data.get(key)!r}, expected {value!r}")
print("production_health_after_transfer=PASS")
PY

stat -c 'incoming_mode=%a owner=%U group=%G bytes=%s path=%n' "$INCOMING"
echo "incoming_sha256=$(sha256sum "$INCOMING" | awk '{print $1}')"
echo "incoming_cr_bytes=0"
echo "bash_syntax=PASS"
echo "port_8876=free"
echo "script_finalized=no"
echo "script_executed=no"
echo "candidate_started=no"
echo "production_changed=no"
echo "status=READABLE_TYPOGRAPHY_HARNESS_TRANSFER_PASS"
'@

$verification = $verification.Replace("__INCOMING__", $incoming).Replace("__FINAL__", $final).Replace("__SHA256__", $expectedSHA256)
Invoke-RemoteBash -Script $verification -FailureMessage "Remote transfer verification failed"
