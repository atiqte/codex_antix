#!/usr/bin/env python3
"""Safely pack, split, restore, and verify a converted Maildir++ archive.

This utility is for an already-converted canonical Maildir++ tree, such as the
Fedora Evolution-validated Betterbird archive, not for the original Betterbird
profile. It reuses the repository's tested split-archive transport primitives
and adds Maildir++-specific preflight checks.
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

try:
    import betterbird_profile_transport as transport
except ModuleNotFoundError:  # pragma: no cover - defensive for unusual import paths.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import betterbird_profile_transport as transport


FORMAT_VERSION = "maildirpp-archive-transport-v1"
ARCHIVE_BASENAME = "maildirpp-archive.tar.gz"
PART_PREFIX = ARCHIVE_BASENAME + ".part"
DEFAULT_SOURCE = "/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp"
DEFAULT_DEST = "/mail/Mailstore/evolution/local-maildir"
STATE_DIRS = ("cur", "new", "tmp")
_ORIGINAL_TRANSPORT_CONFIG = {
    "FORMAT_VERSION": transport.FORMAT_VERSION,
    "ARCHIVE_BASENAME": transport.ARCHIVE_BASENAME,
    "PART_PREFIX": transport.PART_PREFIX,
    "DEFAULT_DEST": transport.DEFAULT_DEST,
    "ACTIVE_PROFILE_MARKERS": transport.ACTIVE_PROFILE_MARKERS,
}


class MaildirppError(transport.TransportError):
    """Raised for Maildir++ archive transport safety failures."""


@dataclass(frozen=True)
class MaildirppInspection:
    source: Path
    maildir_folders: int
    dot_folders: int
    cur_files: int
    new_files: int
    tmp_files: int
    metadata_files: int
    bytes_regular: int

    def as_dict(self) -> Dict[str, object]:
        return {
            "source": str(self.source),
            "maildir_folders": self.maildir_folders,
            "dot_folders": self.dot_folders,
            "cur_files": self.cur_files,
            "new_files": self.new_files,
            "tmp_files": self.tmp_files,
            "metadata_files": self.metadata_files,
            "bytes_regular": self.bytes_regular,
        }


def configure_transport() -> None:
    """Set split-archive defaults for the converted Maildir++ archive tool."""

    transport.FORMAT_VERSION = FORMAT_VERSION
    transport.ARCHIVE_BASENAME = ARCHIVE_BASENAME
    transport.PART_PREFIX = PART_PREFIX
    transport.DEFAULT_DEST = DEFAULT_DEST
    transport.ACTIVE_PROFILE_MARKERS = ()


def restore_transport() -> None:
    """Restore imported transport module globals for long-lived Python callers."""

    for name, value in _ORIGINAL_TRANSPORT_CONFIG.items():
        setattr(transport, name, value)


def is_state_dir(path: Path) -> bool:
    return path.name in STATE_DIRS and path.parent != path


def is_under_state_dir(path: Path, source: Path) -> bool:
    try:
        rel_parts = path.relative_to(source).parts
    except ValueError:
        return False
    return any(part in STATE_DIRS for part in rel_parts)


def discover_maildir_folders(source: Path) -> List[Path]:
    folders: List[Path] = []
    for root, dirs, _files in os.walk(source, topdown=True, followlinks=False):
        root_path = Path(root)
        dirs[:] = sorted(dirs)
        dir_set = set(dirs)
        if any(name in dir_set for name in STATE_DIRS):
            folders.append(root_path)
        dirs[:] = [name for name in dirs if name not in STATE_DIRS]
    return sorted(folders, key=lambda p: str(p.relative_to(source)) if p != source else "")


def inspect_maildirpp(source: Path, allow_tmp_files: bool = False, allow_symlinks: bool = False) -> MaildirppInspection:
    source = transport.resolve_path(source)
    if not source.exists() or not source.is_dir():
        raise MaildirppError(f"Source directory does not exist: {source}")

    errors: List[str] = []

    maildir_folders = discover_maildir_folders(source)
    if source not in maildir_folders:
        maildir_folders.insert(0, source)

    cur_files = 0
    new_files = 0
    tmp_files = 0
    metadata_files = 0
    bytes_regular = 0
    dot_folders = 0

    for folder in maildir_folders:
        if folder != source:
            dot_folders += 1
            if not folder.name.startswith("."):
                errors.append(f"non-dot-maildir-folder:{folder.relative_to(source).as_posix()}")
        folder_rel = folder.relative_to(source).as_posix() or "."
        state_dir_symlinks = [name for name in STATE_DIRS if (folder / name).is_symlink()]
        missing_states = [name for name in STATE_DIRS if name not in state_dir_symlinks and not (folder / name).is_dir()]
        if state_dir_symlinks:
            errors.append(f"maildir-folder-state-dir-symlink:{folder_rel}:{','.join(state_dir_symlinks)}")
        if missing_states:
            errors.append(f"maildir-folder-missing-state-dirs:{folder_rel}:" + ",".join(missing_states))
        if state_dir_symlinks or missing_states:
            continue
        for state in STATE_DIRS:
            state_dir = folder / state
            for child in sorted(state_dir.iterdir(), key=lambda p: p.name):
                rel = child.relative_to(source).as_posix()
                if child.is_symlink():
                    errors.append(f"symlink-in-{state}:{rel}")
                    continue
                if child.is_dir():
                    errors.append(f"directory-in-{state}:{rel}")
                    continue
                if not child.is_file():
                    errors.append(f"special-file-in-{state}:{rel}")
                    continue
                size = child.stat().st_size
                bytes_regular += size
                if state == "cur":
                    cur_files += 1
                elif state == "new":
                    new_files += 1
                else:
                    tmp_files += 1

    for root, dirs, files in os.walk(source, topdown=True, followlinks=False):
        root_path = Path(root)
        dirs[:] = sorted(dirs)
        for name in list(dirs):
            path = root_path / name
            rel = path.relative_to(source).as_posix()
            if path.is_symlink():
                if not allow_symlinks:
                    errors.append(f"symlink-directory:{rel}")
        for name in sorted(files):
            path = root_path / name
            rel = path.relative_to(source).as_posix()
            if is_under_state_dir(path, source):
                continue
            if path.is_symlink():
                if not allow_symlinks:
                    errors.append(f"symlink-file:{rel}")
            elif path.is_file():
                metadata_files += 1
                bytes_regular += path.stat().st_size
            else:
                errors.append(f"special-file:{rel}")

    if tmp_files and not allow_tmp_files:
        errors.append(f"tmp-files-present:{tmp_files}")

    if errors:
        preview = "; ".join(errors[:10])
        suffix = "" if len(errors) <= 10 else f"; ... {len(errors) - 10} more"
        raise MaildirppError(f"Maildir++ inspection failed: {preview}{suffix}")

    return MaildirppInspection(
        source=source,
        maildir_folders=len(maildir_folders),
        dot_folders=dot_folders,
        cur_files=cur_files,
        new_files=new_files,
        tmp_files=tmp_files,
        metadata_files=metadata_files,
        bytes_regular=bytes_regular,
    )


def print_summary(mode: str, rows: Dict[str, object]) -> None:
    print(f"mode={mode}")
    for key, value in rows.items():
        print(f"{key}={value}")
    print("status=ok")


def cmd_inspect(args: argparse.Namespace) -> int:
    summary = inspect_maildirpp(
        Path(args.source),
        allow_tmp_files=args.allow_tmp_files,
        allow_symlinks=args.allow_symlinks,
    )
    print_summary("inspect", summary.as_dict())
    return 0


def cmd_pack(args: argparse.Namespace) -> int:
    configure_transport()
    try:
        source = transport.resolve_path(Path(args.source))
        preflight = inspect_maildirpp(
            source,
            allow_tmp_files=args.allow_tmp_files,
            allow_symlinks=args.allow_symlinks,
        )
        manifest = transport.pack_profile(
            source=source,
            out_dir=Path(args.out),
            part_size=args.part_size,
            compression_level=args.compression_level,
            allow_active_profile=True,
            allow_symlinks=args.allow_symlinks,
        )
        loaded = transport.load_manifest(manifest)
        archive = loaded["archive"]
        assert isinstance(archive, dict)
        print("mode=pack")
        print(f"source={source}")
        print(f"out={manifest.parent}")
        print(f"manifest={manifest}")
        print(f"parts={len(archive['parts'])}")
        print(f"archive_bytes={archive['size']}")
        print(f"maildir_folders={preflight.maildir_folders}")
        print(f"cur_files={preflight.cur_files}")
        print(f"new_files={preflight.new_files}")
        print(f"tmp_files={preflight.tmp_files}")
        print(f"bytes_regular={preflight.bytes_regular}")
        print("status=ok")
        return 0
    finally:
        restore_transport()


def cmd_verify_archive(args: argparse.Namespace) -> int:
    configure_transport()
    try:
        summary = transport.verify_archive_from_manifest(Path(args.manifest))
        print_summary(
            "verify-archive",
            {
                "manifest": str(transport.resolve_path(Path(args.manifest))),
                "parts": summary["parts"],
                "archive_bytes": summary["bytes"],
            },
        )
        return 0
    finally:
        restore_transport()


def cmd_unpack(args: argparse.Namespace) -> int:
    configure_transport()
    try:
        summary = transport.unpack_manifest(
            manifest_path=Path(args.manifest),
            dest=Path(args.dest),
            allow_non_empty_dest=args.allow_non_empty_dest,
            allow_symlinks=args.allow_symlinks,
            skip_archive_verify=args.skip_archive_verify,
        )
        post = inspect_maildirpp(
            Path(args.dest),
            allow_tmp_files=args.allow_tmp_files,
            allow_symlinks=args.allow_symlinks,
        )
        rows: Dict[str, object] = {
            "manifest": str(transport.resolve_path(Path(args.manifest))),
            "dest": str(transport.resolve_path(Path(args.dest))),
            "directories": summary["directories"],
            "regular_files": summary["regular_files"],
            "bytes": summary["bytes"],
            "maildir_folders": post.maildir_folders,
            "cur_files": post.cur_files,
            "new_files": post.new_files,
            "tmp_files": post.tmp_files,
        }
        print_summary("unpack", rows)
        return 0
    finally:
        restore_transport()


def cmd_verify_tree(args: argparse.Namespace) -> int:
    configure_transport()
    try:
        summary = transport.verify_tree_from_manifest(Path(args.manifest), Path(args.dest))
        post = inspect_maildirpp(
            Path(args.dest),
            allow_tmp_files=args.allow_tmp_files,
            allow_symlinks=args.allow_symlinks,
        )
        rows: Dict[str, object] = {
            "manifest": str(transport.resolve_path(Path(args.manifest))),
            "dest": str(transport.resolve_path(Path(args.dest))),
            "entries": summary["entries"],
            "regular_files": summary["regular_files"],
            "bytes": summary["bytes"],
            "maildir_folders": post.maildir_folders,
            "cur_files": post.cur_files,
            "new_files": post.new_files,
            "tmp_files": post.tmp_files,
        }
        print_summary("verify-tree", rows)
        return 0
    finally:
        restore_transport()


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pack, split, restore, and verify an already-converted canonical Maildir++ archive."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    inspect = subparsers.add_parser("inspect", help="Validate and summarize a converted Maildir++ tree")
    inspect.add_argument("--source", default=DEFAULT_SOURCE, help="Converted Maildir++ root to inspect")
    inspect.add_argument(
        "--allow-tmp-files",
        action="store_true",
        help="Allow files in Maildir tmp directories after manual review",
    )
    inspect.add_argument(
        "--allow-symlinks",
        action="store_true",
        help="Allow non-message metadata symlinks after manual review",
    )
    inspect.set_defaults(func=cmd_inspect)

    pack = subparsers.add_parser("pack", help="Create split verified tar.gz parts from a converted Maildir++ tree")
    pack.add_argument("--source", default=DEFAULT_SOURCE, help="Converted Maildir++ root to pack")
    pack.add_argument("--out", required=True, help="Output directory for parts, manifest, and inventory")
    pack.add_argument("--part-size", type=transport.parse_size, default=transport.DEFAULT_PART_SIZE, help="Part size, default 1900MiB")
    pack.add_argument("--compression-level", type=int, default=transport.DEFAULT_COMPRESSION_LEVEL, help="gzip level 0-9")
    pack.add_argument(
        "--allow-tmp-files",
        action="store_true",
        help="Allow files in Maildir tmp directories after manual review",
    )
    pack.add_argument(
        "--allow-symlinks",
        action="store_true",
        help="Archive safe relative symlinks after manual review",
    )
    pack.set_defaults(func=cmd_pack)

    verify_archive = subparsers.add_parser("verify-archive", help="Verify split parts and whole archive hash")
    verify_archive.add_argument("--manifest", required=True, help="Path to manifest.json")
    verify_archive.set_defaults(func=cmd_verify_archive)

    unpack = subparsers.add_parser("unpack", help="Restore a split archive into the antiX Maildir++ archive target")
    unpack.add_argument("--manifest", required=True, help="Path to manifest.json")
    unpack.add_argument("--dest", default=DEFAULT_DEST, help="Restore destination")
    unpack.add_argument(
        "--allow-non-empty-dest",
        action="store_true",
        help="Allow restore into a non-empty destination after manual review",
    )
    unpack.add_argument(
        "--allow-tmp-files",
        action="store_true",
        help="Allow files in Maildir tmp directories after manual review",
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

    verify_tree = subparsers.add_parser("verify-tree", help="Verify restored files and Maildir++ layout")
    verify_tree.add_argument("--manifest", required=True, help="Path to manifest.json")
    verify_tree.add_argument("--dest", default=DEFAULT_DEST, help="Restored Maildir++ archive destination")
    verify_tree.add_argument(
        "--allow-tmp-files",
        action="store_true",
        help="Allow files in Maildir tmp directories after manual review",
    )
    verify_tree.add_argument(
        "--allow-symlinks",
        action="store_true",
        help="Allow non-message metadata symlinks after manual review",
    )
    verify_tree.set_defaults(func=cmd_verify_tree)

    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)
    try:
        return int(args.func(args))
    except transport.TransportError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
