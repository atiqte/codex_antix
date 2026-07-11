#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ENGINE_SOURCE="$REPO_ROOT/src/provider_live_archive.py"
TRANSPORT_SOURCE="$REPO_ROOT/src/betterbird_profile_transport.py"
CONTROL_SOURCE="$REPO_ROOT/scripts/provider_live_archive_control.sh"
SETUP_SOURCE="$REPO_ROOT/scripts/provider_live_archive_setup.sh"

LIB_DIR=${PROVIDER_LIVE_ARCHIVE_LIB_DIR:-"$HOME/.local/lib"}
BIN_DIR=${PROVIDER_LIVE_ARCHIVE_BIN_DIR:-"$HOME/.local/bin"}
ENGINE_TARGET="$LIB_DIR/provider-live-archive.py"
TRANSPORT_TARGET="$LIB_DIR/betterbird_profile_transport.py"
CONTROL_TARGET="$BIN_DIR/provider-live-archive-control"
TOOL_BACKUP_ROOT=${PROVIDER_LIVE_ARCHIVE_TOOL_BACKUP_ROOT:-/mail/Backups/provider-live-archive}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
need_file() { [ -f "$1" ] || die "missing payload file: $1"; }

verify_sources() {
  need_file "$ENGINE_SOURCE"
  need_file "$TRANSPORT_SOURCE"
  need_file "$CONTROL_SOURCE"
  command -v python3 >/dev/null 2>&1 || die "python3 is required"
  command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required"
  python3 -m py_compile "$ENGINE_SOURCE" "$TRANSPORT_SOURCE"
  sh -n "$CONTROL_SOURCE"
}

install_payload() {
  verify_sources
  mkdir -p "$LIB_DIR" "$BIN_DIR"
  chmod 700 "$LIB_DIR" "$BIN_DIR" 2>/dev/null || true
  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$TOOL_BACKUP_ROOT/tool-refresh-$stamp"
  mkdir -p "$backup"
  chmod 700 "$backup"
  for target in "$ENGINE_TARGET" "$TRANSPORT_TARGET" "$CONTROL_TARGET"; do
    [ ! -f "$target" ] || cp -p "$target" "$backup/$(basename "$target")"
  done
  install -m 700 "$ENGINE_SOURCE" "$ENGINE_TARGET"
  install -m 600 "$TRANSPORT_SOURCE" "$TRANSPORT_TARGET"
  install -m 700 "$CONTROL_SOURCE" "$CONTROL_TARGET"
  python3 -m py_compile "$ENGINE_TARGET" "$TRANSPORT_TARGET"
  sh -n "$CONTROL_TARGET"
  sha256sum "$ENGINE_TARGET" "$TRANSPORT_TARGET" "$CONTROL_TARGET"
  "$CONTROL_TARGET" layout
  "$CONTROL_TARGET" simulate-alert
  printf 'status=provider_live_archive_tools_installed\n'
  printf 'backup=%s\n' "$backup"
}

verify_install() {
  [ -x "$ENGINE_TARGET" ] || die "missing installed engine: $ENGINE_TARGET"
  [ -r "$TRANSPORT_TARGET" ] || die "missing installed transport: $TRANSPORT_TARGET"
  [ -x "$CONTROL_TARGET" ] || die "missing installed control: $CONTROL_TARGET"
  python3 -m py_compile "$ENGINE_TARGET" "$TRANSPORT_TARGET"
  sh -n "$CONTROL_TARGET"
  sha256sum "$ENGINE_TARGET" "$TRANSPORT_TARGET" "$CONTROL_TARGET"
  "$CONTROL_TARGET" status
}

make_bundle() {
  verify_sources
  out=${1:-}
  [ -n "$out" ] || die "bundle requires an output directory"
  command -v tar >/dev/null 2>&1 || die "tar is required"
  mkdir -p "$out"
  out=$(CDPATH= cd -- "$out" && pwd)
  bundle="$out/provider-live-archive-offline.tar.gz"
  checksum="$bundle.sha256"
  [ ! -e "$bundle" ] || die "bundle already exists: $bundle"
  (
    cd "$REPO_ROOT"
    tar -czf "$bundle" \
      src/provider_live_archive.py \
      src/betterbird_profile_transport.py \
      scripts/provider_live_archive_control.sh \
      scripts/provider_live_archive_setup.sh
  )
  (cd "$out" && sha256sum "$(basename "$bundle")" > "$(basename "$checksum")")
  printf 'bundle=%s\nchecksum=%s\n' "$bundle" "$checksum"
}

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") {verify-sources|install|verify-install|bundle OUT_DIR}"
}

case ${1:-} in
  verify-sources) verify_sources ;;
  install) install_payload ;;
  verify-install) verify_install ;;
  bundle) make_bundle "${2:-}" ;;
  help|-h|--help|'') usage ;;
  *) usage >&2; exit 2 ;;
esac
