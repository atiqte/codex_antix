#!/usr/bin/env python3
"""Convert Betterbird/Thunderbird maildir-lite trees to canonical Maildir++.

The converter is intentionally conservative:

* the source tree is never modified;
* dry-run is the default mode;
* only files directly inside source ``cur`` and ``new`` directories are copied;
* ``tmp`` and Betterbird metadata are ignored;
* messages are copied byte-for-byte through target ``tmp`` and atomically
  renamed into target ``cur`` or ``new``;
* duplicate messages are kept, but logged for review.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import email.parser
import email.policy
import hashlib
import json
import os
import re
import shutil
import socket
import sqlite3
import sys
import time
import uuid
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Tuple


CHUNK_SIZE = 1024 * 1024
MAX_HEADER_BYTES = 2 * 1024 * 1024
MAILDIR_INFO_PREFIX = ":2,"
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


class ConversionError(RuntimeError):
    """Raised for fatal safety or conversion errors."""


@dataclass(frozen=True)
class Settings:
    source: Path
    target: Path
    log_dir: Path
    state_path: Path
    mode: str
    resume: bool
    verify_hash: bool
    allow_unmarked_source: bool
    max_header_bytes: int = MAX_HEADER_BYTES


@dataclass(frozen=True)
class Candidate:
    source_file: Path
    source_folder: Path
    source_state: str
    size: int
    mtime_ns: int


@dataclass(frozen=True)
class FolderMapping:
    source_folder: Path
    relative_source: str
    target_name: str
    target_folder: Path
    collision_note: str = ""


class TsvWriter:
    def __init__(self, path: Path, fieldnames: List[str]) -> None:
        self.path = path
        self.file = path.open("w", newline="", encoding="utf-8")
        self.writer = csv.DictWriter(self.file, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore")
        self.writer.writeheader()

    def write(self, row: Dict[str, object]) -> None:
        self.writer.writerow({k: "" if v is None else v for k, v in row.items()})
        self.file.flush()

    def close(self) -> None:
        self.file.close()


class JsonlWriter:
    def __init__(self, path: Path) -> None:
        self.file = path.open("w", encoding="utf-8")

    def write(self, row: Dict[str, object]) -> None:
        self.file.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
        self.file.flush()

    def close(self) -> None:
        self.file.close()


def resolve_path(path: Path) -> Path:
    return path.expanduser().resolve()


def is_relative_to(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def timestamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def utc_now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")


def mkdir_maildir(path: Path, dry_run: bool) -> None:
    if dry_run:
        return
    for name in ("cur", "new", "tmp"):
        (path / name).mkdir(parents=True, exist_ok=True)


def fsync_directory(path: Path) -> None:
    if os.name == "nt":
        return
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def sanitize_component(component: str) -> str:
    if component.endswith(".sbd"):
        component = component[:-4]
    component = component.replace(".", "_").replace(" ", "_").replace(":", "_")
    component = re.sub(r"[^A-Za-z0-9_-]+", "_", component)
    component = re.sub(r"_+", "_", component).strip("_")
    return component or "folder"


def source_folder_to_maildirpp_name(source_root: Path, source_folder: Path) -> str:
    rel_parts = list(source_folder.relative_to(source_root).parts)
    if rel_parts and rel_parts[0] == "Mail":
        rel_parts = rel_parts[1:]
    sanitized = [sanitize_component(part) for part in rel_parts if part not in ("cur", "new", "tmp")]
    if not sanitized:
        return ""
    return "." + ".".join(sanitized)


def discover_source_folders(source: Path) -> List[Path]:
    folders: List[Path] = []
    for root, dirs, _files in os.walk(source):
        root_path = Path(root)
        dirs[:] = sorted(d for d in dirs if d != "tmp")
        dir_set = set(dirs)
        if "cur" in dir_set or "new" in dir_set:
            folders.append(root_path)
    return sorted(set(folders), key=lambda p: str(p.relative_to(source)))


def build_folder_mappings(source: Path, target: Path, source_folders: List[Path]) -> Dict[Path, FolderMapping]:
    used: Dict[str, int] = {}
    mappings: Dict[Path, FolderMapping] = {}
    for folder in source_folders:
        base_name = source_folder_to_maildirpp_name(source, folder)
        if not base_name:
            base_name = ".Root"
        target_name = base_name
        collision_note = ""
        if target_name in used:
            used[target_name] += 1
            target_name = f"{base_name}__{used[base_name]}"
            collision_note = f"collision-renamed-from={base_name}"
        else:
            used[target_name] = 1
        mappings[folder] = FolderMapping(
            source_folder=folder,
            relative_source=str(folder.relative_to(source)),
            target_name=target_name,
            target_folder=target / target_name,
            collision_note=collision_note,
        )
    return mappings


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


def iter_candidates(source_folders: Iterable[Path]) -> Iterator[Candidate]:
    for folder in source_folders:
        for state in ("cur", "new"):
            state_dir = folder / state
            if not state_dir.is_dir():
                continue
            for child in sorted(state_dir.iterdir(), key=lambda p: p.name):
                try:
                    stat = child.stat()
                except OSError:
                    continue
                yield Candidate(
                    source_file=child,
                    source_folder=folder,
                    source_state=state,
                    size=stat.st_size,
                    mtime_ns=stat.st_mtime_ns,
                )


def split_maildir_flags(name: str) -> Tuple[str, str]:
    marker_index = name.find(MAILDIR_INFO_PREFIX)
    if marker_index == -1:
        return name, ""
    return name[:marker_index], name[marker_index + len(MAILDIR_INFO_PREFIX) :]


def target_flags(candidate: Candidate) -> str:
    _base, flags = split_maildir_flags(candidate.source_file.name)
    if flags:
        return flags
    if candidate.source_state == "cur":
        return "S"
    return ""


def target_state(candidate: Candidate) -> str:
    return candidate.source_state


def safe_hostname() -> str:
    return sanitize_component(socket.gethostname()) or "host"


def generate_maildir_name(flags: str, sequence: int) -> str:
    now_ns = time.time_ns()
    base = f"{now_ns}.M{now_ns % 1_000_000}P{os.getpid()}Q{sequence}.{safe_hostname()}"
    if flags:
        return f"{base}{MAILDIR_INFO_PREFIX}{flags}"
    return base


def unique_target_path(target_dir: Path, flags: str, sequence: int) -> Path:
    for attempt in range(10_000):
        name = generate_maildir_name(flags, sequence + attempt)
        final = target_dir / name
        if not final.exists():
            return final
    raise ConversionError(f"Could not generate a unique target filename in {target_dir}")


def read_header_bytes(path: Path, max_header_bytes: int) -> Tuple[bytes, str]:
    data = bytearray()
    warning = ""
    with path.open("rb") as f:
        while len(data) < max_header_bytes:
            chunk = f.read(8192)
            if not chunk:
                break
            data.extend(chunk)
            pos = data.find(b"\r\n\r\n")
            if pos != -1:
                return bytes(data[: pos + 4]), warning
            pos = data.find(b"\n\n")
            if pos != -1:
                return bytes(data[: pos + 2]), warning
    if len(data) >= max_header_bytes:
        warning = "header-scan-limit-reached"
    return bytes(data), warning


def parse_message_id(path: Path, max_header_bytes: int) -> Tuple[str, str]:
    try:
        header_bytes, warning = read_header_bytes(path, max_header_bytes)
        parser = email.parser.BytesHeaderParser(policy=email.policy.default)
        message = parser.parsebytes(header_bytes)
        message_id = message.get("Message-ID") or message.get("Message-Id") or ""
        message_id = str(message_id).strip()
        if not message_id:
            warning = append_warning(warning, "missing-message-id")
        return message_id, warning
    except Exception as exc:  # pragma: no cover - defensive guard for malformed real mail.
        return "", f"malformed-headers:{type(exc).__name__}:{exc}"


def append_warning(existing: str, addition: str) -> str:
    if not existing:
        return addition
    if not addition:
        return existing
    return existing + ";" + addition


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_atomic_with_hash(source: Path, tmp_dir: Path, final_path: Path) -> str:
    tmp_dir.mkdir(parents=True, exist_ok=True)
    tmp_path = tmp_dir / f".convert-{uuid.uuid4().hex}.tmp"
    digest = hashlib.sha256()
    try:
        with source.open("rb") as src, tmp_path.open("xb") as dst:
            for chunk in iter(lambda: src.read(CHUNK_SIZE), b""):
                digest.update(chunk)
                dst.write(chunk)
            dst.flush()
            os.fsync(dst.fileno())
        if final_path.exists():
            raise ConversionError(f"Refusing to overwrite existing target file: {final_path}")
        os.replace(tmp_path, final_path)
        fsync_directory(final_path.parent)
        return digest.hexdigest()
    except Exception:
        try:
            if tmp_path.exists():
                tmp_path.unlink()
        finally:
            raise


def init_db(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS processed (
            source_path TEXT PRIMARY KEY,
            source_size INTEGER NOT NULL,
            source_mtime_ns INTEGER NOT NULL,
            source_sha256 TEXT NOT NULL,
            target_path TEXT NOT NULL,
            status TEXT NOT NULL,
            message_id TEXT,
            copied_at TEXT NOT NULL
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_processed_status ON processed(status)")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS message_ids (
            message_id TEXT NOT NULL,
            source_path TEXT NOT NULL,
            target_path TEXT NOT NULL
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_message_ids_id ON message_ids(message_id)")
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS hashes (
            sha256 TEXT NOT NULL,
            source_path TEXT NOT NULL,
            target_path TEXT NOT NULL
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_hashes_sha ON hashes(sha256)")
    conn.commit()
    return conn


def already_copied(conn: sqlite3.Connection, candidate: Candidate) -> Optional[str]:
    row = conn.execute(
        """
        SELECT target_path FROM processed
        WHERE source_path = ? AND source_size = ? AND source_mtime_ns = ? AND status = 'copied'
        """,
        (str(candidate.source_file), candidate.size, candidate.mtime_ns),
    ).fetchone()
    if not row:
        return None
    target_path = row[0]
    if Path(target_path).exists():
        return target_path
    return None


def record_processed(
    conn: sqlite3.Connection,
    candidate: Candidate,
    source_sha256: str,
    target_path: str,
    status: str,
    message_id: str,
) -> None:
    conn.execute(
        """
        INSERT OR REPLACE INTO processed
        (source_path, source_size, source_mtime_ns, source_sha256, target_path, status, message_id, copied_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            str(candidate.source_file),
            candidate.size,
            candidate.mtime_ns,
            source_sha256,
            target_path,
            status,
            message_id,
            utc_now_iso(),
        ),
    )
    if message_id:
        conn.execute(
            "INSERT INTO message_ids(message_id, source_path, target_path) VALUES (?, ?, ?)",
            (message_id, str(candidate.source_file), target_path),
        )
    if source_sha256:
        conn.execute(
            "INSERT INTO hashes(sha256, source_path, target_path) VALUES (?, ?, ?)",
            (source_sha256, str(candidate.source_file), target_path),
        )
    conn.commit()


