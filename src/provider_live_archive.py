#!/usr/bin/env python3
"""Safely archive a validated provider-live Maildir INBOX.

The tool deliberately separates immutable data operations from service control.
`provider_live_archive_control.sh` pauses mbsync/Evolution/notmuch as required;
this module creates manifests, snapshots, portable backups, archive copies,
verification evidence, cleanup canaries, rollback links, and status output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Optional, Sequence, Set, Tuple

try:
    import betterbird_profile_transport as transport
except ModuleNotFoundError:  # pragma: no cover
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import betterbird_profile_transport as transport


FORMAT_VERSION = "provider-live-archive-run-v1"
BACKUP_FORMAT_VERSION = "provider-live-prearchive-backup-v1"
DEFAULT_LIVE = Path("/mail/Mailstore/mbsync/provider-live")
DEFAULT_ARCHIVE = Path("/mail/Mailstore/evolution/provider-live-archive")
DEFAULT_STATE = Path("/mail/AppData/provider-live-archive")
DEFAULT_BACKUP = Path("/mail/Backups/provider-live-archive")
DEFAULT_MBSYNC_STATE = Path("/mail/AppData/isync/state/provider-live")
DEFAULT_CONFIG = Path.home() / ".config/isyncrc"
DEFAULT_THRESHOLD = 15_000
DEFAULT_PART_SIZE = 1_900 * 1024 * 1024
STATE_DIRS = ("cur", "new", "tmp")
UID_RE = re.compile(r"(?:^|,)U=(\d+)(?=,|:|;|$)")
FLAGS_RE = re.compile(r"[:;]2,([A-Za-z]*)$")
RUN_ID_RE = re.compile(r"^[0-9]{8}-[0-9]{6}$")
ARCHIVE_ID_RE = re.compile(r",A=([0-9]{8}-[0-9]{6}-[0-9]{8})(?=[:;]2,)")
ARCHIVE_FOLDER_RE = re.compile(r"^\.Inbox(?:\.\d{4}(?:\.\d{2})?)?$")
ARCHIVE_MONTH_RE = re.compile(r"^\.Inbox\.\d{4}\.\d{2}$")
ALLOWED_PHASES = {
    "snapshotted",
    "external_verified",
    "copied",
    "copy_verified",
    "evolution_validated",
    "notmuch_verified",
    "canary_removed",
    "canary_verified",
    "cleanup_completed",
    "cleanup_verified",
    "rolled_back",
    "snapshot_retired",
}


class ArchiveError(RuntimeError):
    """Raised when an archive safety invariant fails."""


@dataclass(frozen=True)
class MessageRecord:
    uid: int
    source_rel: str
    snapshot_rel: str
    size: int
    mtime_ns: int
    flags: str
    sha256: str
    archive_id: str
    archive_rel: str


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def fail(message: str) -> None:
    raise ArchiveError(message)


def parse_isyncrc(config: Path) -> Dict[str, Dict[str, List[List[str]]]]:
    """Parse named isyncrc sections needed by the production safety audit."""
    config = resolve(config)
    if not config.is_file() or config.is_symlink():
        fail(f"missing or unsafe mbsync config: {config}")
    sections: Dict[str, Dict[str, List[List[str]]]] = {}
    current = "__global__"
    sections[current] = {}
    section_keywords = {"IMAPAccount", "IMAPStore", "MaildirStore", "Channel", "Group"}
    try:
        lines = config.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ArchiveError(f"cannot read mbsync config {config}: {exc}") from exc
    for number, raw in enumerate(lines, 1):
        try:
            tokens = shlex.split(raw, comments=True, posix=True)
        except ValueError as exc:
            raise ArchiveError(f"invalid mbsync config syntax at line {number}: {exc}") from exc
        if not tokens:
            continue
        keyword, values = tokens[0], tokens[1:]
        if keyword in section_keywords and not (keyword == "Channel" and current.startswith("Group:")):
            if not values:
                fail(f"unnamed {keyword} at mbsync config line {number}")
            current = f"{keyword}:{values[0]}"
            if current in sections:
                fail(f"duplicate mbsync section: {current}")
            sections[current] = {}
            continue
        sections[current].setdefault(keyword, []).append(values)
    return sections


def audit_mbsync_config(config: Path) -> Dict[str, object]:
    """Refuse changes to the validated provider-live deletion-safety policy."""
    sections = parse_isyncrc(config)

    def require_values(section: str, keyword: str, expected: List[str]) -> None:
        actual = sections.get(section, {}).get(keyword, [])
        if actual != [expected]:
            fail(f"unsafe mbsync setting {section} {keyword}: {actual!r} != {[expected]!r}")

    require_values("__global__", "FSync", ["yes"])
    account = "IMAPAccount:provider"
    require_values(account, "Port", ["993"])
    require_values(account, "TLSType", ["IMAPS"])
    require_values(account, "SystemCertificates", ["yes"])
    require_values(account, "Timeout", ["60"])
    require_values(account, "PipelineDepth", ["1"])
    for keyword in ("Host", "User", "PassCmd"):
        actual = sections.get(account, {}).get(keyword, [])
        if len(actual) != 1 or len(actual[0]) != 1 or not actual[0][0]:
            fail(f"missing or ambiguous mbsync setting {account} {keyword}")
    require_values("IMAPStore:provider-remote", "Account", ["provider"])
    require_values("IMAPStore:provider-remote", "UseNamespace", ["yes"])

    require_values("MaildirStore:provider-live-local", "Inbox", [DEFAULT_LIVE.as_posix()])
    require_values("MaildirStore:provider-live-local", "SubFolders", ["Maildir++"])

    normal = "Channel:provider-live"
    require_values(normal, "Far", [":provider-remote:"])
    require_values(normal, "Near", [":provider-live-local:"])
    require_values(normal, "Patterns", ["INBOX", "Drafts", "Trash", "spam", "Junk", "Archive"])
    require_values(normal, "Sync", ["PullNew"])
    require_values(normal, "Create", ["Near"])
    require_values(normal, "Remove", ["None"])
    require_values(normal, "Expunge", ["None"])
    require_values(normal, "CopyArrivalDate", ["yes"])
    require_values(normal, "SyncState", [DEFAULT_MBSYNC_STATE.as_posix() + "/"])

    sent = "Channel:provider-live-sent-upload"
    require_values(sent, "Far", [":provider-remote:Sent"])
    require_values(sent, "Near", [":provider-live-local:Sent"])
    require_values(sent, "Sync", ["PullNew", "PushNew"])
    require_values(sent, "Create", ["None"])
    require_values(sent, "Remove", ["None"])
    require_values(sent, "Expunge", ["None"])
    require_values(sent, "CopyArrivalDate", ["yes"])
    require_values(sent, "SyncState", [DEFAULT_MBSYNC_STATE.as_posix() + "/"])

    group_channels = sections.get("Group:provider-live-group", {}).get("Channel", [])
    if group_channels != [["provider-live"], ["provider-live-sent-upload"]]:
        fail(f"unsafe provider-live group membership: {group_channels!r}")
    return {
        "mbsync_policy": "validated",
        "normal_channel": "PullNew only; Remove None; Expunge None",
        "sent_channel": "PullNew PushNew only; Remove None; Expunge None",
        "group": "provider-live-group",
    }


def resolve(path: Path) -> Path:
    return path.expanduser().resolve()


def ensure_under(path: Path, root: Path, label: str) -> Path:
    path = resolve(path)
    root = resolve(root)
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise ArchiveError(f"{label} escapes allowed root: {path} not under {root}") from exc
    return path


def validate_run_id(run_id: str) -> str:
    if not RUN_ID_RE.fullmatch(run_id):
        fail(f"invalid run id: {run_id}; expected YYYYMMDD-HHMMSS")
    return run_id


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            block = handle.read(chunk_size)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def fsync_directory(path: Path) -> None:
    if os.name == "nt":
        return
    directory_fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def atomic_json(path: Path, value: object, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def append_jsonl(path: Path, rows: Iterable[Dict[str, object]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    with tmp.open("w", encoding="utf-8", newline="\n") as handle:
        for row in rows:
            handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")))
            handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def read_json(path: Path) -> Dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArchiveError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        fail(f"expected JSON object: {path}")
    return value


def read_jsonl(path: Path) -> List[MessageRecord]:
    records: List[MessageRecord] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ArchiveError(f"cannot read manifest {path}: {exc}") from exc
    for number, line in enumerate(lines, 1):
        if not line:
            continue
        try:
            raw = json.loads(line)
            records.append(MessageRecord(**raw))
        except (json.JSONDecodeError, TypeError) as exc:
            raise ArchiveError(f"invalid manifest row {number}: {exc}") from exc
    return records


def ensure_maildir(folder: Path) -> None:
    if folder.is_symlink():
        fail(f"Maildir folder may not be a symlink: {folder}")
    folder.mkdir(parents=True, exist_ok=True)
    os.chmod(folder, 0o700)
    for state in STATE_DIRS:
        child = folder / state
        if child.is_symlink():
            fail(f"Maildir state directory may not be a symlink: {child}")
        child.mkdir(exist_ok=True)
        os.chmod(child, 0o700)


def create_layout(archive: Path, state: Path, backup: Path) -> None:
    archive = resolve(archive)
    state = resolve(state)
    backup = resolve(backup)
    ensure_maildir(archive)
    ensure_maildir(archive / ".Inbox")
    for path in (state, state / "runs", state / "monitor", backup, backup / "runs"):
        path.mkdir(parents=True, exist_ok=True)
        os.chmod(path, 0o700)
    audit_archive_layout(archive)


def audit_archive_layout(archive: Path) -> None:
    archive = resolve(archive)
    if not archive.is_dir() or archive.is_symlink():
        fail(f"missing or unsafe archive root: {archive}")
    root_allowed = set(STATE_DIRS)
    root_names = {child.name for child in archive.iterdir()}
    missing_root = root_allowed - root_names
    if missing_root:
        fail(f"archive root is missing state directories: {sorted(missing_root)}")
    for child in archive.iterdir():
        if child.is_symlink():
            fail(f"archive layout refuses symlink: {child}")
        if child.name in root_allowed:
            if not child.is_dir():
                fail(f"archive state entry is not a directory: {child}")
        elif ARCHIVE_FOLDER_RE.fullmatch(child.name):
            if not child.is_dir():
                fail(f"archive folder is not a directory: {child}")
            names = {entry.name for entry in child.iterdir()}
            if names != root_allowed:
                fail(f"archive folder has unexpected entries: {child}: {sorted(names)}")
        else:
            fail(f"unexpected archive root entry: {child}")
    for directory, dirs, files in os.walk(archive, topdown=True, followlinks=False):
        directory_path = Path(directory)
        if directory_path.name in STATE_DIRS:
            if dirs:
                fail(f"archive state directory contains subdirectories: {directory_path}")
            if directory_path.name == "tmp" and files:
                fail(f"archive tmp is not empty: {directory_path}")
            if files and directory_path.name in ("cur", "new") and not ARCHIVE_MONTH_RE.fullmatch(directory_path.parent.name):
                fail(f"archive messages may exist only in monthly folders: {directory_path}")
            for name in files:
                path = directory_path / name
                if path.is_symlink() or not path.is_file():
                    fail(f"unsafe archive message entry: {path}")
                if directory_path.name in ("cur", "new") and not ARCHIVE_ID_RE.search(name):
                    fail(f"unrecognized archive message filename: {path}")
            dirs[:] = []


def iter_inbox_files(live: Path) -> Iterator[Path]:
    live = resolve(live)
    for state in ("cur", "new"):
        directory = live / state
        if not directory.is_dir() or directory.is_symlink():
            fail(f"missing or unsafe live INBOX state directory: {directory}")
        for path in sorted(directory.iterdir(), key=lambda item: item.name):
            if path.is_symlink() or not path.is_file():
                fail(f"non-regular live INBOX entry: {path}")
            yield path


def tmp_file_count(root: Path) -> int:
    total = 0
    root = resolve(root)
    for directory, dirs, files in os.walk(root, topdown=True, followlinks=False):
        directory_path = Path(directory)
        dirs[:] = [name for name in dirs if not (directory_path / name).is_symlink()]
        if directory_path.name == "tmp":
            total += len(files)
            dirs[:] = []
    return total


def parse_uid(name: str) -> int:
    matches = UID_RE.findall(name)
    if len(matches) != 1:
        fail(f"expected exactly one mbsync UID in filename: {name}")
    return int(matches[0])


def parse_flags(name: str, source_state: str) -> str:
    match = FLAGS_RE.search(name)
    if match:
        return "".join(sorted(set(match.group(1))))
    if source_state == "new":
        return ""
    fail(f"cur message lacks Maildir info flags: {name}")


def info_delimiter() -> str:
    return ";" if os.name == "nt" else ":"


def archive_month(mtime_ns: int) -> Tuple[int, int]:
    stamp = time.localtime(mtime_ns / 1_000_000_000)
    return stamp.tm_year, stamp.tm_mon


def archive_filename(run_id: str, sequence: int, mtime_ns: int, size: int, flags: str) -> str:
    seconds, nanos = divmod(mtime_ns, 1_000_000_000)
    archive_id = f"{run_id}-{sequence:08d}"
    delim = info_delimiter()
    return (
        f"{seconds}.M{nanos:09d}P{os.getpid()}Q{sequence}.antix-archive,"
        f"S={size},A={archive_id}{delim}2,{flags}"
    )


def count_and_size(live: Path) -> Tuple[int, int]:
    count = 0
    size = 0
    for path in iter_inbox_files(live):
        stat = path.stat()
        count += 1
        size += stat.st_size
    return count, size


def regular_tree_bytes(root: Path) -> int:
    root = resolve(root)
    total = 0
    for directory, dirs, files in os.walk(root, topdown=True, followlinks=False):
        directory_path = Path(directory)
        for name in dirs:
            path = directory_path / name
            if path.is_symlink():
                fail(f"tree size refuses symlink directory: {path}")
        for name in files:
            path = directory_path / name
            if path.is_symlink() or not path.is_file():
                fail(f"tree size refuses non-regular file: {path}")
            total += path.stat().st_size
    return total


def estimate(live: Path, threshold: int = DEFAULT_THRESHOLD) -> Dict[str, object]:
    rows: List[Tuple[int, int, int, str]] = []
    months: Dict[str, int] = {}
    seen: Set[int] = set()
    for path in iter_inbox_files(live):
        uid = parse_uid(path.name)
        if uid in seen:
            fail(f"duplicate mbsync UID in live INBOX: {uid}")
        seen.add(uid)
        stat = path.stat()
        rows.append((uid, stat.st_size, stat.st_mtime_ns, path.name))
        year, month = archive_month(stat.st_mtime_ns)
        key = f"{year:04d}-{month:02d}"
        months[key] = months.get(key, 0) + 1
    rows.sort()
    total_bytes = sum(row[1] for row in rows)
    snapshot_bytes = regular_tree_bytes(live)
    mtime_min = min((row[2] for row in rows), default=None)
    mtime_max = max((row[2] for row in rows), default=None)
    return {
        "live_inbox_count": len(rows),
        "threshold": threshold,
        "alert_required": len(rows) >= threshold,
        "selected_count": len(rows),
        "selected_bytes": total_bytes,
        "full_provider_live_snapshot_bytes": snapshot_bytes,
        "required_mail_free_bytes": int(total_bytes * 1.15) + 1024**3,
        "required_external_free_bytes": int(snapshot_bytes * 1.10) + 1024**3,
        "uid_min": rows[0][0] if rows else None,
        "uid_max": rows[-1][0] if rows else None,
        "mtime_min_ns": mtime_min,
        "mtime_max_ns": mtime_max,
        "arrival_date_min_local": datetime.fromtimestamp(mtime_min / 1_000_000_000).astimezone().isoformat() if mtime_min else None,
        "arrival_date_max_local": datetime.fromtimestamp(mtime_max / 1_000_000_000).astimezone().isoformat() if mtime_max else None,
        "monthly_counts": dict(sorted(months.items())),
    }


def run_paths(run_id: str, state: Path, backup: Path) -> Dict[str, Path]:
    validate_run_id(run_id)
    state_run = resolve(state) / "runs" / run_id
    backup_run = resolve(backup) / "runs" / run_id
    return {
        "state_run": state_run,
        "run_json": state_run / "run.json",
        "manifest": state_run / "manifest.jsonl",
        "backup_run": backup_run,
        "snapshot_bundle": backup_run / "snapshot-bundle",
        "snapshot_live": backup_run / "snapshot-bundle" / "provider-live",
        "snapshot_state": backup_run / "snapshot-bundle" / "mbsync-state",
        "snapshot_config": backup_run / "snapshot-bundle" / "isyncrc",
    }


def update_run(paths: Dict[str, Path], **changes: object) -> Dict[str, object]:
    data = read_json(paths["run_json"])
    data.update(changes)
    data["updated_at_utc"] = now_utc()
    atomic_json(paths["run_json"], data)
    return data


def require_phase(data: Dict[str, object], allowed: Sequence[str]) -> None:
    phase = str(data.get("phase", ""))
    if phase not in allowed:
        fail(f"run phase {phase!r} not allowed; expected one of: {', '.join(allowed)}")


def hardlink_tree(source: Path, dest: Path) -> None:
    source = resolve(source)
    if dest.exists():
        fail(f"snapshot destination already exists: {dest}")
    if source.stat().st_dev != dest.parent.stat().st_dev:
        fail("hard-link snapshot must be on the same filesystem as provider-live")
    dest.mkdir(mode=0o700)
    for directory, dirs, files in os.walk(source, topdown=True, followlinks=False):
        directory_path = Path(directory)
        rel_dir = directory_path.relative_to(source)
        target_dir = dest / rel_dir
        os.chmod(target_dir, 0o700)
        dirs.sort()
        files.sort()
        for name in list(dirs):
            child = directory_path / name
            if child.is_symlink():
                fail(f"snapshot refuses symlink directory: {child}")
            (target_dir / name).mkdir(mode=0o700)
        for name in files:
            child = directory_path / name
            if child.is_symlink() or not child.is_file():
                fail(f"snapshot refuses non-regular file: {child}")
            os.link(child, target_dir / name)


def build_uid_map(live: Path) -> Dict[int, Path]:
    result: Dict[int, Path] = {}
    for path in iter_inbox_files(live):
        uid = parse_uid(path.name)
        if uid in result:
            fail(f"duplicate mbsync UID in live INBOX: {uid}")
        result[uid] = path
    return result


def build_archive_id_map(archive: Path) -> Dict[str, Path]:
    archive = resolve(archive)
    result: Dict[str, Path] = {}
    audit_archive_layout(archive)
    for directory, dirs, files in os.walk(archive, topdown=True, followlinks=False):
        directory_path = Path(directory)
        dirs[:] = sorted(name for name in dirs if not (directory_path / name).is_symlink())
        if directory_path.name not in ("cur", "new"):
            continue
        for name in sorted(files):
            path = directory_path / name
            if path.is_symlink() or not path.is_file():
                fail(f"unsafe archive message entry: {path}")
            match = ARCHIVE_ID_RE.search(name)
            if not match:
                fail(f"unrecognized archive message filename: {path}")
            archive_id = match.group(1)
            if archive_id in result:
                fail(f"duplicate archive ID: {archive_id}")
            result[archive_id] = path
        dirs[:] = []
    return result


def snapshot_run(
    run_id: str,
    live: Path,
    archive: Path,
    state: Path,
    backup: Path,
    mbsync_state: Path,
    config: Path,
    threshold: int,
) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    live = resolve(live)
    archive = resolve(archive)
    mbsync_state = resolve(mbsync_state)
    config = resolve(config)
    create_layout(archive, state, backup)
    if paths["state_run"].exists() or paths["backup_run"].exists():
        fail(f"run already exists: {run_id}")
    if tmp_file_count(live):
        fail("provider-live contains files under tmp")
    if not mbsync_state.is_dir() or mbsync_state.is_symlink():
        fail(f"missing or unsafe mbsync state directory: {mbsync_state}")
    if not config.is_file() or config.is_symlink():
        fail(f"missing or unsafe mbsync config: {config}")
    audit_mbsync_config(config)
    summary = estimate(live, threshold)
    if int(summary["live_inbox_count"]) < threshold:
        fail(f"live INBOX below threshold: {summary['live_inbox_count']} < {threshold}")
    mail_free = shutil.disk_usage(archive.parent).free
    required_mail_free = int(summary["required_mail_free_bytes"])
    if mail_free < required_mail_free:
        fail(f"insufficient /mail free space: free={mail_free} required~={required_mail_free}")

    paths["state_run"].mkdir(parents=True, mode=0o700)
    paths["backup_run"].mkdir(parents=True, mode=0o700)
    paths["snapshot_bundle"].mkdir(mode=0o700)
    hardlink_tree(live, paths["snapshot_live"])
    shutil.copytree(mbsync_state, paths["snapshot_state"], copy_function=shutil.copy2)
    shutil.copy2(config, paths["snapshot_config"])
    os.chmod(paths["snapshot_config"], 0o600)

    records: List[MessageRecord] = []
    seen: Set[int] = set()
    for sequence, source in enumerate(iter_inbox_files(live), 1):
        uid = parse_uid(source.name)
        if uid in seen:
            fail(f"duplicate mbsync UID in live INBOX: {uid}")
        seen.add(uid)
        rel = source.relative_to(live).as_posix()
        snapshot_file = paths["snapshot_live"] / rel
        stat = snapshot_file.stat()
        flags = parse_flags(source.name, source.parent.name)
        digest = sha256_file(snapshot_file)
        year, month = archive_month(stat.st_mtime_ns)
        name = archive_filename(run_id, sequence, stat.st_mtime_ns, stat.st_size, flags)
        archive_id = f"{run_id}-{sequence:08d}"
        archive_rel = f".Inbox.{year:04d}.{month:02d}/cur/{name}"
        records.append(
            MessageRecord(
                uid=uid,
                source_rel=rel,
                snapshot_rel=rel,
                size=stat.st_size,
                mtime_ns=stat.st_mtime_ns,
                flags=flags,
                sha256=digest,
                archive_id=archive_id,
                archive_rel=archive_rel,
            )
        )
    records.sort(key=lambda row: row.uid)
    append_jsonl(paths["manifest"], (asdict(row) for row in records))
    shutil.copy2(paths["manifest"], paths["snapshot_bundle"] / "manifest.jsonl")
    manifest_sha = sha256_file(paths["manifest"])
    data: Dict[str, object] = {
        "format": FORMAT_VERSION,
        "run_id": run_id,
        "created_at_utc": now_utc(),
        "updated_at_utc": now_utc(),
        "phase": "snapshotted",
        "live": str(live),
        "archive": str(archive),
        "snapshot_live": str(paths["snapshot_live"]),
        "manifest": str(paths["manifest"]),
        "manifest_sha256": manifest_sha,
        "threshold": threshold,
        "selected_count": len(records),
        "selected_bytes": sum(row.size for row in records),
        "uid_min": records[0].uid if records else None,
        "uid_max": records[-1].uid if records else None,
        "external_verified": False,
        "copy_verified": False,
        "evolution_validated": False,
        "notmuch_verified": False,
        "cleanup_verified": False,
        "snapshot_retired": False,
    }
    atomic_json(paths["run_json"], data)
    shutil.copy2(paths["run_json"], paths["snapshot_bundle"] / "run-at-cutoff.json")
    return data


def configure_backup_transport() -> Dict[str, object]:
    old = {
        "FORMAT_VERSION": transport.FORMAT_VERSION,
        "ARCHIVE_BASENAME": transport.ARCHIVE_BASENAME,
        "PART_PREFIX": transport.PART_PREFIX,
        "ACTIVE_PROFILE_MARKERS": transport.ACTIVE_PROFILE_MARKERS,
    }
    transport.FORMAT_VERSION = BACKUP_FORMAT_VERSION
    transport.ARCHIVE_BASENAME = "provider-live-prearchive.tar.gz"
    transport.PART_PREFIX = "provider-live-prearchive.tar.gz.part"
    transport.ACTIVE_PROFILE_MARKERS = ()
    return old


def restore_backup_transport(old: Dict[str, object]) -> None:
    for key, value in old.items():
        setattr(transport, key, value)


def external_pack(
    run_id: str,
    external_target: Path,
    state: Path,
    backup: Path,
    mail_root: Path = Path("/mail"),
    part_size: int = DEFAULT_PART_SIZE,
    compression_level: int = 6,
    allow_same_filesystem: bool = False,
) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("snapshotted", "external_verified"))
    external_target = resolve(external_target)
    mail_root = resolve(mail_root)
    try:
        external_target.relative_to(mail_root)
    except ValueError:
        pass
    else:
        fail(f"external target may not be under {mail_root}: {external_target}")
    if not external_target.is_dir() or external_target.is_symlink():
        fail(f"external target is not a safe mounted directory: {external_target}")
    if not allow_same_filesystem:
        allowed_prefixes = (Path("/media"), Path("/run/media"), Path("/mnt/hgfs"))
        if not any(_is_relative_to(external_target, prefix) for prefix in allowed_prefixes):
            fail("external target must be under /media, /run/media, or /mnt/hgfs")
        mount_point = mounted_ancestor(external_target)
        if mount_point == Path("/"):
            fail(f"external target is backed by the root filesystem, not a mounted USB/HGFS filesystem: {external_target}")
        if not any(_is_relative_to(mount_point, prefix) for prefix in allowed_prefixes):
            fail(f"external target mount point is outside approved USB/HGFS roots: {mount_point}")
    if not allow_same_filesystem and external_target.stat().st_dev == mail_root.stat().st_dev:
        fail("external target is on the same filesystem as /mail")
    required = sum(path.stat().st_size for path in paths["snapshot_bundle"].rglob("*") if path.is_file())
    free = shutil.disk_usage(external_target).free
    if free < int(required * 1.10) + 1024**3:
        fail(f"insufficient external free space: free={free} required~={int(required * 1.10) + 1024**3}")
    final_dir = external_target / f"provider-live-prearchive-{run_id}"
    partial_dir = external_target / f".provider-live-prearchive-{run_id}.partial"
    if final_dir.exists() or partial_dir.exists():
        fail(f"external backup destination already exists for run: {run_id}")
    old = configure_backup_transport()
    try:
        manifest = transport.pack_profile(
            source=paths["snapshot_bundle"],
            out_dir=partial_dir,
            part_size=part_size,
            compression_level=compression_level,
            allow_active_profile=True,
            allow_symlinks=False,
        )
        transport.verify_archive_from_manifest(manifest)
    finally:
        restore_backup_transport(old)
    os.replace(partial_dir, final_dir)
    manifest = final_dir / "manifest.json"
    old = configure_backup_transport()
    try:
        verification = transport.verify_archive_from_manifest(manifest)
    finally:
        restore_backup_transport(old)
    return update_run(
        paths,
        phase="external_verified",
        external_verified=True,
        external_manifest=str(manifest),
        external_manifest_sha256=sha256_file(manifest),
        external_archive_bytes=verification["bytes"],
    )


def copy_verified_file(source: Path, temp: Path, dest: Path, record: MessageRecord) -> None:
    if dest.exists():
        if dest.is_symlink() or not dest.is_file() or sha256_file(dest) != record.sha256:
            fail(f"existing archive destination mismatch: {dest}")
        return
    if temp.exists():
        if temp.is_symlink() or not temp.is_file() or sha256_file(temp) != record.sha256:
            fail(f"existing archive temporary file mismatch: {temp}")
    else:
        digest = hashlib.sha256()
        with source.open("rb") as src, temp.open("xb") as out:
            while True:
                block = src.read(1024 * 1024)
                if not block:
                    break
                out.write(block)
                digest.update(block)
            out.flush()
            os.fsync(out.fileno())
        if digest.hexdigest() != record.sha256:
            temp.unlink(missing_ok=True)
            fail(f"archive copy hash mismatch: {source}")
        os.utime(temp, ns=(record.mtime_ns, record.mtime_ns))
    os.replace(temp, dest)
    fsync_directory(dest.parent)


def copy_to_archive(run_id: str, state: Path, backup: Path, archive: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("external_verified", "copied", "copy_verified"))
    if not bool(data.get("external_verified")):
        fail("external backup must verify before archive copy")
    records = read_jsonl(paths["manifest"])
    archive = resolve(archive)
    ensure_maildir(archive)
    ensure_maildir(archive / ".Inbox")
    for record in records:
        source = ensure_under(paths["snapshot_live"] / record.snapshot_rel, paths["snapshot_live"], "snapshot source")
        if source.is_symlink() or not source.is_file():
            fail(f"missing or unsafe snapshot source: {source}")
        if source.stat().st_size != record.size or sha256_file(source) != record.sha256:
            fail(f"snapshot source changed: {source}")
        dest = ensure_under(archive / record.archive_rel, archive, "archive destination")
        month_folder = dest.parent.parent
        parts = month_folder.name.lstrip(".").split(".")
        if len(parts) != 3 or parts[0] != "Inbox":
            fail(f"unexpected monthly archive path: {month_folder}")
        ensure_maildir(archive / ".Inbox")
        ensure_maildir(archive / f".Inbox.{parts[1]}")
        ensure_maildir(month_folder)
        temp = month_folder / "tmp" / f"{dest.name}.partial"
        copy_verified_file(source, temp, dest, record)
    return update_run(paths, phase="copied", archive_copy_completed_at_utc=now_utc())


def verify_external_manifest(data: Dict[str, object]) -> None:
    raw = data.get("external_manifest")
    if not raw:
        fail("run has no external manifest")
    manifest = resolve(Path(str(raw)))
    if not manifest.is_file() or sha256_file(manifest) != data.get("external_manifest_sha256"):
        fail(f"external manifest missing or changed: {manifest}")
    old = configure_backup_transport()
    try:
        transport.verify_archive_from_manifest(manifest)
    finally:
        restore_backup_transport(old)


def verify_copy(run_id: str, live: Path, archive: Path, state: Path, backup: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("copied", "copy_verified", "evolution_validated", "notmuch_verified"))
    records = read_jsonl(paths["manifest"])
    if sha256_file(paths["manifest"]) != data.get("manifest_sha256"):
        fail("immutable manifest hash mismatch")
    verify_external_manifest(data)
    uid_map = build_uid_map(live)
    archive_id_map = build_archive_id_map(archive)
    archive = resolve(archive)
    seen_ids: Set[str] = set()
    for record in records:
        if record.archive_id in seen_ids:
            fail(f"duplicate archive id: {record.archive_id}")
        seen_ids.add(record.archive_id)
        snapshot = paths["snapshot_live"] / record.snapshot_rel
        dest = archive_id_map.get(record.archive_id)
        current = uid_map.get(record.uid)
        for label, path in (("snapshot", snapshot), ("archive", dest), ("live", current)):
            if path is None or path.is_symlink() or not path.is_file():
                fail(f"{label} copy missing for UID {record.uid}: {path}")
            if path.stat().st_size != record.size or sha256_file(path) != record.sha256:
                fail(f"{label} copy mismatch for UID {record.uid}: {path}")
    if tmp_file_count(archive):
        fail("archive contains temporary files")
    return update_run(paths, phase="copy_verified", copy_verified=True, copy_verified_at_utc=now_utc())


def mark_evolution_validated(run_id: str, state: Path, backup: Path, operator_note: str) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("copy_verified", "evolution_validated", "notmuch_verified"))
    if not bool(data.get("copy_verified")):
        fail("copy must be verified before Evolution attestation")
    return update_run(
        paths,
        phase="evolution_validated",
        evolution_validated=True,
        evolution_validated_at_utc=now_utc(),
        evolution_operator_note=operator_note,
    )


def verify_notmuch_paths(
    run_id: str,
    indexed_paths_file: Path,
    state: Path,
    backup: Path,
    archive: Path,
    forbidden_prefix: Optional[Path] = None,
) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("evolution_validated", "notmuch_verified"))
    if not bool(data.get("evolution_validated")):
        fail("Evolution validation must be recorded before notmuch validation")
    indexed = {line for line in indexed_paths_file.read_text(encoding="utf-8").splitlines() if line}
    if forbidden_prefix is not None:
        forbidden = str(resolve(forbidden_prefix)) + os.sep
        bad = [path for path in indexed if path.startswith(forbidden)]
        if bad:
            fail(f"forbidden path entered notmuch index: {bad[0]}")
    archive = resolve(archive)
    records = read_jsonl(paths["manifest"])
    archive_id_map = build_archive_id_map(archive)
    missing_ids = [record.archive_id for record in records if record.archive_id not in archive_id_map]
    if missing_ids:
        fail(f"archive files missing before notmuch validation; first ID: {missing_ids[0]}")
    missing = [str(archive_id_map[record.archive_id]) for record in records if str(archive_id_map[record.archive_id]) not in indexed]
    if missing:
        fail(f"notmuch is missing {len(missing)} archived paths; first: {missing[0]}")
    return update_run(
        paths,
        phase="notmuch_verified",
        notmuch_verified=True,
        notmuch_verified_at_utc=now_utc(),
        notmuch_indexed_archive_files=len(records),
    )


def verify_cleanup_gates(data: Dict[str, object]) -> None:
    for key in ("external_verified", "copy_verified", "evolution_validated", "notmuch_verified"):
        if not bool(data.get(key)):
            fail(f"cleanup gate not satisfied: {key}")


def resolve_source(record: MessageRecord, uid_map: Dict[int, Path]) -> Path:
    source = uid_map.get(record.uid)
    if source is None:
        fail(f"live source UID missing before cleanup: {record.uid}")
    if source.is_symlink() or not source.is_file():
        fail(f"unsafe live source for UID {record.uid}: {source}")
    if source.stat().st_size != record.size or sha256_file(source) != record.sha256:
        fail(f"live source changed for UID {record.uid}: {source}")
    return source


def verify_record_copies(
    record: MessageRecord,
    paths: Dict[str, Path],
    archive: Path,
    archive_id_map: Optional[Dict[str, Path]] = None,
) -> None:
    snapshot = paths["snapshot_live"] / record.snapshot_rel
    if archive_id_map is None:
        archive_id_map = build_archive_id_map(archive)
    dest = archive_id_map.get(record.archive_id)
    if dest is None:
        fail(f"archive copy missing for ID {record.archive_id}")
    for label, path in (("snapshot", snapshot), ("archive", dest)):
        if path.is_symlink() or not path.is_file() or path.stat().st_size != record.size:
            fail(f"{label} copy missing for UID {record.uid}: {path}")
        if sha256_file(path) != record.sha256:
            fail(f"{label} hash mismatch for UID {record.uid}: {path}")


def cleanup_canary(run_id: str, live: Path, archive: Path, state: Path, backup: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("notmuch_verified", "canary_removed"))
    verify_cleanup_gates(data)
    verify_external_manifest(data)
    records = read_jsonl(paths["manifest"])
    if not records:
        fail("run has no messages")
    record = records[0]
    archive_id_map = build_archive_id_map(archive)
    verify_record_copies(record, paths, archive, archive_id_map)
    uid_map = build_uid_map(live)
    source = resolve_source(record, uid_map)
    source_rel_at_cleanup = source.relative_to(resolve(live)).as_posix()
    source.unlink()
    fsync_directory(source.parent)
    return update_run(
        paths,
        phase="canary_removed",
        canary_uid=record.uid,
        canary_source_rel=source_rel_at_cleanup,
        canary_removed_at_utc=now_utc(),
    )


def verify_canary(run_id: str, live: Path, archive: Path, state: Path, backup: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("canary_removed", "canary_verified"))
    uid = int(data.get("canary_uid", -1))
    records = {record.uid: record for record in read_jsonl(paths["manifest"])}
    record = records.get(uid)
    if record is None:
        fail(f"canary UID absent from manifest: {uid}")
    if uid in build_uid_map(live):
        fail(f"canary UID was re-downloaded or restored unexpectedly: {uid}")
    verify_record_copies(record, paths, archive, build_archive_id_map(archive))
    return update_run(paths, phase="canary_verified", canary_verified=True, canary_verified_at_utc=now_utc())


def cleanup_remaining(run_id: str, live: Path, archive: Path, state: Path, backup: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("canary_verified", "cleanup_completed"))
    if not bool(data.get("canary_verified")):
        fail("cleanup canary has not been verified")
    canary_uid = int(data["canary_uid"])
    records = read_jsonl(paths["manifest"])
    uid_map = build_uid_map(live)
    archive_id_map = build_archive_id_map(archive)
    sources: List[Path] = []
    for record in records:
        verify_record_copies(record, paths, archive, archive_id_map)
        if record.uid == canary_uid:
            if record.uid in uid_map:
                fail("canary UID unexpectedly exists before bulk cleanup")
            continue
        sources.append(resolve_source(record, uid_map))
    for source in sources:
        source.unlink()
    for directory in (resolve(live) / "cur", resolve(live) / "new"):
        fsync_directory(directory)
    return update_run(
        paths,
        phase="cleanup_completed",
        cleanup_removed_count=len(sources) + 1,
        cleanup_completed_at_utc=now_utc(),
    )


def verify_cleanup(run_id: str, live: Path, archive: Path, state: Path, backup: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("cleanup_completed", "cleanup_verified"))
    records = read_jsonl(paths["manifest"])
    live_uids = build_uid_map(live)
    archive_id_map = build_archive_id_map(archive)
    remaining = [record.uid for record in records if record.uid in live_uids]
    if remaining:
        fail(f"selected UIDs remain in live INBOX after cleanup: {remaining[:5]}")
    for record in records:
        verify_record_copies(record, paths, archive, archive_id_map)
    if tmp_file_count(live) or tmp_file_count(archive):
        fail("temporary Maildir files present after cleanup")
    return update_run(
        paths,
        phase="cleanup_verified",
        cleanup_verified=True,
        cleanup_verified_at_utc=now_utc(),
        post_cleanup_live_count=len(live_uids),
    )


def rollback(run_id: str, live: Path, state: Path, backup: Path) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    records = read_jsonl(paths["manifest"])
    live = resolve(live)
    uid_map = build_uid_map(live)
    restored = 0
    for record in records:
        if record.uid in uid_map:
            current = uid_map[record.uid]
            if sha256_file(current) != record.sha256:
                fail(f"existing live UID hash mismatch during rollback: {record.uid}")
            continue
        snapshot = paths["snapshot_live"] / record.snapshot_rel
        if not snapshot.is_file() or sha256_file(snapshot) != record.sha256:
            fail(f"rollback snapshot missing or changed for UID {record.uid}")
        dest = ensure_under(live / record.source_rel, live, "rollback destination")
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            fail(f"rollback destination collision: {dest}")
        os.link(snapshot, dest)
        restored += 1
    return update_run(paths, phase="rolled_back", rollback_restored_count=restored, rolled_back_at_utc=now_utc())


def retire_snapshot(
    run_id: str,
    state: Path,
    backup: Path,
    minimum_days: int = 30,
    archive: Path = DEFAULT_ARCHIVE,
) -> Dict[str, object]:
    paths = run_paths(run_id, state, backup)
    data = read_json(paths["run_json"])
    require_phase(data, ("cleanup_verified", "snapshot_retired"))
    if not bool(data.get("cleanup_verified")) or not bool(data.get("external_verified")):
        fail("snapshot retirement requires verified cleanup and external backup")
    verify_external_manifest(data)
    records = read_jsonl(paths["manifest"])
    archive_id_map = build_archive_id_map(archive)
    for record in records:
        verify_record_copies(record, paths, archive, archive_id_map)
    created = datetime.fromisoformat(str(data["created_at_utc"]))
    age_days = (datetime.now(timezone.utc) - created).total_seconds() / 86400
    if age_days < minimum_days:
        fail(f"snapshot is only {age_days:.1f} days old; minimum is {minimum_days}")
    snapshot = ensure_under(paths["snapshot_bundle"], paths["backup_run"], "snapshot retirement")
    if snapshot.exists():
        shutil.rmtree(snapshot)
    return update_run(paths, phase="snapshot_retired", snapshot_retired=True, snapshot_retired_at_utc=now_utc())


def run_status(run_id: str, state: Path, backup: Path) -> Dict[str, object]:
    return read_json(run_paths(run_id, state, backup)["run_json"])


def _is_relative_to(path: Path, root: Path) -> bool:
    try:
        resolve(path).relative_to(resolve(root))
        return True
    except ValueError:
        return False


def mounted_ancestor(path: Path) -> Path:
    """Return the nearest actual mount point, refusing paths backed by root."""
    current = resolve(path)
    while True:
        if os.path.ismount(current):
            return current
        if current.parent == current:
            fail(f"cannot identify mounted filesystem for external target: {path}")
        current = current.parent


def compute_notmuch_ignore(
    current: Iterable[str],
    mail_root_children: Iterable[str],
    evolution_children: Iterable[str],
    mbsync_children: Iterable[str],
) -> List[str]:
    allowed_evolution = {
        "provider-live-archive",
        "betterbird-delta-maildirpp-20260704",
        "local-maildir",
        "test-maildir",
    }
    allowed_mbsync = {"provider-live", "provider-inbox-test"}
    ignore = {value for value in current if value}
    ignore -= {"evolution", "mbsync", *allowed_evolution, *allowed_mbsync}
    ignore.update(name for name in mail_root_children if name not in {"evolution", "mbsync"})
    ignore.update(name for name in evolution_children if name not in allowed_evolution)
    ignore.update(name for name in mbsync_children if name not in allowed_mbsync)
    ignore -= allowed_evolution | allowed_mbsync
    return sorted(ignore)


def configure_notmuch_scope(
    config: Path,
    mail_root: Path,
    backup_root: Path,
    notmuch_command: str = "notmuch",
) -> Dict[str, object]:
    config = resolve(config)
    mail_root = resolve(mail_root)
    backup_root = resolve(backup_root)
    if not config.is_file() or config.is_symlink():
        fail(f"missing or unsafe notmuch config: {config}")
    evolution = mail_root / "evolution"
    mbsync = mail_root / "mbsync"
    for path in (mail_root, evolution, mbsync):
        if not path.is_dir() or path.is_symlink():
            fail(f"missing or unsafe notmuch scope directory: {path}")

    def run_notmuch(arguments: Sequence[str], capture: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [notmuch_command, f"--config={config}", *arguments],
            check=True,
            text=True,
            capture_output=capture,
        )

    expected_db = "/mail/SearchIndex/notmuch/default"
    safety = {
        "database.path": expected_db,
        "database.mail_root": str(mail_root),
        "maildir.synchronize_flags": "false",
        "index.decrypt": "false",
    }
    for key, expected in safety.items():
        actual = run_notmuch(("config", "get", key)).stdout.strip()
        if actual != expected:
            fail(f"unsafe notmuch setting {key}: {actual!r} != {expected!r}")

    current_raw = run_notmuch(("config", "get", "new.ignore")).stdout.splitlines()
    current: Set[str] = {value.strip() for value in current_raw if value.strip()}
    allowed_evolution = {
        "provider-live-archive",
        "betterbird-delta-maildirpp-20260704",
        "local-maildir",
        "test-maildir",
    }
    allowed_mbsync = {"provider-live", "provider-inbox-test"}
    child_names: Dict[Path, List[str]] = {}
    for parent in (mail_root, evolution, mbsync):
        child_names[parent] = []
        for child in parent.iterdir():
            if child.is_symlink():
                fail(f"notmuch scope refuses symlink child: {child}")
            if child.is_dir():
                child_names[parent].append(child.name)
    ignore = compute_notmuch_ignore(
        current,
        child_names[mail_root],
        child_names[evolution],
        child_names[mbsync],
    )

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = backup_root / f"provider-live-archive-scope-{stamp}"
    if backup_dir.exists():
        fail(f"notmuch scope backup already exists: {backup_dir}")
    backup_dir.mkdir(parents=True, mode=0o700)
    shutil.copy2(config, backup_dir / "config.before")
    os.chmod(backup_dir / "config.before", 0o600)
    tags = run_notmuch(("dump", "--format=batch-tag")).stdout
    (backup_dir / "tags.before.batch-tag").write_text(tags, encoding="utf-8", newline="\n")
    paths = run_notmuch(("search", "--output=files", "*")).stdout
    historical_prefix = str(evolution / "local-maildir") + os.sep
    historical_indexed_files = sum(
        1 for path in paths.splitlines() if path.startswith(historical_prefix)
    )
    before_messages = run_notmuch(("count", "*")).stdout.strip()
    before_files = run_notmuch(("count", "--output=files", "*")).stdout.strip()
    (backup_dir / "paths.before.txt").write_text(paths, encoding="utf-8", newline="\n")
    for name in ("tags.before.batch-tag", "paths.before.txt"):
        digest = sha256_file(backup_dir / name)
        (backup_dir / f"{name}.sha256").write_text(f"{digest}  {name}\n", encoding="ascii")
    run_notmuch(("config", "set", "new.ignore", *ignore))
    after = run_notmuch(("config", "get", "new.ignore")).stdout.splitlines()
    return {
        "notmuch_scope_backup": str(backup_dir),
        "new_ignore_before": sorted(current),
        "new_ignore_after": [value.strip() for value in after if value.strip()],
        "allowed_evolution": sorted(allowed_evolution),
        "allowed_mbsync": sorted(allowed_mbsync),
        "before_messages": before_messages,
        "before_files": before_files,
        "historical_indexed_files_before": historical_indexed_files,
        "status": "notmuch_scope_configured",
    }


def print_rows(rows: Dict[str, object]) -> None:
    for key, value in rows.items():
        if isinstance(value, (dict, list)):
            print(f"{key}={json.dumps(value, sort_keys=True, separators=(',', ':'))}")
        elif isinstance(value, bool):
            print(f"{key}={'yes' if value else 'no'}")
        elif value is None:
            print(f"{key}=")
        else:
            print(f"{key}={value}")


def common_paths(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--live", default=str(DEFAULT_LIVE))
    parser.add_argument("--archive", default=str(DEFAULT_ARCHIVE))
    parser.add_argument("--state", default=str(DEFAULT_STATE))
    parser.add_argument("--backup", default=str(DEFAULT_BACKUP))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    layout = sub.add_parser("layout")
    common_paths(layout)

    count = sub.add_parser("count")
    count.add_argument("--live", default=str(DEFAULT_LIVE))
    count.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)

    estimate_parser = sub.add_parser("estimate")
    estimate_parser.add_argument("--live", default=str(DEFAULT_LIVE))
    estimate_parser.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)

    snapshot = sub.add_parser("snapshot")
    snapshot.add_argument("run_id")
    common_paths(snapshot)
    snapshot.add_argument("--mbsync-state", default=str(DEFAULT_MBSYNC_STATE))
    snapshot.add_argument("--config", default=str(DEFAULT_CONFIG))
    snapshot.add_argument("--threshold", type=int, default=DEFAULT_THRESHOLD)

    pack = sub.add_parser("external-pack")
    pack.add_argument("run_id")
    common_paths(pack)
    pack.add_argument("--external-target", required=True)
    pack.add_argument("--mail-root", default="/mail")
    pack.add_argument("--part-size", type=int, default=DEFAULT_PART_SIZE)

    copy = sub.add_parser("copy")
    copy.add_argument("run_id")
    common_paths(copy)

    verify = sub.add_parser("verify-copy")
    verify.add_argument("run_id")
    common_paths(verify)

    evolution = sub.add_parser("mark-evolution-validated")
    evolution.add_argument("run_id")
    common_paths(evolution)
    evolution.add_argument("--note", required=True)

    notmuch = sub.add_parser("verify-notmuch")
    notmuch.add_argument("run_id")
    common_paths(notmuch)
    notmuch.add_argument("--indexed-paths", required=True)
    notmuch.add_argument("--forbidden-prefix")

    canary = sub.add_parser("cleanup-canary")
    canary.add_argument("run_id")
    common_paths(canary)

    canary_verify = sub.add_parser("verify-canary")
    canary_verify.add_argument("run_id")
    common_paths(canary_verify)

    cleanup = sub.add_parser("cleanup-remaining")
    cleanup.add_argument("run_id")
    common_paths(cleanup)

    cleanup_verify = sub.add_parser("verify-cleanup")
    cleanup_verify.add_argument("run_id")
    common_paths(cleanup_verify)

    rollback_parser = sub.add_parser("rollback")
    rollback_parser.add_argument("run_id")
    common_paths(rollback_parser)

    retire = sub.add_parser("retire-snapshot")
    retire.add_argument("run_id")
    common_paths(retire)
    retire.add_argument("--minimum-days", type=int, default=30)

    status = sub.add_parser("run-status")
    status.add_argument("run_id")
    status.add_argument("--state", default=str(DEFAULT_STATE))
    status.add_argument("--backup", default=str(DEFAULT_BACKUP))

    scope = sub.add_parser("configure-notmuch-scope")
    scope.add_argument("--config", default=str(Path.home() / ".config/notmuch/default/config"))
    scope.add_argument("--mail-root", default="/mail/Mailstore")
    scope.add_argument("--backup-root", default="/mail/Backups/notmuch")
    scope.add_argument("--notmuch-command", default="notmuch")

    policy = sub.add_parser("audit-mbsync-config")
    policy.add_argument("--config", default=str(DEFAULT_CONFIG))
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "layout":
            create_layout(Path(args.archive), Path(args.state), Path(args.backup))
            print_rows({"archive": resolve(Path(args.archive)), "status": "layout_ready"})
        elif args.command in ("count", "estimate"):
            print_rows(estimate(Path(args.live), args.threshold))
        elif args.command == "snapshot":
            print_rows(snapshot_run(args.run_id, Path(args.live), Path(args.archive), Path(args.state), Path(args.backup), Path(args.mbsync_state), Path(args.config), args.threshold))
        elif args.command == "external-pack":
            print_rows(external_pack(args.run_id, Path(args.external_target), Path(args.state), Path(args.backup), Path(args.mail_root), args.part_size))
        elif args.command == "copy":
            print_rows(copy_to_archive(args.run_id, Path(args.state), Path(args.backup), Path(args.archive)))
        elif args.command == "verify-copy":
            print_rows(verify_copy(args.run_id, Path(args.live), Path(args.archive), Path(args.state), Path(args.backup)))
        elif args.command == "mark-evolution-validated":
            print_rows(mark_evolution_validated(args.run_id, Path(args.state), Path(args.backup), args.note))
        elif args.command == "verify-notmuch":
            forbidden = Path(args.forbidden_prefix) if args.forbidden_prefix else None
            print_rows(verify_notmuch_paths(args.run_id, Path(args.indexed_paths), Path(args.state), Path(args.backup), Path(args.archive), forbidden))
        elif args.command == "cleanup-canary":
            print_rows(cleanup_canary(args.run_id, Path(args.live), Path(args.archive), Path(args.state), Path(args.backup)))
        elif args.command == "verify-canary":
            print_rows(verify_canary(args.run_id, Path(args.live), Path(args.archive), Path(args.state), Path(args.backup)))
        elif args.command == "cleanup-remaining":
            print_rows(cleanup_remaining(args.run_id, Path(args.live), Path(args.archive), Path(args.state), Path(args.backup)))
        elif args.command == "verify-cleanup":
            print_rows(verify_cleanup(args.run_id, Path(args.live), Path(args.archive), Path(args.state), Path(args.backup)))
        elif args.command == "rollback":
            print_rows(rollback(args.run_id, Path(args.live), Path(args.state), Path(args.backup)))
        elif args.command == "retire-snapshot":
            print_rows(retire_snapshot(args.run_id, Path(args.state), Path(args.backup), args.minimum_days, Path(args.archive)))
        elif args.command == "run-status":
            print_rows(run_status(args.run_id, Path(args.state), Path(args.backup)))
        elif args.command == "configure-notmuch-scope":
            print_rows(configure_notmuch_scope(Path(args.config), Path(args.mail_root), Path(args.backup_root), args.notmuch_command))
        elif args.command == "audit-mbsync-config":
            print_rows(audit_mbsync_config(Path(args.config)))
        else:  # pragma: no cover
            fail(f"unsupported command: {args.command}")
    except (ArchiveError, transport.TransportError, OSError, subprocess.SubprocessError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
