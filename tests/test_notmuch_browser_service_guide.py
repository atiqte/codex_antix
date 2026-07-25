import importlib.util
import subprocess
import unittest
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / "scripts" / "generate_notmuch_browser_service_guide.py"
HTML_GUIDE = ROOT / "docs" / "NOTMUCH_GO_BROWSER_SERVICE_GUIDE.html"
TEXT_GUIDE = ROOT / "docs" / "NOTMUCH_GO_BROWSER_SERVICE_GUIDE.txt"


def load_generator():
    spec = importlib.util.spec_from_file_location("notmuch_guide_generator", GENERATOR)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class GuideParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = []
        self.targets = []
        self.resources = []
        self.code_stack = []
        self.codes = {}

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if "id" in values:
            self.ids.append(values["id"])
        if "data-copy-target" in values:
            self.targets.append(values["data-copy-target"])
        for key in ("src", "href"):
            if key in values and not values[key].startswith("#"):
                self.resources.append(values[key])
        if tag == "pre":
            self.code_stack.append([values.get("id"), []])

    def handle_data(self, data):
        if self.code_stack:
            self.code_stack[-1][1].append(data)

    def handle_endtag(self, tag):
        if tag == "pre":
            target, chunks = self.code_stack.pop()
            self.codes[target] = "".join(chunks)


class NotmuchBrowserServiceGuideTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.generator = load_generator()
        cls.html = HTML_GUIDE.read_text(encoding="ascii")
        cls.text = TEXT_GUIDE.read_text(encoding="ascii")
        cls.parser = GuideParser()
        cls.parser.feed(cls.html)

    def test_generated_files_are_current(self):
        self.assertEqual(self.generator.render_html(), self.html)
        self.assertEqual(self.generator.render_text(), self.text)

    def test_copy_targets_are_unique_complete_and_nonempty(self):
        self.assertEqual(11, len(self.parser.targets))
        self.assertEqual(len(self.parser.targets), len(set(self.parser.targets)))
        self.assertEqual(len(self.parser.ids), len(set(self.parser.ids)))
        self.assertEqual(set(self.parser.targets), set(self.parser.codes))
        self.assertTrue(all(self.parser.codes[target].strip() for target in self.parser.targets))
        self.assertIn('document.execCommand("copy")', self.html)

    def test_every_html_command_is_verbatim_in_text_guide(self):
        for target in self.parser.targets:
            self.assertIn(self.parser.codes[target], self.text)

    def test_offline_resources_and_required_identities(self):
        self.assertEqual([], self.parser.resources)
        self.assertNotIn("@import", self.html)
        self.assertNotIn("url(http", self.html)
        required = {
            "a1728127940f0824fb91d3dd97abe636be47690e",
            "5e58f63b9ef3eca0b1e8fc2b8b9013f1985aeaae7817424848ae1ed5ccd361a1",
            "c7d14e0ee792595cd168a131cb05307214ae1129dc449f982fa48d30aa5bfed9",
            "4b8231a2c886dfb1247d4dfa6b3de043e67d230e4fad1bc202b7452936ca04a8",
            "1ddf93c9c5f9943bcc9b4f744f3e835e6c12f0df83a8a467ac061d2b38f6b007",
            "598762b0f98147460cff3e937b69a47b7aa531e9e4e80807c4f75e540fdc0c77",
            "fe18ec8f19796607d7d45c621c2e6e92e5608b0a0086aaab82b3871d913e8202",
            "4af19fb2dca62622be0b3d6b79e233b698acc0acc53c7d05e1fe32b145182325",
        }
        for identity in required:
            self.assertIn(identity, self.text)
            self.assertIn(identity, self.html)
        for stale in (
            "50e6b1adbcf32201496f6d6f5a3d53c060d0c39e1831ca1b5ecac3d48838f37e",
            "f56332f7746ba0a621da784135cdb1379a8e3f1310e7bfd2de9ed00ac2af5f9e",
        ):
            self.assertNotIn(stale, self.text)
            self.assertNotIn(stale, self.html)

    def test_posix_command_blocks_parse(self):
        shell_sections = [
            section["code"]
            for section in self.generator.SECTIONS
            if section.get("language") == "sh"
        ]
        for command in shell_sections:
            result = subprocess.run(
                ["sh", "-n"],
                input=command,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, result.returncode, result.stderr)


if __name__ == "__main__":
    unittest.main()