def duplicate_warning(
    conn: sqlite3.Connection, message_id: str, source_sha256: str
) -> Tuple[str, List[Tuple[str, str, str]]]:
    warnings: List[str] = []
    duplicate_rows: List[Tuple[str, str, str]] = []
    if message_id:
        row = conn.execute(
            "SELECT source_path, target_path FROM message_ids WHERE message_id = ? LIMIT 1",
            (message_id,),
        ).fetchone()
        if row:
            warnings.append("duplicate-message-id")
            duplicate_rows.append(("message-id", message_id, row[0]))
    if source_sha256:
        row = conn.execute(
            "SELECT source_path, target_path FROM hashes WHERE sha256 = ? LIMIT 1",
            (source_sha256,),
        ).fetchone()
        if row:
            warnings.append("duplicate-content-hash")
            duplicate_rows.append(("sha256", source_sha256, row[0]))
    return ";".join(warnings), duplicate_rows


def validate_safety(settings: Settings) -> None:
    source = settings.source
    target = settings.target
    if not source.exists() or not source.is_dir():
        raise ConversionError(f"Source directory does not exist: {source}")
    if settings.mode == "copy" and not settings.allow_unmarked_source:
        if not (source / "prefs.js").is_file() or not (source / "Mail").is_dir():
            raise ConversionError(
                "Refusing --copy: source does not look like a staged Betterbird profile "
                "(expected prefs.js and Mail/). Use --allow-unmarked-source only for a verified copy."
            )
    dangerous_targets = {Path("/"), Path("/home"), Path.home().resolve()}
    if target in dangerous_targets:
        raise ConversionError(f"Refusing unsafe target path: {target}")
    if is_relative_to(target, source):
        raise ConversionError("Refusing target inside source tree")
    if source == target or is_relative_to(source, target):
        raise ConversionError("Refusing source inside target tree")
    if settings.mode == "copy" and target.exists() and not settings.resume:
        existing = [p for p in target.iterdir() if p.name not in (".conversion-state.sqlite",)]
        if existing:
            raise ConversionError("Target exists and is not empty. Use --resume to continue safely.")


