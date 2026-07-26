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
        expected_commands = sum(
            1 for section in self.generator.SECTIONS if section.get("code")
        )
        self.assertEqual(19, expected_commands)
        self.assertEqual(expected_commands, len(self.parser.targets))
        self.assertEqual(len(self.parser.targets), len(set(self.parser.targets)))
        self.assertEqual(len(self.parser.ids), len(set(self.parser.ids)))
        self.assertEqual(set(self.parser.targets), set(self.parser.codes))
        self.assertTrue(all(self.parser.codes[target].strip() for target in self.parser.targets))
        self.assertIn('document.execCommand("copy")', self.html)

    def test_every_html_command_is_verbatim_in_text_guide(self):
        for target in self.parser.targets:
            self.assertIn(self.parser.codes[target], self.text)

    def test_offline_resources_and_required_fresh_install_contract(self):
        self.assertEqual([], self.parser.resources)
        self.assertNotIn("@import", self.html)
        self.assertNotIn("url(http", self.html)
        required = {
            "go1.26.5",
            "5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053",
            "Bun 1.3.14",
            "Tailwind CSS 4.3.3",
            "HTMX 2.0.10",
            "48,720",
            "62,430,783,277",
            "80 GiB",
            "250 GB",
            "notmuch_browser_fresh_vm_setup.sh",
            "acknowledge archives-restored",
            "initial-index",
            "git pull --ff-only",
            "automatic new-mail indexing",
            "127.0.0.1:8765",
        }
        for identity in required:
            self.assertIn(identity, self.text)
            self.assertIn(identity, self.html)
        self.assertIn("local-maildir is deliberately not in new.ignore", self.text)
        self.assertIn("Do not copy the drifted 48,564-file tree", self.text)
        self.assertIn("does not need to restart.", self.text)
        self.assertIn("provider-inbox-test", self.text)
        self.assertIn("provider-live-archive", self.text)
        self.assertIn("never thread-grouped", self.text)
        self.assertIn("always newest first", self.text)
        self.assertIn("60-119 minutes says 1 hour ago", self.text)
        self.assertIn(
            "new.ignore contains only the unavailable legacy", self.text
        )

    def test_beginner_safety_and_feature_contract(self):
        for phrase in (
            "No prior Linux, Go,",
            "never partitions,",
            "one-step-at-a-time assistant",
            "Stop if clone or checkout fails",
            "signed individual attachments",
            "Save All ZIP",
            "embedded/remote images",
            "read_only=true",
            "mail_mutation=false",
            "reboot recovery works",
        ):
            self.assertIn(phrase, self.text)

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
