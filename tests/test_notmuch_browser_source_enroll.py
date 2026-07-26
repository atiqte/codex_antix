import os
from pathlib import Path
import stat
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "notmuch_browser_source_enroll.sh"


class SourceEnrollmentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.mail = self.root / "mail"
        self.mailstore = self.mail / "Mailstore"
        self.config = self.home / ".config" / "notmuch" / "default" / "config"
        self.db = self.mail / "SearchIndex" / "notmuch" / "default"
        self.state = self.mail / "state"
        self.logs = self.mail / "logs"
        self.backups = self.mail / "backups"
        self.mock_bin = self.root / "mock-bin"
        self.mock_state = self.root / "mock-state"
        self.control_log = self.root / "controls.log"
        for directory in (
            self.home,
            self.config.parent,
            self.db,
            self.state,
            self.logs,
            self.backups,
            self.mock_bin,
            self.mock_state,
        ):
            directory.mkdir(parents=True, exist_ok=True)
        self.config.write_text("mock-config\n", encoding="utf-8")
        (self.db / "database").write_text("baseline-db\n", encoding="utf-8")

        self.sources = {
            "evolution/local-maildir": 2,
            "evolution/betterbird-delta-maildirpp-20260704": 1,
            "mbsync/provider-inbox-test": 1,
            "evolution/test-maildir": 1,
            "evolution/provider-live-archive": 0,
            "mbsync/provider-live": 1,
        }
        for relative, count in self.sources.items():
            root = self.mailstore / relative
            for leaf in ("cur", "new", "tmp"):
                (root / leaf).mkdir(parents=True, exist_ok=True)
            for index in range(count):
                (root / "cur" / f"message-{index}:2,S").write_text(
                    f"{relative}-{index}\n", encoding="utf-8"
                )

        (self.mock_state / "ignore").write_text(
            "betterbird-post-main-archive-maildirpp-20260704-205827\n"
            "local-maildir\nprovider-inbox-test\ntest-maildir\n",
            encoding="utf-8",
        )
        (self.mock_state / "tags").write_text("unread\ninbox\n", encoding="utf-8")
        (self.mock_state / "new-count").write_text("0\n", encoding="utf-8")

        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "PATH": f"{self.mock_bin}:/usr/bin:/bin",
                "NOTMUCH_ENROLL_MAIL_ROOT": str(self.mail),
                "NOTMUCH_ENROLL_MAILSTORE": str(self.mailstore),
                "NOTMUCH_ENROLL_CONFIG": str(self.config),
                "NOTMUCH_ENROLL_DB_PATH": str(self.db),
                "NOTMUCH_ENROLL_STATE_DIR": str(self.state),
                "NOTMUCH_ENROLL_LOG_DIR": str(self.logs),
                "NOTMUCH_ENROLL_BACKUP_ROOT": str(self.backups),
                "NOTMUCH_ENROLL_MBSYNC_CONTROL": str(self.home / "mbsync-control"),
                "NOTMUCH_ENROLL_BROWSER_CONTROL": str(self.home / "browser-control"),
                "NOTMUCH_ENROLL_INDEX_CONTROL": str(self.home / "index-control"),
                "NOTMUCH_ENROLL_EXPECTED_LOCAL": "2",
                "NOTMUCH_ENROLL_EXPECTED_DELTA": "1",
                "NOTMUCH_ENROLL_EXPECTED_PROVIDER_TEST": "1",
                "NOTMUCH_ENROLL_EXPECTED_TEST": "1",
                "NOTMUCH_ENROLL_EXPECTED_PROVIDER_ARCHIVE": "0",
                "NOTMUCH_ENROLL_MIN_FREE_KIB": "100",
                "NOTMUCH_ENROLL_RESTORE_WAIT_ATTEMPTS": "1",
                "NOTMUCH_ENROLL_QUIESCE_WAIT_ATTEMPTS": "1",
                "NOTMUCH_ENROLL_MBSYNC_LOCK_DIR": str(
                    self.state / "mbsync.lock"
                ),
                "NOTMUCH_ENROLL_REFRESH_LOCK_DIR": str(
                    self.state / "refresh.lock"
                ),
                "MOCK_MAILSTORE": str(self.mailstore),
                "MOCK_DB": str(self.db),
                "MOCK_CONFIG_STATE": str(self.mock_state),
                "MOCK_CONTROL_LOG": str(self.control_log),
            }
        )
        self.write_executable(
            self.mock_bin / "findmnt",
            "#!/bin/sh\nprintf '%s\\n' xfs\n",
        )
        self.write_executable(
            self.mock_bin / "df",
            textwrap.dedent(
                """\
                #!/bin/sh
                printf '%s\n' 'Filesystem 1024-blocks Used Available Capacity Mounted on'
                printf '%s\n' 'mock 1000000 1 900000 1% /mail'
                """
            ),
        )
        self.write_notmuch_mock()
        for name in ("mbsync-control", "browser-control", "index-control"):
            self.write_control_mock(self.home / name, name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    @staticmethod
    def write_executable(path: Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def write_control_mock(self, path: Path, name: str) -> None:
        self.write_executable(
            path,
            textwrap.dedent(
                f"""\
                #!/bin/sh
                printf '%s:%s\\n' '{name}' "$*" >> "$MOCK_CONTROL_LOG"
                case "$1" in
                  status)
                    case '{name}' in
                      mbsync-control) printf '%s\\n' loop=running paused=no;;
                      index-control) printf '%s\\n' loop=running;;
                      browser-control)
                        if [ "${{MOCK_BROWSER_RESTORE_STUCK:-0}}" = 1 ] &&
                          grep -Fqx 'browser-control:start' "$MOCK_CONTROL_LOG"; then
                          printf '%s\\n' server=stopped
                        else
                          printf '%s\\n' server=running
                        fi
                        ;;
                    esac
                    ;;
                  refresh-index)
                    printf '%s\\n' 'private-refresh-detail-that-must-not-reach-operator-output'
                    if [ "${{MOCK_FAIL_REFRESH:-0}}" = 1 ]; then
                      printf '%s\\n' simulated-refresh-failure
                      exit 8
                    fi
                    printf '%s\\n' status=refresh-complete
                    ;;
                esac
                """
            ),
        )

    def write_notmuch_mock(self) -> None:
        self.write_executable(
            self.mock_bin / "notmuch",
            textwrap.dedent(
                """\
                #!/bin/sh
                case "$1" in --config=*) shift;; esac
                command=$1
                shift
                case "$command" in
                  config)
                    action=$1
                    key=$2
                    shift 2
                    case "$action:$key" in
                      get:database.path) printf '%s\\n' "$MOCK_DB";;
                      get:database.mail_root) printf '%s\\n' "$MOCK_MAILSTORE";;
                      get:maildir.synchronize_flags) printf '%s\\n' false;;
                      get:index.decrypt) printf '%s\\n' false;;
                      get:new.ignore) cat "$MOCK_CONFIG_STATE/ignore";;
                      get:new.tags) cat "$MOCK_CONFIG_STATE/tags";;
                      set:new.ignore) : > "$MOCK_CONFIG_STATE/ignore"; for value in "$@"; do printf '%s\\n' "$value" >> "$MOCK_CONFIG_STATE/ignore"; done;;
                      set:new.tags) : > "$MOCK_CONFIG_STATE/tags"; for value in "$@"; do printf '%s\\n' "$value" >> "$MOCK_CONFIG_STATE/tags"; done;;
                    esac
                    ;;
                  count) printf '%s\\n' 1;;
                  dump) printf '%s\\n' '+inbox +unread -- id:baseline@example.test';;
                  new)
                    count=$(cat "$MOCK_CONFIG_STATE/new-count")
                    count=$((count + 1))
                    printf '%s\\n' "$count" > "$MOCK_CONFIG_STATE/new-count"
                    if [ "${MOCK_FAIL_NEW_AT:-0}" = "$count" ]; then
                      printf '%s\\n' simulated-index-failure
                      exit 9
                    fi
                    printf 'Processed mock stage %s\\n' "$count"
                    ;;
                  tag) printf 'tag:%s\\n' "$*" >> "$MOCK_CONFIG_STATE/actions";;
                  search)
                    query=
                    for value in "$@"; do query=$value; done
                    case "$query" in
                      *evolution/local-maildir*)
                        find "$MOCK_MAILSTORE/evolution/local-maildir" -type f \\( -path '*/cur/*' -o -path '*/new/*' \\) -print;;
                      *evolution/betterbird-delta-maildirpp-20260704*)
                        find "$MOCK_MAILSTORE/evolution/betterbird-delta-maildirpp-20260704" -type f \\( -path '*/cur/*' -o -path '*/new/*' \\) -print;;
                      *mbsync/provider-inbox-test*)
                        find "$MOCK_MAILSTORE/mbsync/provider-inbox-test" -type f \\( -path '*/cur/*' -o -path '*/new/*' \\) -print;;
                      *evolution/test-maildir*)
                        find "$MOCK_MAILSTORE/evolution/test-maildir" -type f \\( -path '*/cur/*' -o -path '*/new/*' \\) -print;;
                      *evolution/provider-live-archive*) :;;
                      *)
                        find "$MOCK_MAILSTORE/mbsync/provider-live" -type f \\( -path '*/cur/*' -o -path '*/new/*' \\) -print
                        find "$MOCK_MAILSTORE/evolution/betterbird-delta-maildirpp-20260704" -type f \\( -path '*/cur/*' -o -path '*/new/*' \\) -print
                        ;;
                    esac
                    ;;
                esac
                """
            ),
        )

    def run_helper(
        self, *args: str, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["sh", str(HELPER), *args],
            text=True,
            capture_output=True,
            check=False,
            env=env or self.env,
        )

    def test_inspect_and_acknowledge_exact_current_sources(self) -> None:
        inspected = self.run_helper("inspect")
        self.assertEqual(0, inspected.returncode, inspected.stdout + inspected.stderr)
        self.assertIn(
            "source=evolution/local-maildir message_paths=2", inspected.stdout
        )
        self.assertIn(
            "source=mbsync/provider-inbox-test message_paths=1", inspected.stdout
        )
        acknowledged = self.run_helper("acknowledge-current")
        self.assertEqual(
            0, acknowledged.returncode, acknowledged.stdout + acknowledged.stderr
        )
        marker = self.state / "current-sources-acknowledged.env"
        self.assertTrue(marker.is_file())
        self.assertEqual(0o600, marker.stat().st_mode & 0o777)

    def test_acknowledgement_refuses_inventory_drift(self) -> None:
        extra = self.mailstore / "evolution" / "local-maildir" / "cur" / "extra:2,S"
        extra.write_text("drift\n", encoding="utf-8")
        result = self.run_helper("acknowledge-current")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("expected 2", result.stdout)

    def test_enroll_restores_live_defaults_and_exact_ignore(self) -> None:
        self.assertEqual(0, self.run_helper("acknowledge-current").returncode)
        result = self.run_helper("enroll")
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("status=source_enrollment_complete", result.stdout)
        self.assertNotIn("private-refresh-detail", result.stdout)
        self.assertNotIn("Processed mock stage", result.stdout)
        self.assertEqual(
            ["betterbird-post-main-archive-maildirpp-20260704-205827"],
            (self.mock_state / "ignore").read_text(encoding="utf-8").splitlines(),
        )
        self.assertEqual(
            ["unread", "inbox"],
            (self.mock_state / "tags").read_text(encoding="utf-8").splitlines(),
        )
        actions = (self.mock_state / "actions").read_text(encoding="utf-8")
        self.assertIn("+historical-archive", actions)
        self.assertIn("+provider-inbox-test", actions)
        self.assertIn("+test-mail", actions)
        controls = self.control_log.read_text(encoding="utf-8")
        self.assertIn("mbsync-control:pause", controls)
        self.assertIn("index-control:stop", controls)
        self.assertIn("browser-control:stop", controls)
        self.assertIn("browser-control:start", controls)

    def test_failed_index_restores_database_and_service_states(self) -> None:
        self.assertEqual(0, self.run_helper("acknowledge-current").returncode)
        env = self.env.copy()
        env["MOCK_FAIL_NEW_AT"] = "2"
        result = self.run_helper("enroll", env=env)
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(
            "baseline-db\n", (self.db / "database").read_text(encoding="utf-8")
        )
        failed = list(self.backups.glob("source-enrollment-*/notmuch-database.failed-enrollment"))
        self.assertEqual(1, len(failed))
        controls = self.control_log.read_text(encoding="utf-8")
        self.assertIn("browser-control:start", controls)
        self.assertIn("index-control:start", controls)
        self.assertIn("mbsync-control:resume", controls)

    def test_prebackup_refresh_failure_restores_service_states(self) -> None:
        self.assertEqual(0, self.run_helper("acknowledge-current").returncode)
        env = self.env.copy()
        env["MOCK_FAIL_REFRESH"] = "1"
        result = self.run_helper("enroll", env=env)
        self.assertNotEqual(0, result.returncode)
        self.assertEqual([], list(self.backups.glob("source-enrollment-*")))
        controls = self.control_log.read_text(encoding="utf-8")
        self.assertIn("browser-control:start", controls)
        self.assertIn("index-control:start", controls)
        self.assertIn("mbsync-control:resume", controls)

    def test_active_sync_lock_blocks_before_backup_and_restores_services(self) -> None:
        self.assertEqual(0, self.run_helper("acknowledge-current").returncode)
        (self.state / "mbsync.lock").mkdir()
        result = self.run_helper("enroll")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("lock did not quiesce", result.stdout)
        self.assertEqual([], list(self.backups.glob("source-enrollment-*")))
        controls = self.control_log.read_text(encoding="utf-8")
        self.assertIn("browser-control:start", controls)
        self.assertIn("index-control:start", controls)
        self.assertIn("mbsync-control:resume", controls)

    def test_failed_service_restore_rolls_back_database(self) -> None:
        self.assertEqual(0, self.run_helper("acknowledge-current").returncode)
        env = self.env.copy()
        env["MOCK_BROWSER_RESTORE_STUCK"] = "1"
        result = self.run_helper("enroll", env=env)
        self.assertNotEqual(0, result.returncode)
        self.assertIn("service state did not recover", result.stdout)
        self.assertEqual(
            "baseline-db\n", (self.db / "database").read_text(encoding="utf-8")
        )
        failed = list(
            self.backups.glob(
                "source-enrollment-*/notmuch-database.failed-enrollment"
            )
        )
        self.assertEqual(1, len(failed))


if __name__ == "__main__":
    unittest.main()