def open_logs(log_dir: Path) -> Tuple[JsonlWriter, Dict[str, TsvWriter]]:
    log_dir.mkdir(parents=True, exist_ok=True)
    jsonl = JsonlWriter(log_dir / "conversion.jsonl")
    writers = {
        "folders": TsvWriter(
            log_dir / "folder-map.tsv",
            ["source_folder", "relative_source", "target_name", "target_folder", "note"],
        ),
        "summary": TsvWriter(
            log_dir / "summary.tsv",
            [
                "target_folder",
                "source_candidates",
                "copied",
                "dry_run_copy",
                "skipped",
                "errors",
                "bytes",
            ],
        ),
        "duplicates": TsvWriter(
            log_dir / "duplicates.tsv",
            ["kind", "key", "source_path", "target_path", "first_seen_source"],
        ),
        "errors": TsvWriter(
            log_dir / "errors.tsv",
            ["source_path", "target_path", "error"],
        ),
        "skipped": TsvWriter(
            log_dir / "skipped.tsv",
            ["source_path", "target_path", "reason"],
        ),
    }
    return jsonl, writers


def copy_state_snapshot(active_state: Path, log_state: Path) -> None:
    if active_state == log_state or not active_state.exists():
        return
    shutil.copy2(active_state, log_state)


