#!/bin/bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OPERATOR_ROOT=${NOTMUCH_BROWSER_OPERATOR_ROOT:-"$REPO_ROOT/codex-output/notmuch-browser-operator"}
EVIDENCE_ROOT=${NOTMUCH_BROWSER_EVIDENCE_ROOT:-"$REPO_ROOT/docs/validation/notmuch-browser-multisource"}

die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

[ "$#" -eq 3 ] || die "usage: $0 CHUNK_ID SLUG RESULT"
CHUNK_ID=$1
SLUG=$2
RESULT=$3
[[ "$CHUNK_ID" =~ ^[0-9]{2}$ ]] || die "CHUNK_ID must contain exactly two digits"
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "SLUG must be lowercase letters, numbers, and hyphens"
case "$RESULT" in
  success|failed|partial|superseded) ;;
  *) die "RESULT must be success, failed, partial, or superseded" ;;
esac

LATEST_RESULT_POINTER="$OPERATOR_ROOT/latest-result.txt"
[ -s "$LATEST_RESULT_POINTER" ] || die "latest result pointer is missing"
RESULT_PATH=$(sed -n '1p' "$LATEST_RESULT_POINTER")
[ -f "$RESULT_PATH" ] || die "result manifest is missing: $RESULT_PATH"

value() {
  local key=$1
  sed -n "s/^${key}=//p" "$RESULT_PATH" | sed -n '1p'
}

BATCH_PATH=$(value batch_path)
BATCH_SHA256=$(value batch_sha256)
LOG_PATH=$(value log_path)
LOG_SHA256=$(value log_sha256)
BATCH_EXIT=$(value batch_exit)
STARTED_AT=$(value started_at)
FINISHED_AT=$(value finished_at)
[ -f "$BATCH_PATH" ] || die "executed batch is missing: $BATCH_PATH"
[ -f "$LOG_PATH" ] || die "operator log is missing: $LOG_PATH"
[ "$(sha256sum "$BATCH_PATH" | awk '{print $1}')" = "$BATCH_SHA256" ] ||
  die "executed batch hash drifted"
[ "$(sha256sum "$LOG_PATH" | awk '{print $1}')" = "$LOG_SHA256" ] ||
  die "operator log hash drifted"

if grep -Eaiq \
  'BEGIN ([A-Z ]+ )?PRIVATE KEY|authorization:[[:space:]]*(basic|bearer)|set-cookie:|cookie:|password[[:space:]]*[:=]|app[_ -]?password|client[_ -]?secret|refresh[_ -]?token' \
  "$BATCH_PATH" "$LOG_PATH"; then
  die "privacy scan found a credential-shaped value; do not publish this run"
fi

case "$RESULT:$BATCH_EXIT" in
  success:0) ;;
  success:*) die "cannot record a nonzero exit as success" ;;
  failed:0) die "cannot record exit zero as failed" ;;
esac

BASENAME="${CHUNK_ID}-${SLUG}"
BATCH_DEST="$EVIDENCE_ROOT/batches/$BASENAME.sh"
LOG_DEST="$EVIDENCE_ROOT/logs/$BASENAME.log"
RECORD_DEST="$EVIDENCE_ROOT/records/$BASENAME.env"
for target in "$BATCH_DEST" "$LOG_DEST" "$RECORD_DEST"; do
  [ ! -e "$target" ] || die "evidence target already exists: $target"
done

install -d -m 755 \
  "$EVIDENCE_ROOT/batches" \
  "$EVIDENCE_ROOT/logs" \
  "$EVIDENCE_ROOT/records"
cp -p "$BATCH_PATH" "$BATCH_DEST"
cp -p "$LOG_PATH" "$LOG_DEST"
chmod 755 "$BATCH_DEST"
chmod 644 "$LOG_DEST"

RECORD_TMP=$(mktemp "$EVIDENCE_ROOT/records/.record.XXXXXX")
{
  printf 'schema_version=1\n'
  printf 'chunk_id=%s\n' "$CHUNK_ID"
  printf 'slug=%s\n' "$SLUG"
  printf 'result=%s\n' "$RESULT"
  printf 'started_at=%s\n' "$STARTED_AT"
  printf 'finished_at=%s\n' "$FINISHED_AT"
  printf 'batch_exit=%s\n' "$BATCH_EXIT"
  printf 'batch_file=%s\n' "${BATCH_DEST#"$REPO_ROOT/"}"
  printf 'batch_sha256=%s\n' "$BATCH_SHA256"
  printf 'log_file=%s\n' "${LOG_DEST#"$REPO_ROOT/"}"
  printf 'log_sha256=%s\n' "$LOG_SHA256"
  printf 'repository_commit=%s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD)"
  printf 'repository_branch=%s\n' "$(git -C "$REPO_ROOT" branch --show-current)"
  printf 'privacy_review=automated_scan_passed_manual_review_required\n'
} > "$RECORD_TMP"
chmod 644 "$RECORD_TMP"
mv "$RECORD_TMP" "$RECORD_DEST"

[ "$(sha256sum "$BATCH_DEST" | awk '{print $1}')" = "$BATCH_SHA256" ] ||
  die "published batch hash mismatch"
[ "$(sha256sum "$LOG_DEST" | awk '{print $1}')" = "$LOG_SHA256" ] ||
  die "published log hash mismatch"

printf 'status=evidence_staged\n'
printf 'record=%s\n' "$RECORD_DEST"
printf 'batch=%s\n' "$BATCH_DEST"
printf 'log=%s\n' "$LOG_DEST"
printf 'manual_privacy_review=required_before_git_add\n'
