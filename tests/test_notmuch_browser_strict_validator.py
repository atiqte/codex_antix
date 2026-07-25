import base64
import html
import importlib.util
import json
from pathlib import Path
import unittest


SCRIPT = (
    Path(__file__).resolve().parents[1]
    / "scripts"
    / "notmuch_browser_strict_validator.py"
)
SPEC = importlib.util.spec_from_file_location("notmuch_browser_strict_validator", SCRIPT)
validator = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(validator)


class StrictValidatorTests(unittest.TestCase):
    def capability_url(self, purpose, duplicate, part):
        payload = {"p": purpose, "d": duplicate, "n": part}
        encoded = base64.urlsafe_b64encode(
            json.dumps(payload, separators=(",", ":")).encode()
        ).decode().rstrip("=")
        return f"http://127.0.0.1:8765/{purpose}?cap={encoded}.signature"

    def test_parse_page_collects_outer_and_srcdoc_urls(self):
        attachment = self.capability_url("attachment", 0, 7)
        inline = self.capability_url("inline-image", 0, 6)
        inner = f'<img src="{inline}"><img src="{inline}">'
        page = (
            f'<a href="{attachment}">download</a>'
            f'<iframe srcdoc="{html.escape(inner, quote=True)}"></iframe>'
        ).encode()

        _, urls, srcdocs = validator.parse_page(page)

        self.assertIn(attachment, urls)
        self.assertEqual(srcdocs, [inner])
        self.assertEqual(
            validator.capability_urls(
                "http://127.0.0.1:8765",
                urls,
                "inline-image",
                0,
                6,
            ),
            [inline],
        )

    def test_attachment_parts_deduplicates_repeated_urls(self):
        part7 = self.capability_url("attachment", 1, 7)
        part8 = self.capability_url("attachment", 1, 8)

        parts = validator.attachment_parts(
            "http://127.0.0.1:8765",
            [part7, part7, part8],
            1,
        )

        self.assertEqual(parts, {7: [part7], 8: [part8]})


if __name__ == "__main__":
    unittest.main()