def event_base(
    candidate: Candidate,
    mapping: FolderMapping,
    target_path: str,
    status: str,
    message_id: str = "",
    flags: str = "",
    sha256: str = "",
    warning: str = "",
    error: str = "",
) -> Dict[str, object]:
    return {
        "status": status,
        "source_path": str(candidate.source_file),
        "target_path": target_path,
        "source_folder": str(candidate.source_folder),
        "target_folder": str(mapping.target_folder),
        "source_state": candidate.source_state,
        "target_state": target_state(candidate),
        "size_bytes": candidate.size,
        "mtime": candidate.mtime_ns,
        "message_id": message_id,
        "source_flags": split_maildir_flags(candidate.source_file.name)[1],
        "target_flags": flags,
        "sha256": sha256,
        "warning": warning,
        "error": error,
    }


def run_conversion(settings: Settings) -> int:
    validate_safety(settings)
    jsonl, writers = open_logs(settings.log_dir)
    conn = init_db(settings.state_path)
    counters: Dict[str, Counter] = defaultdict(Counter)
    bytes_by_folder: Counter = Counter()
    sequence = 0
    try:
        source_folders = discover_source_folders(settings.source)
        mappings = build_folder_mappings(settings.source, settings.target, source_folders)
        if not source_folders:
            raise ConversionError(f"No source folders containing cur/new found under {settings.source}")

        mkdir_maildir(settings.target, settings.mode == "dry-run")
        for mapping in mappings.values():
            writers["folders"].write(
                {
                    "source_folder": str(mapping.source_folder),
                    "relative_source": mapping.relative_source,
                    "target_name": mapping.target_name,
                    "target_folder": str(mapping.target_folder),
                    "note": mapping.collision_note,
                }
            )
            mkdir_maildir(mapping.target_folder, settings.mode == "dry-run")

        for candidate in iter_candidates(source_folders):
            mapping = mappings[candidate.source_folder]
            folder_key = str(mapping.target_folder)
            counters[folder_key]["source_candidates"] += 1
            skip_reason = should_skip_file(candidate.source_file)
            flags = target_flags(candidate)
            final_dir = mapping.target_folder / target_state(candidate)
            sequence += 1
            try:
                final_path = unique_target_path(final_dir, flags, sequence)
            except ConversionError as exc:
                final_path = final_dir / "<unavailable>"
                skip_reason = str(exc)

            if skip_reason:
                counters[folder_key]["skipped"] += 1
                row = event_base(candidate, mapping, str(final_path), "skipped", flags=flags, error=skip_reason)
                jsonl.write(row)
                writers["skipped"].write(
                    {"source_path": str(candidate.source_file), "target_path": str(final_path), "reason": skip_reason}
                )
                continue

            if candidate.size == 0:
                counters[folder_key]["skipped"] += 1
                row = event_base(candidate, mapping, str(final_path), "skipped", flags=flags, error="empty-file")
                jsonl.write(row)
                writers["skipped"].write(
                    {"source_path": str(candidate.source_file), "target_path": str(final_path), "reason": "empty-file"}
                )
                continue

            resumed_target = already_copied(conn, candidate) if settings.resume else None
            if resumed_target:
                counters[folder_key]["skipped"] += 1
                row = event_base(candidate, mapping, resumed_target, "skipped", flags=flags, warning="resume-already-copied")
                jsonl.write(row)
                writers["skipped"].write(
                    {"source_path": str(candidate.source_file), "target_path": resumed_target, "reason": "resume-already-copied"}
                )
                continue

            message_id, header_warning = parse_message_id(candidate.source_file, settings.max_header_bytes)

            try:
                if settings.mode == "dry-run":
                    source_sha256 = sha256_file(candidate.source_file)
                    status = "dry-run-copy"
                    counters[folder_key]["dry_run_copy"] += 1
                elif settings.mode == "copy":
                    source_sha256 = copy_atomic_with_hash(candidate.source_file, mapping.target_folder / "tmp", final_path)
                    status = "copied"
                    counters[folder_key]["copied"] += 1
                else:
                    raise ConversionError(f"Unsupported conversion mode: {settings.mode}")

                duplicate_warn, duplicate_rows = duplicate_warning(conn, message_id, source_sha256)
                warning = append_warning(header_warning, duplicate_warn)
                # Keep duplicate tracking available within the current run. In copy mode
                # this must happen after duplicate checks so the current message is not
                # reported as a duplicate of itself.
                record_processed(conn, candidate, source_sha256, str(final_path), status, message_id)
                for kind, key, first_source in duplicate_rows:
                    writers["duplicates"].write(
                        {
                            "kind": kind,
                            "key": key,
                            "source_path": str(candidate.source_file),
                            "target_path": str(final_path),
                            "first_seen_source": first_source,
                        }
                    )
                bytes_by_folder[folder_key] += candidate.size
                row = event_base(candidate, mapping, str(final_path), status, message_id, flags, source_sha256, warning)
                jsonl.write(row)
            except Exception as exc:
                counters[folder_key]["errors"] += 1
                error = f"{type(exc).__name__}: {exc}"
                row = event_base(candidate, mapping, str(final_path), "error", message_id, flags, error=error)
                jsonl.write(row)
                writers["errors"].write(
                    {"source_path": str(candidate.source_file), "target_path": str(final_path), "error": error}
                )

        for folder_key in sorted(counters):
            counter = counters[folder_key]
            writers["summary"].write(
                {
                    "target_folder": folder_key,
                    "source_candidates": counter["source_candidates"],
                    "copied": counter["copied"],
                    "dry_run_copy": counter["dry_run_copy"],
                    "skipped": counter["skipped"],
                    "errors": counter["errors"],
                    "bytes": bytes_by_folder[folder_key],
                }
            )
        conn.commit()
        copy_state_snapshot(settings.state_path, settings.log_dir / "conversion-state.sqlite")
    finally:
        conn.close()
        jsonl.close()
        for writer in writers.values():
            writer.close()
    return 0


