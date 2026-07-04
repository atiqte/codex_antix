#!/usr/bin/env python3
"""Select Betterbird messages that are not in the main converted archive.

This helper builds a dynamic post-main-archive aggregate delta.  The baseline is
the converter state database from the original Betterbird Maildir++ conversion,
not a fixed message count and not message Date headers.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import hashlib
import os
import re
import shutil
import sqlite3
import stat
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Tuple


CHUNK_SIZE = 1024 * 1024
DEFAULT_SOURCE = "/home/atiq/Betterbird-Email/betterbird-maildir"
DEFAULT_BASELINE_STATE = "/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp/.conversion-state.sqlite"
DEFAULT_WORK_ROOT = "/home/atiq/Evolution-Mailstore/post-main-archive-work"
DEFAULT_TARGET_PREFIX = "/home/atiq/Evolution-Mailstore/betterbird-post-main-archive-maildirpp"
DEFAULT_CONVERTER = "/home/atiq/codex-runs/betterbird_maildirlite_to_maildirpp.py"
DEFAULT_LOG_ROOT = "/home/atiq/Evolution-Mailstore/conversion-logs"
DEFAULT_EXPECTED_BASELINE_ROWS = 48720
DEFAULT_MAX_CANDIDATES = 10000
STATE_DIRS = ("cur", "new")
SKIP_FILE_NAMES = {
    "global-messages-db.sqlite",
    "global-messages-db.sqlite-shm",
    "global-messages-db.sqlite-wal",
    "panacea.dat",
    "foldertree.json",
    "session.json",
    "xulstore.json",
}
SKIP_SUFFIXES = (
    ".msf",
    ".wdseml",
    ".sqlite",
    ".sqlite-shm",
    ".sqlite-wal",
    ".json",
    ".dat",
)


class DeltaError(RuntimeError):
    """Raised for fatal post-archive delta safety failures."""


@dataclass(frozen=True)
class Candidate:
    path: Path
    relative_path: str
    source_folder: str
    state: str
    size: int
    mtime_ns: int


@dataclass(frozen=True)
class Baseline:
    rows: int
    exact_keys: set[Tuple[str, int, int]]
    relative_keys: set[Tuple[str, int, int]]
    hashes: set[str]


@dataclass(frozen=True)
class Selection:
    source: Path
    baseline_state: Path
    baseline_rows: int
    source_candidates: int
    selected: List[Candidate]
    selected_bytes: int
    excluded_exact: int
    excluded_relative: int
    excluded_hash: int
    hash_checked: int
    skipped: Counter
    folders: Counter
    states: Counter


def resolve_path(value: str | Path) -> Path:
    return Path(value).expanduser().resolve()


def timestamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def validate_run_id(run_id: str) -> str:
    if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._-]{0,63}", run_id):
        raise DeltaError(f"Unsafe run id: {run_id!r}")
    return run_id


def target_for_run(prefix: Path, run_id: str) -> Path:
    return Path(str(prefix) + "-" + run_id)


def run_work_dir(work_root: Path, run_id: str) -> Path:
    return work_root / run_id


def staging_for_run(work_root: Path, run_id: str) -> Path:
    return run_work_dir(work_root, run_id) / "staging-betterbird-maildir"


def is_relative_to(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def validate_source(source: Path) -> None:
    if not source.exists() or not source.is_dir():
        raise DeltaError(f"Source directory does not exist: {source}")
    if not (source / "prefs.js").is_file():
        raise DeltaError(f"Source does not contain Betterbird marker prefs.js: {source}")
    if not (source / "Mail").is_dir():
        raise DeltaError(f"Source does not contain Betterbird Mail directory: {source}")


def should_skip_file(path: Path) -> Optional[str]:
    name_lower = path.name.lower()
    if name_lower in SKIP_FILE_NAMES:
        return "metadata-file"
    if name_lower.endswith(SKIP_SUFFIXES):
        return "metadata-suffix"
    if path.is_symlink():
        return "symlink"
    if not path.is_file():
        return "not-regular-file"
    return None


def relative_key(path_text: str, current_source: Path) -> Optional[str]:
    path = Path(path_text)
    try:
        return path.relative_to(current_source).as_posix()
    except ValueError:
        pass

    parts = path.parts
    if "Mail" in parts:
        index = parts.index("Mail")
        return Path(*parts[index:]).as_posix()
    return None


def iter_candidates(source: Path) -> Iterator[Candidate]:
    for dirpath, dirnames, filenames in os.walk(source):
        dirnames[:] = sorted(d for d in dirnames if d != "tmp")
        state = os.path.basename(dirpath)
        if state not in STATE_DIRS:
            continue
        state_dir = Path(dirpath)
        folder = state_dir.parent
        for name in sorted(filenames):
            path = state_dir / name
            skip_reason = should_skip_file(path)
            if skip_reason:
                continue
            try:
                st = path.stat()
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            yield Candidate(
                path=path,
                relative_path=path.relative_to(source).as_posix(),
                source_folder=folder.relative_to(source).as_posix(),
                state=state,
                size=st.st_size,
                mtime_ns=st.st_mtime_ns,
            )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_baseline(
    state_path: Path,
    source: Path,
    expected_rows: Optional[int] = DEFAULT_EXPECTED_BASELINE_ROWS,
    allow_row_mismatch: bool = False,
) -> Baseline:
    if not state_path.exists() or not state_path.is_file():
        raise DeltaError(f"Baseline state database does not exist: {state_path}")

    exact_keys: set[Tuple[str, int, int]] = set()
    relative_keys: set[Tuple[str, int, int]] = set()
    hashes: set[str] = set()

    conn = sqlite3.connect(str(state_path))
    try:
        rows = conn.execute(
            """
            SELECT source_path, source_size, source_mtime_ns, source_sha256
            FROM processed
            WHERE status = 'copied'
            """
        ).fetchall()
    except sqlite3.Error as exc:
        raise DeltaError(f"Could not read baseline state database: {exc}") from exc
    finally:
        conn.close()

    for source_path, size, mtime_ns, source_sha256 in rows:
        size_i = int(size)
        mtime_i = int(mtime_ns)
        source_text = str(source_path)
        exact_keys.add((source_text, size_i, mtime_i))
        rel = relative_key(source_text, source)
        if rel:
            relative_keys.add((rel, size_i, mtime_i))
        if source_sha256:
            hashes.add(str(source_sha256))

    row_count = len(rows)
    if expected_rows is not None and row_count != expected_rows and not allow_row_mismatch:
        raise DeltaError(
            f"Baseline copied row count mismatch: expected {expected_rows}, actual {row_count}. "
            "Use --allow-baseline-row-mismatch only after manual review."
        )

    return Baseline(rows=row_count, exact_keys=exact_keys, relative_keys=relative_keys, hashes=hashes)


def select_post_archive_candidates(
    source: Path,
    baseline_state: Path,
    expected_baseline_rows: Optional[int] = DEFAULT_EXPECTED_BASELINE_ROWS,
    allow_baseline_row_mismatch: bool = False,
    max_candidates: int = DEFAULT_MAX_CANDIDATES,
    allow_large_delta: bool = False,
    hash_fallback: bool = True,
) -> Selection:
    source = resolve_path(source)
    baseline_state = resolve_path(baseline_state)
    validate_source(source)
    baseline = load_baseline(
        baseline_state,
        source,
        expected_rows=expected_baseline_rows,
        allow_row_mismatch=allow_baseline_row_mismatch,
    )

    selected: List[Candidate] = []
    selected_bytes = 0
    skipped: Counter = Counter()
    folders: Counter = Counter()
    states: Counter = Counter()
    source_candidates = 0
    excluded_exact = 0
    excluded_relative = 0
    excluded_hash = 0
    hash_checked = 0

    for candidate in iter_candidates(source):
        source_candidates += 1
        exact_key = (str(candidate.path), candidate.size, candidate.mtime_ns)
        if exact_key in baseline.exact_keys:
            excluded_exact += 1
            continue
        rel_key = (candidate.relative_path, candidate.size, candidate.mtime_ns)
        if rel_key in baseline.relative_keys:
            excluded_relative += 1
            continue
        if hash_fallback:
            hash_checked += 1
            if sha256_file(candidate.path) in baseline.hashes:
                excluded_hash += 1
                continue

        selected.append(candidate)
        selected_bytes += candidate.size
        folders[candidate.source_folder] += 1
        states[candidate.state] += 1

    if len(selected) > max_candidates and not allow_large_delta:
        raise DeltaError(
            f"status=blocked_large_delta_requires_review selected={len(selected)} max_candidates={max_candidates}"
        )

    return Selection(
        source=source,
        baseline_state=baseline_state,
        baseline_rows=baseline.rows,
        source_candidates=source_candidates,
        selected=selected,
        selected_bytes=selected_bytes,
        excluded_exact=excluded_exact,
        excluded_relative=excluded_relative,
        excluded_hash=excluded_hash,
        hash_checked=hash_checked,
        skipped=skipped,
        folders=folders,
        states=states,
    )


def ensure_safe_output_paths(source: Path, work_dir: Path, staging: Path, target: Path) -> None:
    for path, label in ((work_dir, "work_dir"), (staging, "staging"), (target, "target")):
        if path.exists():
            raise DeltaError(f"{label} already exists, refusing to overwrite: {path}")
        if is_relative_to(path, source):
            raise DeltaError(f"{label} is inside source tree, refusing: {path}")


def copy_exact(src: Path, dst: Path) -> str:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        raise DeltaError(f"Refusing to overwrite existing staged file: {dst}")
    shutil.copy2(src, dst)
    src_hash = sha256_file(src)
    dst_hash = sha256_file(dst)
    if src_hash != dst_hash:
        raise DeltaError(f"Staged hash mismatch: {src} -> {dst}")
    return src_hash


def stage_selection(selection: Selection, work_root: Path, target_prefix: Path, run_id: str) -> Path:
    run_id = validate_run_id(run_id)
    work_root = resolve_path(work_root)
    target_prefix = resolve_path(target_prefix)
    work_dir = run_work_dir(work_root, run_id)
    staging = staging_for_run(work_root, run_id)
    target = target_for_run(target_prefix, run_id)
    ensure_safe_output_paths(selection.source, work_dir, staging, target)

    if not selection.selected:
        return staging

    (staging / "Mail").mkdir(parents=True, exist_ok=False)
    shutil.copy2(selection.source / "prefs.js", staging / "prefs.js")

    manifest = work_dir / "selected-files.tsv"
    summary = work_dir / "summary.tsv"
    with manifest.open("w", encoding="utf-8", newline="") as manifest_handle:
        writer = csv.DictWriter(
            manifest_handle,
            fieldnames=["sha256", "size", "mtime_ns", "state", "source_folder", "relative_path", "source_path"],
            delimiter="\t",
            lineterminator="\n",
        )
        writer.writeheader()
        for candidate in selection.selected:
            dst = staging / candidate.relative_path
            digest = copy_exact(candidate.path, dst)
            writer.writerow(
                {
                    "sha256": digest,
                    "size": candidate.size,
                    "mtime_ns": candidate.mtime_ns,
                    "state": candidate.state,
                    "source_folder": candidate.source_folder,
                    "relative_path": candidate.relative_path,
                    "source_path": str(candidate.path),
                }
            )

    with summary.open("w", encoding="utf-8", newline="") as summary_handle:
        writer = csv.DictWriter(summary_handle, fieldnames=["key", "value"], delimiter="\t", lineterminator="\n")
        writer.writeheader()
        for key, value in selection_summary(selection, run_id, work_root, target_prefix).items():
            writer.writerow({"key": key, "value": value})

    return staging


def selection_summary(
    selection: Selection,
    run_id: str,
    work_root: Path,
    target_prefix: Path,
) -> Dict[str, object]:
    staging = staging_for_run(resolve_path(work_root), run_id)
    target = target_for_run(resolve_path(target_prefix), run_id)
    return {
        "run_id": run_id,
        "source": str(selection.source),
        "baseline_state": str(selection.baseline_state),
        "baseline_copied_rows": selection.baseline_rows,
        "source_candidate_count": selection.source_candidates,
        "post_archive_candidate_count": len(selection.selected),
        "post_archive_total_bytes": selection.selected_bytes,
        "excluded_exact": selection.excluded_exact,
        "excluded_relative": selection.excluded_relative,
        "excluded_hash": selection.excluded_hash,
        "hash_checked": selection.hash_checked,
        "selected_cur": selection.states.get("cur", 0),
        "selected_new": selection.states.get("new", 0),
        "work_dir": str(run_work_dir(resolve_path(work_root), run_id)),
        "staging": str(staging),
        "target": str(target),
    }


def print_key_values(rows: Dict[str, object]) -> None:
    for key, value in rows.items():
        print(f"{key}={value}")


def print_folder_counts(selection: Selection) -> None:
    for folder, count in selection.folders.most_common():
        print(f"selected_folder\t{count}\t{folder}")


def status_for_selection(selection: Selection) -> str:
    return "no_post_archive_mail" if not selection.selected else "post_archive_mail_found"


def build_selection_from_args(args: argparse.Namespace) -> Selection:
    expected_rows = None if args.expected_baseline_rows < 0 else args.expected_baseline_rows
    return select_post_archive_candidates(
        source=Path(args.source),
        baseline_state=Path(args.baseline_state),
        expected_baseline_rows=expected_rows,
        allow_baseline_row_mismatch=args.allow_baseline_row_mismatch,
        max_candidates=args.max_candidates,
        allow_large_delta=args.allow_large_delta,
        hash_fallback=not args.no_hash_fallback,
    )


def cmd_audit(args: argparse.Namespace) -> int:
    run_id = validate_run_id(args.run_id or timestamp())
    selection = build_selection_from_args(args)
    print("mode=audit")
    print_key_values(selection_summary(selection, run_id, Path(args.work_root), Path(args.target_prefix)))
    print_folder_counts(selection)
    print(f"status={status_for_selection(selection)}")
    return 0


def cmd_stage(args: argparse.Namespace) -> int:
    run_id = validate_run_id(args.run_id or timestamp())
    selection = build_selection_from_args(args)
    print("mode=stage")
    print_key_values(selection_summary(selection, run_id, Path(args.work_root), Path(args.target_prefix)))
    print_folder_counts(selection)
    if not selection.selected:
        print("status=no_post_archive_mail")
        return 0
    staging = stage_selection(selection, Path(args.work_root), Path(args.target_prefix), run_id)
    cur_count = sum(1 for p in staging.glob("**/cur/*") if p.is_file())
    new_count = sum(1 for p in staging.glob("**/new/*") if p.is_file())
    tmp_count = sum(1 for p in staging.glob("**/tmp/*") if p.is_file())
    print(f"staging_cur_count={cur_count}")
    print(f"staging_new_count={new_count}")
    print(f"staging_tmp_count={tmp_count}")
    print("status=staging_ready")
    return 0


def cmd_plan_convert(args: argparse.Namespace) -> int:
    run_id = validate_run_id(args.run_id)
    work_root = resolve_path(args.work_root)
    target_prefix = resolve_path(args.target_prefix)
    staging = staging_for_run(work_root, run_id)
    target = target_for_run(target_prefix, run_id)
    converter = resolve_path(args.converter)
    log_root = resolve_path(args.log_root)
    dry_log = log_root / f"post-main-archive-{run_id}-dryrun"
    copy_log = log_root / f"post-main-archive-{run_id}-copy"
    print("mode=plan-convert")
    print(f"run_id={run_id}")
    print(f"staging={staging}")
    print(f"target={target}")
    print(f"converter={converter}")
    print("dry_run_command=")
    print(
        f'python3 "{converter}" --source "{staging}" --target "{target}" '
        f'--log-dir "{dry_log}" --dry-run'
    )
    print("copy_command=")
    print(
        f'python3 "{converter}" --source "{staging}" --target "{target}" '
        f'--log-dir "{copy_log}" --copy --resume'
    )
    print("verify_command=")
    print(
        f'python3 "{converter}" --source "{staging}" --target "{target}" '
        f'--log-dir "{copy_log}" --verify --verify-hash'
    )
    print("status=ok")
    return 0


def add_selection_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--source", default=DEFAULT_SOURCE, help="Betterbird maildir-lite source root")
    parser.add_argument("--baseline-state", default=DEFAULT_BASELINE_STATE, help="Main archive conversion state DB")
    parser.add_argument("--work-root", default=DEFAULT_WORK_ROOT, help="Root for timestamped staging work directories")
    parser.add_argument("--target-prefix", default=DEFAULT_TARGET_PREFIX, help="Maildir++ target path prefix before RUN_ID")
    parser.add_argument("--run-id", help="Safe run id; defaults to current timestamp for audit/stage")
    parser.add_argument("--expected-baseline-rows", type=int, default=DEFAULT_EXPECTED_BASELINE_ROWS)
    parser.add_argument("--allow-baseline-row-mismatch", action="store_true")
    parser.add_argument("--max-candidates", type=int, default=DEFAULT_MAX_CANDIDATES)
    parser.add_argument("--allow-large-delta", action="store_true")
    parser.add_argument("--no-hash-fallback", action="store_true", help="Do not exclude unmatched candidates by SHA256")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build a dynamic post-main-archive Betterbird aggregate delta."
    )
    subparsers = parser.add_subparsers(dest="mode", required=True)

    audit = subparsers.add_parser("audit", help="Report Betterbird messages absent from the main archive baseline")
    add_selection_args(audit)
    audit.set_defaults(func=cmd_audit)

    stage = subparsers.add_parser("stage", help="Copy selected post-main-archive messages into a clean staging tree")
    add_selection_args(stage)
    stage.set_defaults(func=cmd_stage)

    plan = subparsers.add_parser("plan-convert", help="Print converter commands for a staged RUN_ID")
    plan.add_argument("--run-id", required=True, help="Run id used for stage")
    plan.add_argument("--work-root", default=DEFAULT_WORK_ROOT)
    plan.add_argument("--target-prefix", default=DEFAULT_TARGET_PREFIX)
    plan.add_argument("--converter", default=DEFAULT_CONVERTER)
    plan.add_argument("--log-root", default=DEFAULT_LOG_ROOT)
    plan.set_defaults(func=cmd_plan_convert)

    return parser


def main(argv: Optional[List[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except DeltaError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
