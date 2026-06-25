import argparse
import gzip
import hashlib
import importlib.util
import io
import json
import random
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "src" / "betterbird_profile_transport.py"
SPEC = importlib.util.spec_from_file_location("transport", SCRIPT)
transport = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = transport
SPEC.loader.exec_module(transport)


class BetterbirdProfileTransportTests(unittest.TestCase):
    def test_parse_size_examples(self):
        self.assertEqual(transport.parse_size("1"), 1)
        self.assertEqual(transport.parse_size("2KiB"), 2048)
        self.assertEqual(transport.parse_size("3M"), 3 * 1024 * 1024)
        self.assertEqual(transport.parse_size("4GB"), 4 * 1024 * 1024 * 1024)
        with self.assertRaises(argparse.ArgumentTypeError):
            transport.parse_size("bad-size")

    def test_split_archive_creation_with_tiny_parts(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_sample_profile(base / "Betterbird-Email", payload_size=16384)
            out = base / "export"

            manifest = transport.pack_profile(source, out, part_size=512)
            data = json.loads(manifest.read_text(encoding="utf-8"))

            self.assertGreater(len(data["archive"]["parts"]), 1)
            self.assertTrue((out / "inventory.jsonl").is_file())
            summary = transport.verify_archive_from_manifest(manifest)
            self.assertEqual(summary["parts"], len(data["archive"]["parts"]))

    def test_archive_verification_fails_on_corrupted_part(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_sample_profile(base / "Betterbird-Email", payload_size=8192)
            out = base / "export"
            manifest = transport.pack_profile(source, out, part_size=512)
            data = json.loads(manifest.read_text(encoding="utf-8"))
            first_part = out / data["archive"]["parts"][0]["name"]

            with first_part.open("r+b") as f:
                original = f.read(1)
                f.seek(0)
                f.write(b"X" if original != b"X" else b"Y")

            with self.assertRaises(transport.TransportError):
                transport.verify_archive_from_manifest(manifest)

    def test_unpack_rejects_unsafe_tar_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            out = base / "export"
            out.mkdir()
            archive_bytes = make_tar_gz_with_member("../escape.txt", b"escape")
            part = out / "betterbird-profile.tar.gz.part0001"
            part.write_bytes(archive_bytes)
            manifest = write_manifest_for_single_part(out, part, archive_bytes)

            with self.assertRaises(transport.TransportError):
                transport.unpack_manifest(manifest, base / "restore")

    def test_round_trip_restore_preserves_bytes_and_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_sample_profile(base / "Betterbird-Email", payload_size=12288)
            original = (source / "Mail" / "Local Folders" / "cur" / "message-one").read_bytes()
            out = base / "export"
            dest = base / "restore"

            manifest = transport.pack_profile(source, out, part_size=700)
            transport.verify_archive_from_manifest(manifest)
            transport.unpack_manifest(manifest, dest)
            summary = transport.verify_tree_from_manifest(manifest, dest)

            restored = (dest / "Mail" / "Local Folders" / "cur" / "message-one").read_bytes()
            self.assertEqual(restored, original)
            self.assertGreaterEqual(summary["regular_files"], 2)

    def test_refuses_active_profile_lock_marker(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_sample_profile(base / "Betterbird-Email", payload_size=128)
            (source / ".parentlock").write_text("locked\n", encoding="utf-8")

            with self.assertRaises(transport.TransportError):
                transport.pack_profile(source, base / "export", part_size=1024)

    def test_refuses_non_empty_restore_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_sample_profile(base / "Betterbird-Email", payload_size=2048)
            manifest = transport.pack_profile(source, base / "export", part_size=512)
            dest = base / "restore"
            dest.mkdir()
            (dest / "existing.txt").write_text("do not overwrite\n", encoding="utf-8")

            with self.assertRaises(transport.TransportError):
                transport.unpack_manifest(manifest, dest)


def create_sample_profile(root: Path, payload_size: int) -> Path:
    cur = root / "Mail" / "Local Folders" / "cur"
    cur.mkdir(parents=True)
    (root / "prefs.js").write_text('// sample Betterbird profile marker\n', encoding="utf-8")
    rng = random.Random(12345)
    payload = rng.randbytes(payload_size)
    message = b"Message-ID: <sample@example.test>\nSubject: Sample\n\n" + payload
    (cur / "message-one").write_bytes(message)
    (root / "Mail" / "Local Folders" / "new").mkdir(parents=True)
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
    manifest = {
        "format": transport.FORMAT_VERSION,
        "created_at_utc": "2026-06-25T00:00:00+00:00",
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
            "name": transport.ARCHIVE_BASENAME,
            "compression": "gzip",
            "compression_level": 6,
            "part_size": len(archive_bytes),
            "size": len(archive_bytes),
            "sha256": hashlib.sha256(archive_bytes).hexdigest(),
            "parts": [
                {
                    "index": 1,
                    "name": part.name,
                    "size": len(archive_bytes),
                    "sha256": hashlib.sha256(archive_bytes).hexdigest(),
                }
            ],
        },
        "inventory": {
            "name": "inventory.jsonl",
            "size": 0,
            "sha256": hashlib.sha256(b"").hexdigest(),
            "entries": 0,
        },
        "restore": {
            "recommended_dest": transport.DEFAULT_DEST,
            "converter_script": "src/betterbird_maildirlite_to_maildirpp.py",
        },
    }
    (out / "inventory.jsonl").write_bytes(b"")
    manifest_path = out / "manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return manifest_path


if __name__ == "__main__":
    unittest.main()
