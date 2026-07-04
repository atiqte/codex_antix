import importlib.util
import os
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "src" / "betterbird_post_archive_delta.py"
SPEC = importlib.util.spec_from_file_location("post_delta", SCRIPT)
post_delta = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = post_delta
SPEC.loader.exec_module(post_delta)


class BetterbirdPostArchiveDeltaTests(unittest.TestCase):
    def test_baseline_excludes_original_messages(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_source(base / "betterbird-maildir")
            msg = write_message(source, "Mail/account/Inbox/cur/msg1.eml", b"Message-ID: <1>\n\none\n")
            state = create_state(base / "state.sqlite", [(msg, source, sha(msg))])

            selection = post_delta.select_post_archive_candidates(
                source, state, expected_baseline_rows=1, max_candidates=10
            )

            self.assertEqual(selection.baseline_rows, 1)
            self.assertEqual(len(selection.selected), 0)
            self.assertEqual(selection.excluded_exact, 1)

    def test_dynamic_selection_accepts_249_messages(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_source(base / "betterbird-maildir")
            baseline = write_message(source, "Mail/account/Inbox/cur/baseline.eml", b"Message-ID: <base>\n\nbase\n")
            selected_paths = [
                write_message(source, f"Mail/account/Inbox/cur/new-{index:03d}.eml", f"Subject: {index}\n\n{index}\n".encode())
                for index in range(249)
            ]
            state = create_state(base / "state.sqlite", [(baseline, source, sha(baseline))])

            selection = post_delta.select_post_archive_candidates(
                source, state, expected_baseline_rows=1, max_candidates=300
            )

            self.assertEqual(len(selection.selected), 249)
            self.assertEqual(selection.states["cur"], 249)
            self.assertEqual({c.path for c in selection.selected}, set(selected_paths))

    def test_relative_path_fallback_excludes_moved_source_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            old_source = create_source(base / "old-root")
            current_source = create_source(base / "new-root")
            old_msg = write_message(old_source, "Mail/account/Inbox/cur/same.eml", b"Message-ID: <same>\n\nsame\n")
            new_msg = write_message(current_source, "Mail/account/Inbox/cur/same.eml", old_msg.read_bytes())
            match_mtime(old_msg, new_msg)
            state = create_state(base / "state.sqlite", [(old_msg, old_source, sha(old_msg))])

            selection = post_delta.select_post_archive_candidates(
                current_source,
                state,
                expected_baseline_rows=1,
                max_candidates=10,
                hash_fallback=False,
            )

            self.assertEqual(len(selection.selected), 0)
            self.assertEqual(selection.excluded_relative, 1)

    def test_hash_fallback_prevents_false_positive(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_source(base / "betterbird-maildir")
            original = write_message(source, "Mail/account/Inbox/cur/original.eml", b"Message-ID: <dup>\n\nsame\n")
            moved = write_message(source, "Mail/account/Archive/cur/moved.eml", original.read_bytes())
            state = create_state(base / "state.sqlite", [(original, source, sha(original))])

            selection = post_delta.select_post_archive_candidates(
                source, state, expected_baseline_rows=1, max_candidates=10
            )

            self.assertEqual(len(selection.selected), 0)
            self.assertEqual(selection.excluded_exact, 1)
            self.assertEqual(selection.excluded_hash, 1)
            self.assertEqual(selection.hash_checked, 1)

    def test_missing_baseline_state_refuses(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = create_source(Path(tmp) / "betterbird-maildir")

            with self.assertRaises(post_delta.DeltaError):
                post_delta.select_post_archive_candidates(source, Path(tmp) / "missing.sqlite")

    def test_large_delta_refuses_without_override(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_source(base / "betterbird-maildir")
            write_message(source, "Mail/account/Inbox/cur/one.eml", b"Subject: one\n\none\n")
            write_message(source, "Mail/account/Inbox/cur/two.eml", b"Subject: two\n\ntwo\n")
            state = create_state(base / "state.sqlite", [])

            with self.assertRaises(post_delta.DeltaError):
                post_delta.select_post_archive_candidates(
                    source, state, expected_baseline_rows=0, max_candidates=1
                )

    def test_stage_preserves_bytes_and_relative_paths_and_skips_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = create_source(base / "betterbird-maildir")
            raw = b"Message-ID: <real>\n\nreal body\n"
            real = write_message(source, "Mail/account/Inbox/cur/real.eml", raw)
            write_message(source, "Mail/account/Inbox/cur/real.eml.msf", b"metadata")
            write_message(source, "Mail/account/Inbox/tmp/temp.eml", b"tmp should not copy")
            state = create_state(base / "state.sqlite", [])
            selection = post_delta.select_post_archive_candidates(
                source, state, expected_baseline_rows=0, max_candidates=10
            )

            staging = post_delta.stage_selection(
                selection,
                base / "work",
                base / "target-prefix",
                "20260704-201618",
            )

            staged = staging / real.relative_to(source)
            self.assertTrue(staged.is_file())
            self.assertEqual(staged.read_bytes(), raw)
            self.assertFalse((staging / "Mail/account/Inbox/cur/real.eml.msf").exists())
            self.assertFalse((staging / "Mail/account/Inbox/tmp/temp.eml").exists())
            self.assertTrue((staging.parent / "selected-files.tsv").is_file())
            self.assertTrue((staging.parent / "summary.tsv").is_file())

    def test_plan_convert_paths_are_deterministic(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            work = base / "work"
            prefix = base / "target"
            target = post_delta.target_for_run(prefix, "run1")
            staging = post_delta.staging_for_run(work, "run1")

            self.assertEqual(target, Path(str(prefix) + "-run1"))
            self.assertEqual(staging, work / "run1" / "staging-betterbird-maildir")


def create_source(root: Path) -> Path:
    (root / "Mail").mkdir(parents=True)
    (root / "prefs.js").write_text("// Betterbird marker\n", encoding="utf-8")
    return root


def write_message(source: Path, rel: str, payload: bytes) -> Path:
    path = source / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return path


def sha(path: Path) -> str:
    return post_delta.sha256_file(path)


def match_mtime(src: Path, dst: Path) -> None:
    st = src.stat()
    os.utime(dst, ns=(st.st_atime_ns, st.st_mtime_ns))


def create_state(path: Path, rows):
    conn = sqlite3.connect(str(path))
    conn.execute(
        """
        CREATE TABLE processed (
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
    for source_path, _source_root, digest in rows:
        st = source_path.stat()
        conn.execute(
            """
            INSERT INTO processed
            (source_path, source_size, source_mtime_ns, source_sha256, target_path, status, message_id, copied_at)
            VALUES (?, ?, ?, ?, ?, 'copied', '', '2026-06-30T05:01:22+00:00')
            """,
            (str(source_path), st.st_size, st.st_mtime_ns, digest, "/target/" + source_path.name),
        )
    conn.commit()
    conn.close()
    return path


if __name__ == "__main__":
    unittest.main()
