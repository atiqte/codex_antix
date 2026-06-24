import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "src" / "betterbird_maildirlite_to_maildirpp.py"
SPEC = importlib.util.spec_from_file_location("converter", SCRIPT)
converter = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = converter
SPEC.loader.exec_module(converter)


class ConverterTests(unittest.TestCase):
    def test_folder_mapping_examples(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "betterbird-maildir"
            target = Path(tmp) / "target"
            folder = root / "Mail" / "mail.tagindustries.com.sg" / "Archives.sbd" / "2026"
            folder.mkdir(parents=True)
            name = converter.source_folder_to_maildirpp_name(root, folder)
            self.assertEqual(name, ".mail_tagindustries_com_sg.Archives.2026")
            mappings = converter.build_folder_mappings(root, target, [folder])
            self.assertEqual(mappings[folder].target_folder, target / ".mail_tagindustries_com_sg.Archives.2026")

    def test_sanitizes_local_folder_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "betterbird-maildir"
            folder = root / "Mail" / "Local_Folders" / "Unsent Messages"
            folder.mkdir(parents=True)
            self.assertEqual(
                converter.source_folder_to_maildirpp_name(root, folder),
                ".Local_Folders.Unsent_Messages",
            )

    @unittest.skipIf(os.name == "nt", "Maildir :2, filenames are not supported on Windows test filesystems")
    def test_copy_preserves_bytes_and_cur_flags(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            source = base / "betterbird-maildir"
            folder = source / "Mail" / "Local_Folders" / "January2026"
            cur = folder / "cur"
            cur.mkdir(parents=True)
            (source / "prefs.js").write_text("// test\n", encoding="utf-8")
            (source / "Mail").mkdir(exist_ok=True)
            raw = b"Message-ID: <a@example.test>\nSubject: Test\n\n<html>Body</html>\n"
            (cur / "message-one").write_bytes(raw)
            target = base / "target"
            log_dir = base / "logs"
            settings = converter.Settings(
                source=source.resolve(),
                target=target.resolve(),
                log_dir=log_dir.resolve(),
                state_path=(target / ".conversion-state.sqlite").resolve(),
                mode="copy",
                resume=True,
                verify_hash=True,
                allow_unmarked_source=False,
            )
            self.assertEqual(converter.run_conversion(settings), 0)
            copied = list((target / ".Local_Folders.January2026" / "cur").iterdir())
            self.assertEqual(len(copied), 1)
            self.assertTrue(copied[0].name.endswith(":2,S"))
            self.assertEqual(copied[0].read_bytes(), raw)


if __name__ == "__main__":
    unittest.main()