def run_verify(settings: Settings) -> int:
    validate_verify_safety(settings)
    jsonl, writers = open_logs(settings.log_dir)
    conn = init_db(settings.state_path)
    ok = True
    summary = Counter()
    try:
        rows = conn.execute(
            "SELECT source_path, source_size, source_sha256, target_path FROM processed WHERE status = 'copied'"
        ).fetchall()
        for source_path, source_size, source_sha256, target_path in rows:
            summary["state_rows"] += 1
            source = Path(source_path)
            target = Path(target_path)
            error = ""
            if not target.is_file():
                error = "target-missing"
            elif target.stat().st_size != source_size:
                error = f"size-mismatch:{target.stat().st_size}!={source_size}"
            elif settings.verify_hash:
                target_sha = sha256_file(target)
                if target_sha != source_sha256:
                    error = "sha256-mismatch"
            if error:
                ok = False
                writers["errors"].write({"source_path": source_path, "target_path": target_path, "error": error})
                jsonl.write(
                    {
                        "status": "verify-error",
                        "source_path": source_path,
                        "target_path": target_path,
                        "source_size": source_size,
                        "error": error,
                    }
                )
            else:
                summary["verified"] += 1
        writers["summary"].write(
            {
                "target_folder": str(settings.target),
                "source_candidates": summary["state_rows"],
                "copied": summary["verified"],
                "dry_run_copy": 0,
                "skipped": 0,
                "errors": summary["state_rows"] - summary["verified"],
                "bytes": "",
            }
        )
        copy_state_snapshot(settings.state_path, settings.log_dir / "conversion-state.sqlite")
    finally:
        conn.close()
        jsonl.close()
        for writer in writers.values():
            writer.close()
    return 0 if ok else 2


