import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts" / "notmuch_browser_operator_run.sh"
RECORDER = ROOT / "scripts" / "notmuch_browser_operator_record.sh"


class OperatorEvidenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.operator = self.root / "operator"
        self.evidence = self.root / "evidence"
        self.batch = self.operator / "current.sh"
        self.operator.mkdir()
        self.env = os.environ.copy()
        self.env.update(
            {
                "NOTMUCH_BROWSER_OPERATOR_ROOT": str(self.operator),
                "NOTMUCH_BROWSER_EVIDENCE_ROOT": str(self.evidence),
            }
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_batch(self, content: str) -> subprocess.CompletedProcess[str]:
        self.batch.write_text(content, encoding="utf-8")
        return subprocess.run(
            [str(RUNNER)],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def record(self, result: str = "success") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(RECORDER), "01", "test-gate", result],
            cwd=ROOT,
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_success_records_exact_batch_log_and_manifest(self) -> None:
        run = self.run_batch("#!/bin/bash\nset -e\nprintf 'gate=pass\\n'\n")
        self.assertEqual(0, run.returncode, run.stdout + run.stderr)
        recorded = self.record()
        self.assertEqual(0, recorded.returncode, recorded.stdout + recorded.stderr)

        published_batch = self.evidence / "batches" / "01-test-gate.sh"
        published_log = self.evidence / "logs" / "01-test-gate.log"
        record = self.evidence / "records" / "01-test-gate.env"
        self.assertEqual(self.batch.read_bytes(), published_batch.read_bytes())
        self.assertIn("gate=pass", published_log.read_text(encoding="utf-8"))
        record_text = record.read_text(encoding="utf-8")
        self.assertIn("result=success", record_text)
        self.assertIn("batch_exit=0", record_text)
        self.assertIn("privacy_review=automated_scan_passed_manual_review_required", record_text)

    def test_record_refuses_batch_drift(self) -> None:
        run = self.run_batch("#!/bin/bash\nprintf 'gate=pass\\n'\n")
        self.assertEqual(0, run.returncode, run.stdout + run.stderr)
        self.batch.write_text("#!/bin/bash\nprintf 'changed\\n'\n", encoding="utf-8")
        recorded = self.record()
        self.assertNotEqual(0, recorded.returncode)
        self.assertIn("batch hash drifted", recorded.stderr)
        self.assertFalse(self.evidence.exists())

    def test_record_refuses_credential_shaped_output(self) -> None:
        run = self.run_batch(
            "#!/bin/bash\nprintf '%s\\n' 'password=must-not-be-published'\n"
        )
        self.assertEqual(0, run.returncode, run.stdout + run.stderr)
        recorded = self.record()
        self.assertNotEqual(0, recorded.returncode)
        self.assertIn("privacy scan", recorded.stderr)
        self.assertFalse(self.evidence.exists())


if __name__ == "__main__":
    unittest.main()
