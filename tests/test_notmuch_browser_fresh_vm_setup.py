import os
from pathlib import Path
import stat
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "notmuch_browser_fresh_vm_setup.sh"
ARCHIVE_SHA = "23292983c9ffb3590197a534aeddd03590a2b8d9f913732573fa1637b71045fe"
INVENTORY_SHA = "97332ffac27c85372d91486ceeb8d49dde2cc036d6b0d889cd73243b1e06067d"


class FreshVMSetupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.mail = self.root / "mail"
        self.bin = self.root / "mock-bin"
        self.state = self.mail / "state"
        self.logs = self.mail / "logs"
        self.archive = self.mail / "Mailstore" / "evolution" / "local-maildir"
        self.manifest = self.mail / "staging" / "manifest.json"
        self.config = self.home / ".config" / "notmuch" / "default" / "config"
        self.install_bin = self.home / ".local" / "bin"
        self.usersv = self.home / ".runit" / "usersv"
        self.services = self.home / ".runit" / "service"
        self.delta = (
            self.mail
            / "Mailstore"
            / "evolution"
            / "betterbird-delta-maildirpp-20260704"
        )
        self.provider_test = (
            self.mail / "Mailstore" / "mbsync" / "provider-inbox-test"
        )
        self.provider_live = self.mail / "Mailstore" / "mbsync" / "provider-live"
        self.provider_archive = (
            self.mail / "Mailstore" / "evolution" / "provider-live-archive"
        )
        self.test_maildir = (
            self.mail / "Mailstore" / "evolution" / "test-maildir"
        )
        for directory in (
            self.home,
            self.mail,
            self.bin,
            self.state,
            self.logs,
            self.archive / "cur",
            self.archive / "new",
            self.archive / "tmp",
            self.manifest.parent,
            self.config.parent,
            self.install_bin,
            self.usersv,
            self.services,
        ):
            directory.mkdir(parents=True, exist_ok=True)
        for maildir in (
            self.delta,
            self.provider_test,
            self.provider_live,
            self.provider_archive,
            self.test_maildir,
        ):
            for directory in ("cur", "new", "tmp"):
                (maildir / directory).mkdir(parents=True, exist_ok=True)
        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "PATH": f"{self.bin}:/usr/bin:/bin",
                "NOTMUCH_FRESH_REPO_ROOT": str(ROOT),
                "NOTMUCH_FRESH_MAIL_ROOT": str(self.mail),
                "NOTMUCH_FRESH_MAILSTORE": str(self.mail / "Mailstore"),
                "NOTMUCH_FRESH_ARCHIVE_DEST": str(self.archive),
                "NOTMUCH_FRESH_ARCHIVE_MANIFEST": str(self.manifest),
                "NOTMUCH_FRESH_STATE_DIR": str(self.state),
                "NOTMUCH_FRESH_LOG_DIR": str(self.logs),
                "NOTMUCH_FRESH_DB_PATH": str(self.mail / "SearchIndex"),
                "NOTMUCH_FRESH_CONFIG": str(self.config),
                "NOTMUCH_FRESH_BIN_DIR": str(self.install_bin),
                "NOTMUCH_FRESH_USER_SERVICE_ROOT": str(self.usersv),
                "NOTMUCH_FRESH_ACTIVE_SERVICE_ROOT": str(self.services),
                "NOTMUCH_FRESH_MBSYNC_CONFIG": str(self.home / ".config" / "isyncrc"),
                "NOTMUCH_FRESH_MBSYNC_CONTROL": str(self.install_bin / "mbsync-provider-live-control"),
                "NOTMUCH_FRESH_BROWSER_CONTROL": str(self.install_bin / "notmuch-browser-control"),
                "NOTMUCH_FRESH_INDEX_CONTROL": str(self.install_bin / "notmuch-browser-index-control"),
                "NOTMUCH_FRESH_RUNIT_SETUP": str(self.install_bin / "notmuch-browser-runit-setup"),
                "NOTMUCH_FRESH_TEST_MODE": "1",
                "NOTMUCH_FRESH_TEST_CUR": "2",
                "NOTMUCH_FRESH_TEST_NEW": "0",
                "NOTMUCH_FRESH_TEST_TMP": "0",
                "NOTMUCH_FRESH_TEST_METADATA": "1",
                "NOTMUCH_FRESH_TEST_BYTES": "12",
                "NOTMUCH_FRESH_TEST_DELTA_CUR": "0",
                "NOTMUCH_FRESH_TEST_MAILDIR_MESSAGES": "0",
                "NOTMUCH_FRESH_MIN_FREE_KIB": "100",
                "MOCK_MAIL_ROOT": str(self.mail),
                "MOCK_ARCHIVE_DEST": str(self.archive),
                "MOCK_DB_PATH": str(self.mail / "SearchIndex"),
                "MOCK_CONFIG": str(self.config),
                "MOCK_CONTROL_LOG": str(self.root / "control.log"),
            }
        )
        self.write_executable(
            "findmnt",
            "#!/bin/sh\nprintf '%s\\n' \"${MOCK_FSTYPE:-xfs}\"\n",
        )
        self.write_executable(
            "df",
            textwrap.dedent(
                """\
                #!/bin/sh
                printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'
                printf 'mock 300000000 1 %s 1%% %s\n' "${MOCK_FREE_KIB:-200000000}" "$MOCK_MAIL_ROOT"
                """
            ),
        )
        self.write_executable(
            "go",
            "#!/bin/sh\nprintf '%s\\n' 'go version go1.26.5 linux/amd64'\n",
        )
        self.write_executable(
            "bun",
            "#!/bin/sh\nprintf '%s\\n' '1.3.14'\n",
        )

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_executable(self, name: str, content: str, directory: Path | None = None) -> Path:
        path = (directory or self.bin) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return path

    def run_helper(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(HELPER), *args],
            text=True,
            capture_output=True,
            check=False,
            env=env or self.env,
        )

    def make_package_tools_ready(self) -> None:
        for name in ("sudo", "git", "curl", "rsync", "mbsync", "sv", "svlogd", "ssh", "ss", "unzip", "tar", "sha256sum"):
            if not (self.bin / name).exists():
                self.write_executable(name, "#!/bin/sh\nexit 0\n")

    def make_mbsync_ready(self) -> None:
        config = Path(self.env["NOTMUCH_FRESH_MBSYNC_CONFIG"])
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text("mock\n", encoding="utf-8")
        (self.mail / "Mailstore" / "mbsync" / "provider-live").mkdir(
            parents=True, exist_ok=True
        )
        self.write_executable(
            "mbsync-provider-live-control",
            "#!/bin/sh\nprintf '%s\\n' 'loop=running' 'paused=no'\n",
            self.install_bin,
        )

    def write_archive_marker(self) -> None:
        self.state.mkdir(parents=True, exist_ok=True)
        (self.state / "archive-restored.env").write_text(
            f"archive_sha256={ARCHIVE_SHA}\n"
            f"inventory_sha256={INVENTORY_SHA}\n"
            "archive_cur=2\n",
            encoding="utf-8",
        )

    def write_notmuch_mock(self, ignore_local: bool = False, fail_new: bool = False) -> None:
        ignore = (
            "local-maildir"
            if ignore_local
            else "betterbird-post-main-archive-maildirpp-20260704-205827"
        )
        fail = "1" if fail_new else "0"
        self.write_executable(
            "notmuch",
            textwrap.dedent(
                f"""\
                #!/bin/sh
                for arg in "$@"; do
                  [ "$arg" = "new" ] && {{
                    [ "{fail}" = 1 ] && {{ echo simulated-index-failure; exit 9; }}
                    echo "Processed 2 files"
                    exit 0
                  }}
                  [ "$arg" = "dump" ] && exit 0
                  [ "$arg" = "count" ] && {{
                    case " $* " in *" --output=files "*) echo 2;; *) echo 2;; esac
                    exit 0
                  }}
                  [ "$arg" = "search" ] && {{
                    printf '%s\\n' "$MOCK_ARCHIVE_DEST/cur/message-1" "$MOCK_ARCHIVE_DEST/cur/message-2"
                    exit 0
                  }}
                done
                case " $* " in
                  *" config get database.path "*) printf '%s\\n' "$MOCK_DB_PATH";;
                  *" config get database.mail_root "*) printf '%s\\n' "$MOCK_MAIL_ROOT/Mailstore";;
                  *" config get maildir.synchronize_flags "*) echo false;;
                  *" config get index.decrypt "*) echo false;;
                  *" config get new.ignore "*) printf '%s\\n' '{ignore}';;
                  *" config set "*) echo mock-setting >> "$MOCK_CONFIG"; exit 0;;
                  *) exit 0;;
                esac
                """
            ),
        )

    def test_next_stops_at_manual_xfs_gate(self) -> None:
        env = self.env.copy()
        env["MOCK_FSTYPE"] = "ext4"
        result = self.run_helper("next", env=env)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("next_stage=mail-disk", result.stdout)
        self.assertIn("never formats disks", self.run_helper("help").stdout)

    def test_next_progresses_to_archive_gate(self) -> None:
        self.make_package_tools_ready()
        self.make_mbsync_ready()
        result = self.run_helper("next")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("next_stage=archive", result.stdout)
        self.assertIn("acknowledge archives-restored", result.stdout)

    def test_mbsync_readiness_requires_running_unpaused_loop(self) -> None:
        self.make_package_tools_ready()
        self.make_mbsync_ready()
        self.write_executable(
            "mbsync-provider-live-control",
            "#!/bin/sh\nprintf '%s\\n' 'loop=stopped' 'paused=yes'\n",
            self.install_bin,
        )
        result = self.run_helper("next")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("next_stage=mbsync", result.stdout)

    def test_archive_acknowledgement_records_exact_verified_gate(self) -> None:
        self.manifest.write_text("{}\n", encoding="utf-8")
        self.write_executable(
            "python3",
            textwrap.dedent(
                f"""\
                #!/bin/sh
                if [ "$1" = "-" ]; then
                  case "$3" in
                    archive.sha256) echo {ARCHIVE_SHA};;
                    inventory.sha256) echo {INVENTORY_SHA};;
                  esac
                  exit 0
                fi
                case " $* " in
                  *" inspect "*)
                    printf '%s\\n' mode=inspect cur_files=2 new_files=0 tmp_files=0 metadata_files=1 bytes_regular=12
                    ;;
                  *) echo status=ok;;
                esac
                """
            ),
        )
        result = self.run_helper("acknowledge", "archives-restored")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        marker = (self.state / "archive-restored.env").read_text(encoding="utf-8")
        self.assertIn(f"archive_sha256={ARCHIVE_SHA}", marker)
        self.assertIn("archive_cur=2", marker)
        self.assertIn("status=archive_restore_acknowledged", result.stdout)

    def prepare_initial_index(self, fail_new: bool = False) -> None:
        self.make_package_tools_ready()
        self.make_mbsync_ready()
        self.write_archive_marker()
        self.config.write_text("mock\n", encoding="utf-8")
        (self.archive / "cur" / "message-1").write_text("one", encoding="utf-8")
        (self.archive / "cur" / "message-2").write_text("two", encoding="utf-8")
        self.write_notmuch_mock(fail_new=fail_new)

    def test_local_maildir_ignore_blocks_configuration_readiness(self) -> None:
        self.make_package_tools_ready()
        self.make_mbsync_ready()
        self.write_archive_marker()
        self.config.write_text("mock\n", encoding="utf-8")
        self.write_notmuch_mock(ignore_local=True)
        result = self.run_helper("next")
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("next_stage=notmuch-config", result.stdout)

    def test_configure_notmuch_enables_historical_scope(self) -> None:
        self.make_package_tools_ready()
        self.make_mbsync_ready()
        self.write_archive_marker()
        self.write_notmuch_mock()
        result = self.run_helper(
            "configure-notmuch", "Example User", "example@example.com"
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("status=notmuch_configured", result.stdout)
        self.assertIn("local_maildir_indexing=enabled", result.stdout)
        self.assertTrue(self.config.exists())
        self.assertEqual(0o600, stat.S_IMODE(self.config.stat().st_mode))

    def test_initial_index_requires_free_space(self) -> None:
        self.prepare_initial_index()
        env = self.env.copy()
        env["MOCK_FREE_KIB"] = "99"
        result = self.run_helper("initial-index", env=env)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("at least 100 KiB is required", result.stdout)
        self.assertFalse((self.state / "initial-index.env").exists())

    def test_initial_index_failure_is_resumable_and_keeps_log(self) -> None:
        self.prepare_initial_index(fail_new=True)
        result = self.run_helper("initial-index")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("simulated-index-failure", result.stdout)
        self.assertIn("fix the error and rerun initial-index", result.stdout)
        self.assertFalse((self.state / "initial-index.env").exists())
        self.assertEqual(1, len(list(self.logs.glob("initial-notmuch-new-*.log"))))

    def test_initial_index_failure_restores_preexisting_background_loops(self) -> None:
        self.prepare_initial_index(fail_new=True)
        control = textwrap.dedent(
            """\
            #!/bin/sh
            case "${1:-status}" in
              status) printf '%s\n' 'loop=running' 'paused=no';;
              *) printf '%s\n' "$1" >> "$MOCK_CONTROL_LOG";;
            esac
            """
        )
        self.write_executable(
            "mbsync-provider-live-control", control, self.install_bin
        )
        self.write_executable(
            "notmuch-browser-index-control", control, self.install_bin
        )
        result = self.run_helper("initial-index")
        self.assertNotEqual(0, result.returncode)
        actions = Path(self.env["MOCK_CONTROL_LOG"]).read_text(
            encoding="utf-8"
        ).splitlines()
        self.assertEqual(
            ["pause", "stop-loop", "stop", "start", "start-loop", "resume"],
            actions,
        )

    def test_initial_index_records_exact_path_parity(self) -> None:
        self.prepare_initial_index()
        result = self.run_helper("initial-index")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("archive_path_parity=pass", result.stdout)
        marker = (self.state / "initial-index.env").read_text(encoding="utf-8")
        self.assertIn("archive_indexed_files=2", marker)
        self.assertIn("archive_paths_sha256=", marker)
        self.assertIn("betterbird_delta_indexed_files=0", marker)
        self.assertIn("provider_inbox_test_indexed_files=0", marker)
        self.assertIn("provider_live_indexed_files=0", marker)
        self.assertIn("provider_live_archive_indexed_files=0", marker)
        self.assertIn("test_maildir_indexed_files=0", marker)
        self.assertIn("approved_source_path_parity=pass", result.stdout)

    def test_guided_install_blocks_until_recovery_set_is_release_pinned(self) -> None:
        recovery = self.root / "recovery"
        recovery.mkdir()
        (recovery / "recovery-set.env").write_text(
            "recovery_id=notmuch-browser-recovery-v1\n", encoding="ascii"
        )
        recovery_helper = self.write_executable(
            "recovery-helper",
            "#!/bin/sh\nprintf '%s\\n' status=recovery_set_verified\n",
        )
        env = self.env.copy()
        env["NOTMUCH_FRESH_RECOVERY_HELPER"] = str(recovery_helper)
        result = self.run_helper(
            "guided-install",
            "--release",
            "notmuch-browser-antix-v1.0.0",
            "--recovery-root",
            str(recovery),
            env=env,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("does not yet pin a pilot-verified recovery set", result.stdout)

    def test_guided_bootstrap_never_creates_release_state_before_xfs_mount(self) -> None:
        env = self.env.copy()
        env["NOTMUCH_FRESH_TEST_MODE"] = "0"
        env["MOCK_FSTYPE"] = "ext4"
        result = self.run_helper(
            "guided-install",
            "--release",
            "notmuch-browser-antix-v1.0.0-rc1",
            "--recovery-root",
            str(self.root / "recovery"),
            env=env,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("must already be a dedicated XFS mount", result.stdout)
        self.assertFalse((self.state / "releases").exists())

    def test_deterministic_test_fixture_is_complete_and_idempotent(self) -> None:
        env = self.env.copy()
        env["NOTMUCH_FRESH_TEST_MAILDIR_MESSAGES"] = "4"
        result = self.run_helper("_test-create-fixture", env=env)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("test_maildir=created_and_verified", result.stdout)

        fixture_names = sorted(path.name for path in (self.test_maildir / "cur").iterdir())
        self.assertEqual(
            ["01-plain", "02-addresses", "03-html-images", "04-attachment"],
            fixture_names,
        )
        addresses = (self.test_maildir / "cur" / "02-addresses").read_text(
            encoding="utf-8"
        )
        for header in ("From:", "To:", "Cc:", "Bcc:"):
            self.assertIn(header, addresses)
        attachment = (self.test_maildir / "cur" / "04-attachment").read_text(
            encoding="utf-8"
        )
        self.assertIn('filename="fixture.txt"', attachment)

        rerun = self.run_helper("_test-create-fixture", env=env)
        self.assertEqual(0, rerun.returncode, rerun.stdout + rerun.stderr)
        self.assertIn("test_maildir=already_ready", rerun.stdout)

    def test_interrupted_package_restore_resumes_only_with_matching_marker(self) -> None:
        self.manifest.write_text("{}\n", encoding="utf-8")
        attempted = self.root / "restore-attempted"
        complete = self.root / "restore-complete"
        arguments = self.root / "restore-arguments.log"
        restore_dest = self.root / "restore-dest"
        self.write_executable(
            "python3",
            textwrap.dedent(
                """\
                #!/bin/sh
                printf '%s\n' "$*" >> "$MOCK_RESTORE_ARGUMENTS"
                case " $* " in
                  *" verify-tree "*)
                    [ -f "$MOCK_RESTORE_COMPLETE" ] && {
                      printf '%s\n' status=ok
                      exit 0
                    }
                    exit 2
                    ;;
                  *" unpack "*)
                    if [ ! -f "$MOCK_RESTORE_ATTEMPTED" ]; then
                      : > "$MOCK_RESTORE_ATTEMPTED"
                      mkdir -p "$MOCK_ARCHIVE_DEST/cur"
                      : > "$MOCK_ARCHIVE_DEST/cur/partial"
                      exit 9
                    fi
                    : > "$MOCK_RESTORE_COMPLETE"
                    printf '%s\n' status=ok
                    exit 0
                    ;;
                esac
                exit 2
                """
            ),
        )
        env = self.env.copy()
        env.update(
            {
                "MOCK_RESTORE_ATTEMPTED": str(attempted),
                "MOCK_RESTORE_COMPLETE": str(complete),
                "MOCK_RESTORE_ARGUMENTS": str(arguments),
                "MOCK_ARCHIVE_DEST": str(restore_dest),
            }
        )

        first = self.run_helper(
            "_test-restore-package",
            str(self.manifest),
            str(restore_dest),
            "historical-test",
            env=env,
        )
        self.assertEqual(9, first.returncode, first.stdout + first.stderr)
        marker = self.state / "restore-historical-test.env"
        self.assertTrue(marker.is_file())

        second = self.run_helper(
            "_test-restore-package",
            str(self.manifest),
            str(restore_dest),
            "historical-test",
            env=env,
        )
        self.assertEqual(0, second.returncode, second.stdout + second.stderr)
        self.assertIn("historical-test=restored_and_verified", second.stdout)
        self.assertFalse(marker.exists())
        self.assertIn(
            "--allow-non-empty-dest", arguments.read_text(encoding="utf-8")
        )

    def test_help_exposes_resumable_release_interfaces(self) -> None:
        result = self.run_helper("help")
        self.assertEqual(0, result.returncode)
        for phrase in (
            "guided-install --release TAG --recovery-root ABSOLUTE_PATH",
            "validate --full",
            "validate --post-reboot",
            "prove-new-mail-indexing",
            "support-report",
            "update --release TAG",
        ):
            self.assertIn(phrase, result.stdout)


if __name__ == "__main__":
    unittest.main()
