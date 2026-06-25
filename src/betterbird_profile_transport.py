#!/usr/bin/env python3
"""Safely pack, split, restore, and verify a Betterbird profile tree.

This utility is designed for moving a large Betterbird/Thunderbird profile
from a Fedora VM to antiX staging before running the maildir-lite to Maildir++
converter. It uses only the Python standard library and never requires a
single large temporary archive file.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import gzip
import hashlib
import json
import os
import re
import stat
import sys
import tarfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import BinaryIO, Dict, Iterable, Iterator, List, Optional, Tuple


FORMAT_VERSION = "betterbird-profile-transport-v1"
ARCHIVE_BASENAME = "betterbird-profile.tar.gz"
PART_PREFIX = ARCHIVE_BASENAME + ".part"
INVENTORY_NAME = "inventory.jsonl"
MANIFEST_NAME = "manifest.json"
DEFAULT_SOURCE = "~/Betterbird-Email"
DEFAULT_DEST = "/mail/import-staging/betterbird-maildir"
DEFAULT_PART_SIZE = 1900 * 1024 * 1024
DEFAULT_COMPRESSION_LEVEL = 6
CHUNK_SIZE = 1024 * 1024
ACTIVE_PROFILE_MARKERS = (".parentlock", "parent.lock", "lock")


class TransportError(RuntimeError):
    """Raised for fatal transport safety or integrity failures."""


@dataclass(frozen=True)
class TreeEntry:
    path: Path
    rel_posix: str
    kind: str


class HashingReader:
    def __init__(self, fileobj: BinaryIO) -> None:
        self.fileobj = fileobj
        self.sha256 = hashlib.sha256()
        self.bytes_read = 0

    def read(self, size: int = -1) -> bytes:
        data = self.fileobj.read(size)
        if data:
            self.sha256.update(data)
            self.bytes_read += len(data)
        return data


class SplitWriter:
    def __init__(self, out_dir: Path, part_size: int) -> None:
        self.out_dir = out_dir
        self.part_size = part_size
        self.part_index = 0
        self.current: Optional[BinaryIO] = None
        self.current_path: Optional[Path] = None
        self.current_size = 0
        self.current_hash = hashlib.sha256()
        self.whole_hash = hashlib.sha256()
        self.total_size = 0
        self.parts: List[Dict[str, object]] = []
        self.closed = False

    def writable(self) -> bool:
        return True

    def write(self, data: bytes) -> int:
        if self.closed:
            raise ValueError("I/O operation on closed split writer")
        original_len = len(data)
        view = memoryview(data)
        offset = 0
        while offset < original_len:
            if self.current is None or self.current_size >= self.part_size:
                self._open_next_part()
            assert self.current is not None
            remaining = self.part_size - self.current_size
            chunk = view[offset : offset + remaining]
            self.current.write(chunk)
            chunk_bytes = bytes(chunk)
            self.current_hash.update(chunk_bytes)
            self.whole_hash.update(chunk_bytes)
            self.current_size += len(chunk)
            self.total_size += len(chunk)
            offset += len(chunk)
        return original_len

    def flush(self) -> None:
        if self.current is not None:
            self.current.flush()

    def close(self) -> None:
        if not self.closed:
            self._finalize_current_part()
            self.closed = True

    def _open_next_part(self) -> None:
        self._finalize_current_part()
        self.part_index += 1
        name = f"{PART_PREFIX}{self.part_index:04d}"
        path = self.out_dir / name
        if path.exists():
            raise TransportError(f"Refusing to overwrite existing part: {path}")
        self.current_path = path
        self.current = path.open("xb")
        self.current_size = 0
        self.current_hash = hashlib.sha256()

    def _finalize_current_part(self) -> None:
        if self.current is None:
            return
        self.current.flush()
        os.fsync(self.current.fileno())
        self.current.close()
        assert self.current_path is not None
        self.parts.append(
            {
                "index": self.part_index,
                "name": self.current_path.name,
                "size": self.current_size,
                "sha256": self.current_hash.hexdigest(),
            }
        )
        self.current = None
        self.current_path = None
        self.current_size = 0


class PartReader:
    def __init__(self, part_paths: List[Path]) -> None:
        self.part_paths = part_paths
        self.index = 0
        self.current: Optional[BinaryIO] = None

    def readable(self) -> bool:
        return True

    def read(self, size: int = -1) -> bytes:
        if size is None or size < 0:
            chunks = []
            while True:
                chunk = self.read(CHUNK_SIZE)
                if not chunk:
                    break
                chunks.append(chunk)
            return b"".join(chunks)

        remaining = size
        chunks = []
        while remaining > 0:
            if self.current is None and not self._open_next_part():
                break
            assert self.current is not None
            chunk = self.current.read(remaining)
            if chunk:
                chunks.append(chunk)
                remaining -= len(chunk)
                break
            self.current.close()
            self.current = None
        return b"".join(chunks)

    def close(self) -> None:
        if self.current is not None:
            self.current.close()
            self.current = None

    def _open_next_part(self) -> bool:
        if self.index >= len(self.part_paths):
            return False
        self.current = self.part_paths[self.index].open("rb")
        self.index += 1
        return True


class InventoryWriter:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.file = path.open("xb")
        self.sha256 = hashlib.sha256()
        self.bytes_written = 0
        self.entries = 0
        self.regular_files = 0
        self.directories = 0
        self.symlinks = 0
        self.regular_file_bytes = 0

    def write(self, row: Dict[str, object]) -> None:
        data = (json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8")
        self.file.write(data)
        self.sha256.update(data)
        self.bytes_written += len(data)
        self.entries += 1
        kind = str(row.get("type", ""))
        if kind == "regular":
            self.regular_files += 1
            self.regular_file_bytes += int(row.get("size", 0))
        elif kind == "directory":
            self.directories += 1
        elif kind == "symlink":
            self.symlinks += 1

    def close(self) -> None:
        self.file.flush()
        os.fsync(self.file.fileno())
        self.file.close()


def utc_now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")


def resolve_path(path: Path) -> Path:
    return path.expanduser().resolve()


def is_relative_to(child: Path, parent: Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def parse_size(value: str) -> int:
    text = value.strip()
    match = re.fullmatch(r"(\d+)\s*([kmgt]?i?b?)?", text, flags=re.IGNORECASE)
    if not match:
        raise argparse.ArgumentTypeError(f"Invalid size: {value!r}")
    number = int(match.group(1))
    suffix = (match.group(2) or "").lower()
    multipliers = {
        "": 1,
        "b": 1,
        "k": 1024,
        "kb": 1024,
        "kib": 1024,
        "m": 1024**2,
        "mb": 1024**2,
        "mib": 1024**2,
        "g": 1024**3,
        "gb": 1024**3,
        "gib": 1024**3,
        "t": 1024**4,
        "tb": 1024**4,
        "tib": 1024**4,
    }
    if suffix not in multipliers:
        raise argparse.ArgumentTypeError(f"Invalid size suffix: {value!r}")
    size = number * multipliers[suffix]
    if size <= 0:
        raise argparse.ArgumentTypeError("Size must be greater than zero")
    return size


def path_lexists(path: Path) -> bool:
    return os.path.lexists(str(path))


def safe_rel_posix(source: Path, path: Path) -> str:
    rel = path.relative_to(source)
    rel_posix = rel.as_posix()
    validate_archive_name(rel_posix)
    return rel_posix


def validate_archive_name(name: str) -> PurePosixPath:
    if not name or name == ".":
        raise TransportError("Archive entry has an empty or current-directory path")
    if "\\" in name:
        raise TransportError(f"Archive entry contains a backslash path separator: {name}")
    if re.match(r"^[A-Za-z]:", name):
        raise TransportError(f"Archive entry looks like a Windows absolute path: {name}")
    rel = PurePosixPath(name)
    if rel.is_absolute():
        raise TransportError(f"Archive entry is absolute: {name}")
    if any(part in ("", ".", "..") for part in rel.parts):
        raise TransportError(f"Archive entry contains an unsafe path segment: {name}")
    return rel


def safe_dest_path(dest: Path, archive_name: str) -> Path:
    rel = validate_archive_name(archive_name)
    target = dest.joinpath(*rel.parts)
    dest_resolved = dest.resolve()
    target_resolved = target.resolve(strict=False)
    if not is_relative_to(target_resolved, dest_resolved):
        raise TransportError(f"Archive entry escapes destination: {archive_name}")
    return target


def is_dangerous_destination(path: Path) -> bool:
    resolved = path.resolve(strict=False)
    dangerous = {Path("/").resolve(), Path.home().resolve()}
    if os.name == "nt":
        dangerous.add(Path(resolved.anchor).resolve())
    return resolved in dangerous


def ensure_empty_output_dir(out_dir: Path) -> None:
    if out_dir.exists():
        if not out_dir.is_dir():
            raise TransportError(f"Output path exists and is not a directory: {out_dir}")
        if any(out_dir.iterdir()):
            raise TransportError(f"Output directory is not empty: {out_dir}")
    else:
        out_dir.mkdir(parents=True)


def ensure_restore_destination(dest: Path, allow_non_empty: bool) -> None:
    if is_dangerous_destination(dest):
        raise TransportError(f"Refusing unsafe restore destination: {dest}")
    if dest.exists():
        if not dest.is_dir():
            raise TransportError(f"Restore destination exists and is not a directory: {dest}")
        if not allow_non_empty and any(dest.iterdir()):
            raise TransportError(
                f"Restore destination is not empty: {dest}. Use --allow-non-empty-dest only after manual review."
            )
    else:
        dest.mkdir(parents=True)


def find_active_markers(source: Path) -> List[Path]:
    return [source / name for name in ACTIVE_PROFILE_MARKERS if path_lexists(source / name)]


def scan_source_tree(source: Path, allow_symlinks: bool) -> Tuple[int, int]:
    symlinks: List[Path] = []
    special_files: List[Path] = []
    dirs_seen = 0
    files_seen = 0
    for root, dirs, files in os.walk(source, topdown=True, followlinks=False):
        root_path = Path(root)
        dirs.sort()
        files.sort()
        for name in dirs:
            path = root_path / name
            if path.is_symlink():
                symlinks.append(path)
            elif path.is_dir():
                dirs_seen += 1
            else:
                special_files.append(path)
        for name in files:
            path = root_path / name
            if path.is_symlink():
                symlinks.append(path)
            elif path.is_file():
                files_seen += 1
            else:
                special_files.append(path)
    if symlinks and not allow_symlinks:
        examples = ", ".join(str(p) for p in symlinks[:5])
        raise TransportError(
            f"Refusing to pack {len(symlinks)} symlink(s) by default. "
            f"Examples: {examples}. Use --allow-symlinks only after manual review."
        )
    if special_files:
        examples = ", ".join(str(p) for p in special_files[:5])
        raise TransportError(f"Refusing to pack unsupported special file(s): {examples}")
    return dirs_seen, files_seen


def iter_source_entries(source: Path, allow_symlinks: bool) -> Iterator[TreeEntry]:
    for root, dirs, files in os.walk(source, topdown=True, followlinks=False):
        root_path = Path(root)
        dirs.sort()
        files.sort()
        normal_dirs = []
        for name in dirs:
            path = root_path / name
            if path.is_symlink():
                if allow_symlinks:
                    yield TreeEntry(path, safe_rel_posix(source, path), "symlink")
                continue
            normal_dirs.append(name)
            yield TreeEntry(path, safe_rel_posix(source, path), "directory")
        dirs[:] = normal_dirs
        for name in files:
            path = root_path / name
            if path.is_symlink():
                if allow_symlinks:
                    yield TreeEntry(path, safe_rel_posix(source, path), "symlink")
            else:
                yield TreeEntry(path, safe_rel_posix(source, path), "regular")


def make_tarinfo(entry: TreeEntry, st: os.stat_result) -> tarfile.TarInfo:
    info = tarfile.TarInfo(entry.rel_posix)
    info.mode = stat.S_IMODE(st.st_mode)
    info.mtime = st.st_mtime
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    if entry.kind == "directory":
        info.type = tarfile.DIRTYPE
        info.size = 0
    elif entry.kind == "symlink":
        info.type = tarfile.SYMTYPE
        info.size = 0
        info.linkname = os.readlink(entry.path)
    else:
        info.type = tarfile.REGTYPE
        info.size = st.st_size
    return info


def add_directory(entry: TreeEntry, tar: tarfile.TarFile, inventory: InventoryWriter) -> None:
    st = entry.path.stat(follow_symlinks=False)
    tar.addfile(make_tarinfo(entry, st))
    inventory.write(
        {
            "path": entry.rel_posix,
            "type": "directory",
            "size": 0,
            "mode": stat.S_IMODE(st.st_mode),
            "mtime_ns": st.st_mtime_ns,
            "sha256": "",
        }
    )


def add_symlink(entry: TreeEntry, tar: tarfile.TarFile, inventory: InventoryWriter) -> None:
    st = entry.path.lstat()
    linkname = os.readlink(entry.path)
    validate_symlink_target(entry.rel_posix, linkname)
    tar.addfile(make_tarinfo(entry, st))
    inventory.write(
        {
            "path": entry.rel_posix,
            "type": "symlink",
            "size": 0,
            "mode": stat.S_IMODE(st.st_mode),
            "mtime_ns": st.st_mtime_ns,
            "linkname": linkname,
            "sha256": "",
        }
    )


def validate_symlink_target(source_name: str, linkname: str) -> None:
    if not linkname:
        raise TransportError(f"Symlink target is empty for {source_name}")
    if "\\" in linkname:
        raise TransportError(f"Symlink target contains backslash for {source_name}: {linkname}")
    if re.match(r"^[A-Za-z]:", linkname):
        raise TransportError(f"Symlink target looks like a Windows absolute path for {source_name}: {linkname}")
    target = PurePosixPath(linkname)
    if target.is_absolute():
        raise TransportError(f"Symlink target is absolute for {source_name}: {linkname}")
    if any(part in ("", ".", "..") for part in target.parts):
        raise TransportError(f"Symlink target contains unsafe segment for {source_name}: {linkname}")


def add_regular_file(entry: TreeEntry, tar: tarfile.TarFile, inventory: InventoryWriter) -> None:
    before = entry.path.stat(follow_symlinks=False)
    info = make_tarinfo(entry, before)
    with entry.path.open("rb") as raw:
        hashing_reader = HashingReader(raw)
        tar.addfile(info, hashing_reader)
    after = entry.path.stat(follow_symlinks=False)
    if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
        raise TransportError(f"Source file changed while packing: {entry.path}")
    if hashing_reader.bytes_read != before.st_size:
        raise TransportError(f"Short read while packing: {entry.path}")
    inventory.write(
        {
            "path": entry.rel_posix,
            "type": "regular",
            "size": before.st_size,
            "mode": stat.S_IMODE(before.st_mode),
            "mtime_ns": before.st_mtime_ns,
            "sha256": hashing_reader.sha256.hexdigest(),
        }
    )


def pack_profile(
    source: Path,
    out_dir: Path,
    part_size: int = DEFAULT_PART_SIZE,
    compression_level: int = DEFAULT_COMPRESSION_LEVEL,
    allow_active_profile: bool = False,
    allow_symlinks: bool = False,
) -> Path:
    source = resolve_path(source)
    out_dir = resolve_path(out_dir)
    if not source.exists() or not source.is_dir():
        raise TransportError(f"Source directory does not exist: {source}")
    if is_relative_to(out_dir, source):
        raise TransportError("Refusing output directory inside source tree")
    if not allow_active_profile:
        markers = find_active_markers(source)
        if markers:
            marker_text = ", ".join(str(p) for p in markers)
            raise TransportError(
                f"Refusing to pack an active-looking Betterbird profile; lock marker(s) found: {marker_text}"
            )
    compression_level = int(compression_level)
    if compression_level < 0 or compression_level > 9:
        raise TransportError("--compression-level must be between 0 and 9")
    scan_source_tree(source, allow_symlinks)
    ensure_empty_output_dir(out_dir)

    inventory_path = out_dir / INVENTORY_NAME
    manifest_path = out_dir / MANIFEST_NAME
    inventory = InventoryWriter(inventory_path)
    split_writer = SplitWriter(out_dir, part_size)
    try:
        with gzip.GzipFile(filename="", mode="wb", fileobj=split_writer, compresslevel=compression_level, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w|") as tar:
                for entry in iter_source_entries(source, allow_symlinks):
                    if entry.kind == "directory":
                        add_directory(entry, tar, inventory)
                    elif entry.kind == "symlink":
                        add_symlink(entry, tar, inventory)
                    else:
                        add_regular_file(entry, tar, inventory)
        split_writer.close()
        inventory.close()
        if not split_writer.parts:
            raise TransportError("Archive did not produce any part files")
        manifest = build_manifest(source, out_dir, part_size, compression_level, split_writer, inventory)
        write_json_atomic(manifest_path, manifest)
        return manifest_path
    finally:
        try:
            split_writer.close()
        finally:
            if not inventory.file.closed:
                inventory.close()


def build_manifest(
    source: Path,
    out_dir: Path,
    part_size: int,
    compression_level: int,
    split_writer: SplitWriter,
    inventory: InventoryWriter,
) -> Dict[str, object]:
    return {
        "format": FORMAT_VERSION,
        "created_at_utc": utc_now_iso(),
        "source": {
            "path": str(source),
            "root_name": source.name,
            "entries": inventory.entries,
            "regular_files": inventory.regular_files,
            "directories": inventory.directories,
            "symlinks": inventory.symlinks,
            "regular_file_bytes": inventory.regular_file_bytes,
        },
        "archive": {
            "name": ARCHIVE_BASENAME,
            "compression": "gzip",
            "compression_level": compression_level,
            "part_size": part_size,
            "size": split_writer.total_size,
            "sha256": split_writer.whole_hash.hexdigest(),
            "parts": split_writer.parts,
        },
        "inventory": {
            "name": INVENTORY_NAME,
            "size": inventory.bytes_written,
            "sha256": inventory.sha256.hexdigest(),
            "entries": inventory.entries,
        },
        "restore": {
            "recommended_dest": DEFAULT_DEST,
            "converter_script": "src/betterbird_maildirlite_to_maildirpp.py",
        },
    }


def write_json_atomic(path: Path, data: Dict[str, object]) -> None:
    temp_path = path.with_name(path.name + ".tmp")
    with temp_path.open("x", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(temp_path, path)


def load_manifest(manifest_path: Path) -> Dict[str, object]:
    manifest_path = resolve_path(manifest_path)
    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = json.load(f)
    if manifest.get("format") != FORMAT_VERSION:
        raise TransportError(f"Unsupported manifest format: {manifest.get('format')!r}")
    archive = manifest.get("archive")
    inventory = manifest.get("inventory")
    if not isinstance(archive, dict) or not isinstance(inventory, dict):
        raise TransportError("Manifest is missing archive or inventory section")
    return manifest


def manifest_dir(manifest_path: Path) -> Path:
    return resolve_path(manifest_path).parent


def part_paths_from_manifest(manifest_path: Path, manifest: Dict[str, object]) -> List[Path]:
    base = manifest_dir(manifest_path)
    archive = manifest["archive"]
    assert isinstance(archive, dict)
    parts = archive.get("parts")
    if not isinstance(parts, list) or not parts:
        raise TransportError("Manifest has no archive parts")
    paths: List[Path] = []
    for part in parts:
        if not isinstance(part, dict):
            raise TransportError("Manifest archive part entry is not an object")
        name = str(part.get("name", ""))
        part_name = Path(name)
        if part_name.is_absolute() or part_name.name != name:
            raise TransportError(f"Unsafe part filename in manifest: {name}")
        paths.append(base / name)
    return paths


def verify_archive_from_manifest(manifest_path: Path) -> Dict[str, int]:
    manifest = load_manifest(manifest_path)
    archive = manifest["archive"]
    assert isinstance(archive, dict)
    parts = archive.get("parts")
    assert isinstance(parts, list)
    whole_hash = hashlib.sha256()
    total_size = 0
    checked_parts = 0
    paths = part_paths_from_manifest(manifest_path, manifest)
    for path, part in zip(paths, parts):
        if not path.is_file():
            raise TransportError(f"Missing archive part: {path}")
        part_hash = hashlib.sha256()
        part_size = 0
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(CHUNK_SIZE), b""):
                part_hash.update(chunk)
                whole_hash.update(chunk)
                part_size += len(chunk)
                total_size += len(chunk)
        expected_size = int(part.get("size", -1))
        expected_sha = str(part.get("sha256", ""))
        if part_size != expected_size:
            raise TransportError(f"Archive part size mismatch for {path.name}: {part_size} != {expected_size}")
        if part_hash.hexdigest() != expected_sha:
            raise TransportError(f"Archive part SHA256 mismatch for {path.name}")
        checked_parts += 1
    if total_size != int(archive.get("size", -1)):
        raise TransportError(f"Archive size mismatch: {total_size} != {archive.get('size')}")
    if whole_hash.hexdigest() != str(archive.get("sha256", "")):
        raise TransportError("Whole archive SHA256 mismatch")
    return {"parts": checked_parts, "bytes": total_size}


def read_inventory(manifest_path: Path, manifest: Dict[str, object]) -> List[Dict[str, object]]:
    inventory_meta = manifest["inventory"]
    assert isinstance(inventory_meta, dict)
    name = str(inventory_meta.get("name", ""))
    inventory_name = Path(name)
    if inventory_name.is_absolute() or inventory_name.name != name:
        raise TransportError(f"Unsafe inventory filename in manifest: {name}")
    path = manifest_dir(manifest_path) / name
    if not path.is_file():
        raise TransportError(f"Inventory file not found: {path}")
    digest = hashlib.sha256()
    size = 0
    rows: List[Dict[str, object]] = []
    with path.open("rb") as f:
        for line_number, line in enumerate(f, start=1):
            digest.update(line)
            size += len(line)
            if not line.strip():
                continue
            try:
                row = json.loads(line.decode("utf-8"))
            except json.JSONDecodeError as exc:
                raise TransportError(f"Invalid inventory JSON on line {line_number}: {exc}") from exc
            row_path = str(row.get("path", ""))
            validate_archive_name(row_path)
            rows.append(row)
    if size != int(inventory_meta.get("size", -1)):
        raise TransportError(f"Inventory size mismatch: {size} != {inventory_meta.get('size')}")
    if digest.hexdigest() != str(inventory_meta.get("sha256", "")):
        raise TransportError("Inventory SHA256 mismatch")
    if len(rows) != int(inventory_meta.get("entries", -1)):
        raise TransportError(f"Inventory entry count mismatch: {len(rows)} != {inventory_meta.get('entries')}")
    return rows


def validate_tar_member(member: tarfile.TarInfo, allow_symlinks: bool) -> None:
    validate_archive_name(member.name)
    if member.isdir() or member.isfile():
        return
    if member.issym():
        if not allow_symlinks:
            raise TransportError(f"Refusing to extract symlink by default: {member.name}")
        validate_symlink_target(member.name, member.linkname)
        return
    raise TransportError(f"Refusing unsupported tar entry type for {member.name}")


def copy_exact(fileobj: BinaryIO, target: BinaryIO, expected_size: int) -> int:
    copied = 0
    while True:
        chunk = fileobj.read(CHUNK_SIZE)
        if not chunk:
            break
        target.write(chunk)
        copied += len(chunk)
    if copied != expected_size:
        raise TransportError(f"Extracted size mismatch: {copied} != {expected_size}")
    return copied


def unpack_manifest(
    manifest_path: Path,
    dest: Path,
    allow_non_empty_dest: bool = False,
    allow_symlinks: bool = False,
    skip_archive_verify: bool = False,
) -> Dict[str, int]:
    manifest = load_manifest(manifest_path)
    if not skip_archive_verify:
        verify_archive_from_manifest(manifest_path)
    part_paths = part_paths_from_manifest(manifest_path, manifest)
    dest = resolve_path(dest)
    ensure_restore_destination(dest, allow_non_empty_dest)
    pending_symlinks: List[Tuple[Path, str]] = []
    summary = {"directories": 0, "regular_files": 0, "symlinks": 0, "bytes": 0}
    reader = PartReader(part_paths)
    try:
        with tarfile.open(fileobj=reader, mode="r|gz") as tar:
            for member in tar:
                validate_tar_member(member, allow_symlinks)
                target_path = safe_dest_path(dest, member.name)
                if member.isdir():
                    target_path.mkdir(parents=True, exist_ok=True)
                    apply_metadata(target_path, member, follow_symlinks=False)
                    summary["directories"] += 1
                elif member.isfile():
                    target_path.parent.mkdir(parents=True, exist_ok=True)
                    extracted = tar.extractfile(member)
                    if extracted is None:
                        raise TransportError(f"Could not read tar member: {member.name}")
                    with target_path.open("xb") as out:
                        copied = copy_exact(extracted, out, member.size)
                    apply_metadata(target_path, member, follow_symlinks=True)
                    summary["regular_files"] += 1
                    summary["bytes"] += copied
                elif member.issym():
                    pending_symlinks.append((target_path, member.linkname))
        for target_path, linkname in pending_symlinks:
            target_path.parent.mkdir(parents=True, exist_ok=True)
            if target_path.exists() or target_path.is_symlink():
                raise TransportError(f"Refusing to overwrite existing path with symlink: {target_path}")
            os.symlink(linkname, target_path)
            summary["symlinks"] += 1
    finally:
        reader.close()
    return summary


def apply_metadata(path: Path, member: tarfile.TarInfo, follow_symlinks: bool) -> None:
    try:
        os.chmod(path, member.mode, follow_symlinks=follow_symlinks)
    except (NotImplementedError, PermissionError, OSError):
        pass
    try:
        os.utime(path, (member.mtime, member.mtime), follow_symlinks=follow_symlinks)
    except (NotImplementedError, PermissionError, OSError):
        pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(CHUNK_SIZE), b""):
            digest.update(chunk)
    return digest.hexdigest()


def actual_tree_paths(dest: Path) -> Dict[str, str]:
    found: Dict[str, str] = {}
    for root, dirs, files in os.walk(dest, topdown=True, followlinks=False):
        root_path = Path(root)
        dirs.sort()
        files.sort()
        normal_dirs = []
        for name in dirs:
            path = root_path / name
            rel = path.relative_to(dest).as_posix()
            if path.is_symlink():
                found[rel] = "symlink"
            else:
                found[rel] = "directory"
                normal_dirs.append(name)
        dirs[:] = normal_dirs
        for name in files:
            path = root_path / name
            rel = path.relative_to(dest).as_posix()
            found[rel] = "symlink" if path.is_symlink() else "regular"
    return found


def verify_tree_from_manifest(manifest_path: Path, dest: Path) -> Dict[str, int]:
    manifest = load_manifest(manifest_path)
    inventory = read_inventory(manifest_path, manifest)
    dest = resolve_path(dest)
    if not dest.exists() or not dest.is_dir():
        raise TransportError(f"Restore destination does not exist: {dest}")
    expected_paths = {str(row["path"]): str(row["type"]) for row in inventory}
    actual_paths = actual_tree_paths(dest)
    missing = sorted(set(expected_paths) - set(actual_paths))
    extra = sorted(set(actual_paths) - set(expected_paths))
    if missing:
        raise TransportError(f"Restored tree is missing {len(missing)} path(s); first: {missing[0]}")
    if extra:
        raise TransportError(f"Restored tree has {len(extra)} extra path(s); first: {extra[0]}")
    verified_files = 0
    verified_bytes = 0
    for row in inventory:
        rel = str(row["path"])
        expected_type = str(row["type"])
        actual_type = actual_paths[rel]
        if actual_type != expected_type:
            raise TransportError(f"Type mismatch for {rel}: {actual_type} != {expected_type}")
        path = safe_dest_path(dest, rel)
        if expected_type == "regular":
            expected_size = int(row["size"])
            actual_size = path.stat().st_size
            if actual_size != expected_size:
                raise TransportError(f"Size mismatch for {rel}: {actual_size} != {expected_size}")
            expected_sha = str(row["sha256"])
            actual_sha = sha256_file(path)
            if actual_sha != expected_sha:
                raise TransportError(f"SHA256 mismatch for {rel}")
            verified_files += 1
            verified_bytes += actual_size
        elif expected_type == "directory":
            if not path.is_dir():
                raise TransportError(f"Directory missing: {rel}")
        elif expected_type == "symlink":
            if not path.is_symlink():
                raise TransportError(f"Symlink missing: {rel}")
            expected_link = str(row.get("linkname", ""))
            actual_link = os.readlink(path)
            if actual_link != expected_link:
                raise TransportError(f"Symlink target mismatch for {rel}")
        else:
            raise TransportError(f"Unsupported inventory type for {rel}: {expected_type}")
    return {"entries": len(inventory), "regular_files": verified_files, "bytes": verified_bytes}


def cmd_pack(args: argparse.Namespace) -> int:
    manifest = pack_profile(
        source=Path(args.source),
        out_dir=Path(args.out),
        part_size=args.part_size,
        compression_level=args.compression_level,
        allow_active_profile=args.allow_active_profile,
        allow_symlinks=args.allow_symlinks,
    )
    loaded = load_manifest(manifest)
    archive = loaded["archive"]
    source = loaded["source"]
    assert isinstance(archive, dict)
    assert isinstance(source, dict)
    print("mode=pack")
    print(f"source={loaded['source']['path']}")
    print(f"out={manifest.parent}")
    print(f"manifest={manifest}")
    print(f"parts={len(archive['parts'])}")
    print(f"archive_bytes={archive['size']}")
    print(f"regular_files={source['regular_files']}")
    print(f"regular_file_bytes={source['regular_file_bytes']}")
    return 0


def cmd_verify_archive(args: argparse.Namespace) -> int:
    summary = verify_archive_from_manifest(Path(args.manifest))
    print("mode=verify-archive")
    print(f"manifest={resolve_path(Path(args.manifest))}")
    print(f"parts={summary['parts']}")
    print(f"archive_bytes={summary['bytes']}")
    print("status=ok")
    return 0


def cmd_unpack(args: argparse.Namespace) -> int:
    summary = unpack_manifest(
        manifest_path=Path(args.manifest),
        dest=Path(args.dest),
        allow_non_empty_dest=args.allow_non_empty_dest,
        allow_symlinks=args.allow_symlinks,
        skip_archive_verify=args.skip_archive_verify,
    )
    print("mode=unpack")
    print(f"manifest={resolve_path(Path(args.manifest))}")
    print(f"dest={resolve_path(Path(args.dest))}")
    print(f"directories={summary['directories']}")
    print(f"regular_files={summary['regular_files']}")
    print(f"symlinks={summary['symlinks']}")
    print(f"bytes={summary['bytes']}")
    print("status=ok")
    return 0


def cmd_verify_tree(args: argparse.Namespace) -> int:
    summary = verify_tree_from_manifest(Path(args.manifest), Path(args.dest))
    print("mode=verify-tree")
    print(f"manifest={resolve_path(Path(args.manifest))}")
    print(f"dest={resolve_path(Path(args.dest))}")
    print(f"entries={summary['entries']}")
    print(f"regular_files={summary['regular_files']}")
    print(f"bytes={summary['bytes']}")
    print("status=ok")
    return 0


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pack, split, restore, and verify a large Betterbird profile tree."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    pack = subparsers.add_parser("pack", help="Create split verified tar.gz parts from a Betterbird profile")
    pack.add_argument("--source", default=DEFAULT_SOURCE, help="Betterbird profile root to pack")
    pack.add_argument("--out", required=True, help="Output directory for parts, manifest, and inventory")
    pack.add_argument("--part-size", type=parse_size, default=DEFAULT_PART_SIZE, help="Part size, default 1900MiB")
    pack.add_argument("--compression-level", type=int, default=DEFAULT_COMPRESSION_LEVEL, help="gzip level 0-9")
    pack.add_argument(
        "--allow-active-profile",
        action="store_true",
        help="Allow packing when Betterbird lock markers are present after manual verification",
    )
    pack.add_argument(
        "--allow-symlinks",
        action="store_true",
        help="Archive symlinks after manual review. Symlink targets must remain relative and safe.",
    )
    pack.set_defaults(func=cmd_pack)

    verify_archive = subparsers.add_parser("verify-archive", help="Verify split parts and whole archive hash")
    verify_archive.add_argument("--manifest", required=True, help="Path to manifest.json")
    verify_archive.set_defaults(func=cmd_verify_archive)

    unpack = subparsers.add_parser("unpack", help="Restore a split archive into antiX staging")
    unpack.add_argument("--manifest", required=True, help="Path to manifest.json")
    unpack.add_argument("--dest", default=DEFAULT_DEST, help="Restore destination")
    unpack.add_argument(
        "--allow-non-empty-dest",
        action="store_true",
        help="Allow restore into a non-empty destination after manual review",
    )
    unpack.add_argument(
        "--allow-symlinks",
        action="store_true",
        help="Extract safe relative symlinks after manual review",
    )
    unpack.add_argument(
        "--skip-archive-verify",
        action="store_true",
        help="Skip pre-extraction archive verification when verify-archive has already passed",
    )
    unpack.set_defaults(func=cmd_unpack)

    verify_tree = subparsers.add_parser("verify-tree", help="Verify restored files against inventory.jsonl")
    verify_tree.add_argument("--manifest", required=True, help="Path to manifest.json")
    verify_tree.add_argument("--dest", default=DEFAULT_DEST, help="Restored profile destination")
    verify_tree.set_defaults(func=cmd_verify_tree)

    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    try:
        return int(args.func(args))
    except TransportError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
