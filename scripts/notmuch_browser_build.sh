#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
BUN=${BUN_BIN:-bun}
BUILD_OUTPUT=${NOTMUCH_BROWSER_BUILD_OUTPUT:-"$REPO_ROOT/notmuch-browser"}
EXPECTED_BUN_VERSION=${NOTMUCH_BROWSER_EXPECTED_BUN_VERSION:-"1.3.14"}

die() {
  printf 'status=blocked\nreason=%s\n' "$*" >&2
  exit 1
}

require_tools() {
  command -v go >/dev/null 2>&1 || die "go is not available"
  command -v "$BUN" >/dev/null 2>&1 || die "bun is not available: $BUN"
  actual_bun=$("$BUN" --version)
  [ "$actual_bun" = "$EXPECTED_BUN_VERSION" ] ||
    die "unexpected Bun version: $actual_bun (expected $EXPECTED_BUN_VERSION)"
}

prepare() {
  require_tools
  cd "$REPO_ROOT"
  "$BUN" install --frozen-lockfile
  go mod download
  go mod verify
}

generate() {
  require_tools
  cd "$REPO_ROOT"
  go tool templ generate
  "$BUN" run css:build
}

generated_manifest() {
  (
    cd "$REPO_ROOT"
    find internal/notmuchbrowser -maxdepth 1 -type f -name '*_templ.go' -print
    printf '%s\n' internal/notmuchbrowser/static/app.css
  ) | LC_ALL=C sort | while IFS= read -r file; do
    (
      cd "$REPO_ROOT"
      sha256sum "$file"
    )
  done
}

verify_generated() {
  require_tools
  before=$(mktemp)
  after=$(mktemp)
  trap 'rm -f "$before" "$after"' EXIT HUP INT TERM
  generated_manifest > "$before"
  generate
  generated_manifest > "$after"
  if ! diff -u "$before" "$after"; then
    die "templ or Tailwind output is not reproducible"
  fi
  rm -f "$before" "$after"
  trap - EXIT HUP INT TERM
  printf 'status=generated_files_reproducible\n'
}

test_project() {
  require_tools
  cd "$REPO_ROOT"
  go test -count=1 ./...
  go vet ./...
  go test -race -count=1 ./...
  for script in scripts/*.sh; do
    sh -n "$script"
  done
  asset_bytes=$(find internal/notmuchbrowser/static -maxdepth 1 -type f -exec wc -c {} + |
    awk 'END { print $1 }')
  [ "$asset_bytes" -le 92160 ] ||
    die "embedded static assets exceed 90 KiB: $asset_bytes bytes"
  printf 'embedded_static_bytes=%s\n' "$asset_bytes"
}

build_project() {
  require_tools
  cd "$REPO_ROOT"
  go build -trimpath -buildvcs=false -ldflags="-s -w" -o "$BUILD_OUTPUT" ./cmd/notmuch-browser
  chmod 755 "$BUILD_OUTPUT"
  binary_bytes=$(wc -c < "$BUILD_OUTPUT" | tr -d ' ')
  [ "$binary_bytes" -le 12582912 ] ||
    die "stripped binary exceeds 12 MiB: $binary_bytes bytes"
  printf 'binary=%s\n' "$BUILD_OUTPUT"
  sha256sum "$BUILD_OUTPUT"
  printf 'binary_bytes=%s\n' "$binary_bytes"
}

usage() {
  cat <<'EOF'
Usage: scripts/notmuch_browser_build.sh {prepare|generate|verify-generated|test|build|all}

Environment:
  BUN_BIN                              Bun executable (default: bun)
  NOTMUCH_BROWSER_EXPECTED_BUN_VERSION Required Bun version (default: 1.3.14)
  NOTMUCH_BROWSER_BUILD_OUTPUT         Build destination (default: ./notmuch-browser)
EOF
}

command_name=${1:-}
case "$command_name" in
  prepare) prepare ;;
  generate) generate ;;
  verify-generated) verify_generated ;;
  test) test_project ;;
  build) build_project ;;
  all)
    prepare
    generate
    verify_generated
    test_project
    build_project
    ;;
  *) usage; exit 2 ;;
esac