def validate_verify_safety(settings: Settings) -> None:
    if not settings.state_path.is_file():
        raise ConversionError(f"State database not found for verification: {settings.state_path}")
    if not settings.target.exists():
        raise ConversionError(f"Target directory does not exist: {settings.target}")


def default_log_dir(target: Path) -> Path:
    return target.parent / "conversion-logs" / timestamp()


def build_settings(args: argparse.Namespace) -> Settings:
    source = resolve_path(Path(args.source))
    target = resolve_path(Path(args.target))
    mode = "dry-run"
    if args.copy:
        mode = "copy"
    if args.verify:
        mode = "verify"
    log_dir = resolve_path(Path(args.log_dir)) if args.log_dir else default_log_dir(target)
    if args.state:
        state_path = resolve_path(Path(args.state))
    elif mode == "copy" or args.resume or mode == "verify":
        state_path = target / ".conversion-state.sqlite"
    else:
        state_path = log_dir / "conversion-state.sqlite"
    return Settings(
        source=source,
        target=target,
        log_dir=log_dir,
        state_path=state_path,
        mode=mode,
        resume=args.resume,
        verify_hash=args.verify_hash,
        allow_unmarked_source=args.allow_unmarked_source,
    )


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert a staged Betterbird/Thunderbird maildir-lite profile to canonical Maildir++."
    )
    parser.add_argument("--source", default="/mail/import-staging/betterbird-maildir", help="Staged Betterbird profile root")
    parser.add_argument("--target", default="/mail/Mailstore/evolution-import", help="Canonical Maildir++ target root")
    parser.add_argument("--log-dir", help="Directory for conversion logs")
    parser.add_argument("--state", help="Path to conversion-state.sqlite")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Inspect and log planned conversion without copying messages")
    mode.add_argument("--copy", action="store_true", help="Copy messages into canonical Maildir++ target")
    mode.add_argument("--verify", action="store_true", help="Verify copied messages recorded in the state database")
    parser.add_argument("--resume", action="store_true", help="Skip source files already recorded as copied in the state database")
    parser.add_argument("--verify-hash", action="store_true", help="Verify SHA256 content hashes during --verify")
    parser.add_argument(
        "--allow-unmarked-source",
        action="store_true",
        help="Allow --copy from a source without Betterbird markers after manual verification",
    )
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    settings = build_settings(args)
    try:
        if settings.mode == "verify":
            rc = run_verify(settings)
        else:
            rc = run_conversion(settings)
        print(f"mode={settings.mode}")
        print(f"source={settings.source}")
        print(f"target={settings.target}")
        print(f"log_dir={settings.log_dir}")
        print(f"state={settings.state_path}")
        return rc
    except ConversionError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
