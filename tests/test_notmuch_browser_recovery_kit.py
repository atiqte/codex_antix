import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "notmuch_browser_recovery_kit.sh"
TRANSPORT = ROOT / "src" / "maildirpp_transport.py"


class RecoveryKitTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.historical_source = self.root / "historical-source"
        self.delta_source = self.root / "delta-source"
        self.recovery = self.root / "notmuch-browser-recovery-v1"
        self.recovery.mkdir()
        self.historical_bytes = self.make_maildir(
            self.historical_source, ("historical-one", "historical-two")
        )
        self.delta_bytes = self.make_maildir(self.delta_source, ("delta-one",))
        self.pack(self.historical_source, self.recovery / "historical")
        self.historical_manifest = self.load_manifest(
            self.recovery / "historical" / "manifest.json"
        )
        self.env = os.environ.copy()
        self.env.update(
            {
                "NOTMUCH_RECOVERY_REPO_ROOT": str(ROOT),
                "NOTMUCH_RECOVERY_TEST_MODE": "1",
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_ARCHIVE_SHA256": self.historical_manifest[
                    "archive"
                ]["sha256"],
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_INVENTORY_SHA256": self.historical_manifest[
                    "inventory"
                ]["sha256"],
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_CUR": "2",
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_NEW": "0",
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_TMP": "0",
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_METADATA": "1",
                "NOTMUCH_RECOVERY_TEST_HISTORICAL_BYTES": str(
                    self.historical_bytes
                ),
                "NOTMUCH_RECOVERY_TEST_DELTA_CUR": "1",
                "NOTMUCH_RECOVERY_TEST_DELTA_NEW": "0",
                "NOTMUCH_RECOVERY_TEST_DELTA_TMP": "0",
                "NOTMUCH_RECOVERY_TEST_DELTA_METADATA": "1",
                "NOTMUCH_RECOVERY_TEST_DELTA_BYTES": str(self.delta_bytes),
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def make_maildir(path: Path, names: tuple[str, ...]) -> int:
        for folder in ("cur", "new", "tmp"):
            (path / folder).mkdir(parents=True, exist_ok=True)
        for index, name in enumerate(names, start=1):
            (path / "cur" / name).write_text(
                "Message-ID: <fixture-%d@example.test>\n"
                "From: Fixture <fixture@example.test>\n"
                "To: Reader <reader@example.test>\n"
                "Subject: Recovery fixture %d\n\n"
                "fixture body\n" % (index, index),
                encoding="ascii",
            )
        (path / ".maildirpp-migration.json").write_text(
            '{"fixture":true}\n', encoding="ascii"
        )
        return sum(
            item.stat().st_size
            for item in path.rglob("*")
            if item.is_file()
        )

    @staticmethod
    def load_manifest(path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))

    @staticmethod
    def pack(source: Path, output: Path) -> None:
        result = subprocess.run(
            [
                "python3",
                str(TRANSPORT),
                "pack",
                "--source",
                str(source),
                "--out",
                str(output),
            ],
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(result.stdout + result.stderr)

    def run_helper(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(HELPER), *args],
            text=True,
            capture_output=True,
            check=False,
            env=self.env,
        )

    def create_delta_package(self) -> Path:
        output = self.recovery / "betterbird-delta"
        result = self.run_helper("pack-delta", str(self.delta_source), str(output))
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("status=delta_package_complete", result.stdout)
        self.assertTrue((output / "manifest.json").is_file())
        self.assertEqual([], list(self.recovery.glob("*.incoming-*")))
        return output

    def test_pack_finalize_and_verify_recovery_set(self) -> None:
        self.create_delta_package()
        finalized = self.run_helper("finalize", str(self.recovery))
        self.assertEqual(
            0, finalized.returncode, finalized.stdout + finalized.stderr
        )
        self.assertIn("status=recovery_set_finalized", finalized.stdout)
        set_file = self.recovery / "recovery-set.env"
        self.assertEqual(0o600, set_file.stat().st_mode & 0o777)
        contents = set_file.read_text(encoding="ascii")
        self.assertIn("historical_cur=2\n", contents)
        self.assertIn("delta_cur=1\n", contents)
        self.assertNotIn("@example.test", contents)

        verified = self.run_helper("verify", str(self.recovery))
        self.assertEqual(0, verified.returncode, verified.stdout + verified.stderr)
        self.assertIn("historical_archive=verified", verified.stdout)
        self.assertIn("betterbird_delta=verified", verified.stdout)
        self.assertIn("status=recovery_set_verified", verified.stdout)

    def test_finalize_refuses_wrong_delta_source_inventory(self) -> None:
        self.pack(self.delta_source, self.recovery / "betterbird-delta")
        wrong_env = self.env.copy()
        wrong_env["NOTMUCH_RECOVERY_TEST_DELTA_CUR"] = "2"
        result = subprocess.run(
            ["sh", str(HELPER), "finalize", str(self.recovery)],
            text=True,
            capture_output=True,
            check=False,
            env=wrong_env,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("expected 3", result.stdout)
        self.assertFalse((self.recovery / "recovery-set.env").exists())

    def test_verify_refuses_tampered_top_level_manifest(self) -> None:
        self.create_delta_package()
        finalized = self.run_helper("finalize", str(self.recovery))
        self.assertEqual(0, finalized.returncode, finalized.stdout)
        set_file = self.recovery / "recovery-set.env"
        set_file.write_text(
            set_file.read_text(encoding="ascii").replace(
                "delta_cur=1", "delta_cur=9"
            ),
            encoding="ascii",
        )
        result = self.run_helper("verify", str(self.recovery))
        self.assertNotEqual(0, result.returncode)
        self.assertIn("delta_cur is 9, expected 1", result.stdout)

    def test_verify_refuses_delta_manifest_source_stat_drift(self) -> None:
        delta = self.create_delta_package()
        finalized = self.run_helper("finalize", str(self.recovery))
        self.assertEqual(0, finalized.returncode, finalized.stdout)
        manifest_path = delta / "manifest.json"
        manifest = self.load_manifest(manifest_path)
        manifest["source"]["regular_file_bytes"] += 1
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        result = self.run_helper("verify", str(self.recovery))
        self.assertNotEqual(0, result.returncode)
        self.assertIn("delta source regular bytes", result.stdout)


if __name__ == "__main__":
    unittest.main()
