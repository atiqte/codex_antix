#!/bin/bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OPERATOR_ROOT=${NOTMUCH_BROWSER_OPERATOR_ROOT:-"$REPO_ROOT/codex-output/notmuch-browser-operator"}
BATCH_PATH=${1:-"$OPERATOR_ROOT/current.sh"}
LOG_DIR="$OPERATOR_ROOT/logs"

die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

command -v bash >/dev/null 2>&1 || die "bash is not available"
command -v tee >/dev/null 2>&1 || die "tee is not available"
command -v sha256sum >/dev/null 2>&1 || die "sha256sum is not available"
[ -f "$BATCH_PATH" ] || die "operator batch is missing: $BATCH_PATH"
[ -r "$BATCH_PATH" ] || die "operator batch is not readable: $BATCH_PATH"

install -d -m 700 "$OPERATOR_ROOT" "$LOG_DIR"
chmod 700 "$BATCH_PATH"

RUN_STAMP=$(date '+%Y%m%d-%H%M%S-%3N')
LOG_PATH="$LOG_DIR/notmuch-browser-operator-$RUN_STAMP.log"
BATCH_SHA256=$(sha256sum "$BATCH_PATH" | awk '{print $1}')

set +e
(
  set -u
  printf 'operator_run_started=%s\n' "$(date --iso-8601=ns)"
  printf 'operator_run_stamp=%s\n' "$RUN_STAMP"
  printf 'operator_host=%s\n' "$(hostname)"
  printf 'operator_user=%s\n' "$(id -un)"
  printf 'operator_repo=%s\n' "$REPO_ROOT"
  printf 'operator_batch=%s\n' "$BATCH_PATH"
  printf 'operator_batch_sha256=%s\n' "$BATCH_SHA256"
  printf 'operator_log=%s\n' "$LOG_PATH"

  set +e
  bash "$BATCH_PATH"
  BATCH_RC=$?
  set -e

  printf 'operator_batch_exit=%s\n' "$BATCH_RC"
  printf 'operator_run_finished=%s\n' "$(date --iso-8601=ns)"
  exit "$BATCH_RC"
) 2>&1 | tee "$LOG_PATH"
PIPE_STATUS=("${PIPESTATUS[@]}")
set -e

BATCH_RC=${PIPE_STATUS[0]}
TEE_RC=${PIPE_STATUS[1]}
chmod 600 "$LOG_PATH"

LATEST_TMP=$(mktemp "$OPERATOR_ROOT/.latest-log.XXXXXX")
printf '%s\n' "$LOG_PATH" > "$LATEST_TMP"
chmod 600 "$LATEST_TMP"
mv "$LATEST_TMP" "$OPERATOR_ROOT/latest-log.txt"

printf 'saved_operator_log=%s\n' "$LOG_PATH"
printf 'saved_operator_log_sha256=%s\n' "$(sha256sum "$LOG_PATH" | awk '{print $1}')"

if [ "$TEE_RC" -ne 0 ]; then
  die "tee failed while writing the operator log"
fi
exit "$BATCH_RC"
