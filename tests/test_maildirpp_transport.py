import gzip
import hashlib
import importlib.util
import io
import json
import os
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "src" / "maildirpp_transport.py"
SRC_DIR = SCRIPT.parent
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))
SPEC = importlib.util.spec_from_file_location("maildirpp_transport", SCRIPT)
maildirpp = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = maildirpp
SPEC.loader.exec_module(maildirpp)


class MaildirppTransportTests(unittest.TestCase):
    def tearDown(self):
        maildirpp.restore_transport()

    def test_valid_maildirpp_inspection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = create_maildirpp_tree(Path(tmp) / "archive")
            summary = maildirpp.inspect_maildirpp(root)

            self.assertEqual(summary.maildir_folders, 3)
            self.assertEqual(summary.dot_folders, 2)
            self.assertEqual(summary.cur_files, 2)
            self.assertEqual(summary.new_files, 1)
            self.assertEqual(summary.tmp_files, 0)

    def test_missing_state_dir_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = create_maildirpp_tree(Path(tmp) / "archive")
            (root / ".Archive" / "tmp").rmdir()

            with self.assertRaises(maildirpp.MaildirppError):
                maildirpp.inspect_maildirpp(root)

    @unittest.skipIf(os.name == "nt", "Directory symlink creation may require privileges on Windows")
    def test_symlink_state_dir_rejected_even_with_symlink_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = create_maildirpp_tree(Path(tmp) / "archive")
            real_cur = root / "real-cur"
            real_cur.mkdir()
            for child in (root / ".Archive" / "cur").iterdir():
                child.unlink()
            (root / ".Archive" / "cur").rmdir()
            os.symlink(real_cur, root / ".Archive" / "cur", target_is_directory=True)

            with self.assertRaises(maildirpp.MaildirppError):
                maildirpp.inspect_maildirpp(root, allow_symlinks=True)

    def test_non_empty_tmp_rejected_by_default(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = create_maildirpp_tree(Path(tmp) / "archive")
            (root / ".Archive" / "tmp" / "partial").write_bytes(b"partial")

            with self.assertRaises(maildirpp.MaildirppError):
                maildirpp.inspect_maildirpp(root)

            summary = maildirpp.inspect_maildirpp(root, allow_tmp_files=True)
            self.assertEqual(summary.tmp_files, 1)

    def test_split_archive_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_maildirpp_tree(base / "archive", payload_size=8192)
            out = base / "export"
            dest = base / "restore"

            maildirpp.configure_transport()
            manifest = maildirpp.transport.pack_profile(source, out, part_size=512, allow_active_profile=True)
            manifest_data = json.loads(manifest.read_text(encoding="utf-8"))

            self.assertEqual(manifest_data["format"], maildirpp.FORMAT_VERSION)
            self.assertGreater(len(manifest_data["archive"]["parts"]), 1)
            maildirpp.transport.verify_archive_from_manifest(manifest)
            maildirpp.transport.unpack_manifest(manifest, dest)
            result = maildirpp.transport.verify_tree_from_manifest(manifest, dest)
            inspected = maildirpp.inspect_maildirpp(dest)

            self.assertEqual(result["regular_files"], 3)
            self.assertEqual(inspected.cur_files, 2)
            self.assertEqual(inspected.new_files, 1)

    def test_corrupted_part_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_maildirpp_tree(base / "archive", payload_size=4096)
            out = base / "export"

            maildirpp.configure_transport()
            manifest = maildirpp.transport.pack_profile(source, out, part_size=512, allow_active_profile=True)
            manifest_data = json.loads(manifest.read_text(encoding="utf-8"))
            first_part = out / manifest_data["archive"]["parts"][0]["name"]
            with first_part.open("r+b") as f:
                original = f.read(1)
                f.seek(0)
                f.write(b"X" if original != b"X" else b"Y")

            with self.assertRaises(maildirpp.transport.TransportError):
                maildirpp.transport.verify_archive_from_manifest(manifest)

    def test_restored_tree_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_maildirpp_tree(base / "archive", payload_size=1024)
            out = base / "export"
            dest = base / "restore"

            maildirpp.configure_transport()
            manifest = maildirpp.transport.pack_profile(source, out, part_size=512, allow_active_profile=True)
            maildirpp.transport.unpack_manifest(manifest, dest)
            (dest / ".Archive" / "cur" / "archive-message").write_bytes(b"changed")

            with self.assertRaises(maildirpp.transport.TransportError):
                maildirpp.transport.verify_tree_from_manifest(manifest, dest)

    def test_unsafe_tar_path_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            out = base / "export"
            out.mkdir()
            archive_bytes = make_tar_gz_with_member("../escape.txt", b"escape")
            part = out / "maildirpp-archive.tar.gz.part0001"
            part.write_bytes(archive_bytes)
            manifest = write_manifest_for_single_part(out, part, archive_bytes)

            maildirpp.configure_transport()
            with self.assertRaises(maildirpp.transport.TransportError):
                maildirpp.transport.unpack_manifest(manifest, base / "restore")

    def test_non_empty_destination_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_maildirpp_tree(base / "archive", payload_size=512)
            out = base / "export"
            dest = base / "restore"
            dest.mkdir()
            (dest / "existing.txt").write_text("existing\n", encoding="utf-8")

            maildirpp.configure_transport()
            manifest = maildirpp.transport.pack_profile(source, out, part_size=512, allow_active_profile=True)

            with self.assertRaises(maildirpp.transport.TransportError):
                maildirpp.transport.unpack_manifest(manifest, dest)


def create_maildirpp_tree(root: Path, payload_size: int = 128) -> Path:
    for folder in (root, root / ".Archive", root / ".mail_tagindustries_com_sg.Inbox"):
        for state in ("cur", "new", "tmp"):
            (folder / state).mkdir(parents=True)

    payload = b"x" * payload_size
    (root / "cur" / "root-message").write_bytes(b"Message-ID: <root@example.test>\n\n" + payload)
    (root / ".Archive" / "cur" / "archive-message").write_bytes(b"Message-ID: <archive@example.test>\n\n" + payload)
    (root / ".mail_tagindustries_com_sg.Inbox" / "new" / "inbox-message").write_bytes(
        b"Message-ID: <inbox@example.test>\n\n" + payload
    )
    return root


def make_tar_gz_with_member(name: str, payload: bytes) -> bytes:
    raw = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w|") as tar:
            info = tarfile.TarInfo(name)
            info.size = len(payload)
            info.mode = 0o600
            tar.addfile(info, io.BytesIO(payload))
    return raw.getvalue()


def write_manifest_for_single_part(out: Path, part: Path, archive_bytes: bytes) -> Path:
    digest = hashlib.sha256(archive_bytes).hexdigest()
    manifest = {
        "format": maildirpp.FORMAT_VERSION,
        "created_at_utc": "2026-07-01T00:00:00+00:00",
        "source": {
            "path": "test",
            "root_name": "test",
            "entries": 0,
            "regular_files": 0,
            "directories": 0,
            "symlinks": 0,
            "regular_file_bytes": 0,
        },
        "archive": {
            "name": maildirpp.ARCHIVE_BASENAME,
            "compression": "gzip",
            "compression_level": 6,
            "part_size": len(archive_bytes),
            "size": len(archive_bytes),
            "sha256": digest,
            "parts": [{"index": 1, "name": part.name, "size": len(archive_bytes), "sha256": digest}],
        },
        "inventory": {
            "name": "inventory.jsonl",
            "size": 0,
            "sha256": hashlib.sha256(b"").hexdigest(),
            "entries": 0,
        },
        "restore": {
            "recommended_dest": maildirpp.DEFAULT_DEST,
            "converter_script": "",
        },
    }
    (out / "inventory.jsonl").write_bytes(b"")
    manifest_path = out / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return manifest_path


if __name__ == "__main__":
    unittest.main()
