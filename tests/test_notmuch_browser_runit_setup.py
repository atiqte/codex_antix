import os
from pathlib import Path
import stat
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
HELPER = REPO_ROOT / "scripts" / "notmuch_browser_runit_setup.sh"


class RunitSessionReconcileTests(unittest.TestCase):
    def make_executable(self, path: Path, content: str) -> None:
        path.write_text(content, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def test_repair_installs_one_idempotent_block_and_reconciles(self) -> None:
        with tempfile.TemporaryDirectory() as raw_temp:
            root = Path(raw_temp)
            home = root / "home"
            bin_dir = root / "bin"
            usersv = home / ".runit" / "usersv"
            active = home / ".runit" / "service"
            browser_def = usersv / "notmuch-browser"
            index_def = usersv / "notmuch-browser-index"
            state_dir = root / "state"
            log_dir = root / "logs"
            backup_dir = root / "backups"
            startup = home / ".icewm" / "startup"
            config = home / ".config" / "notmuch" / "default" / "config"
            app = home / ".local" / "bin" / "notmuch-browser"
            browser_control = home / ".local" / "bin" / "notmuch-browser-control"
            index_control = home / ".local" / "bin" / "notmuch-browser-index-control"

            for directory in (
                bin_dir,
                browser_def,
                index_def,
                active,
                state_dir,
                log_dir,
                backup_dir,
                startup.parent,
                config.parent,
                app.parent,
            ):
                directory.mkdir(parents=True, exist_ok=True)
            for definition in (browser_def, index_def):
                (definition / ".notmuch-browser-user-runit-managed").write_text(
                    "", encoding="utf-8"
                )
            (active / "notmuch-browser").symlink_to("../usersv/notmuch-browser")
            (active / "notmuch-browser-index").symlink_to(
                "../usersv/notmuch-browser-index"
            )
            startup.write_text("#!/bin/sh\nexisting-command &\n", encoding="utf-8")
            startup.chmod(0o700)
            config.write_text("[database]\npath=/mail/SearchIndex/notmuch/default\n")

            for executable in (app, browser_control, index_control):
                self.make_executable(executable, "#!/bin/sh\nexit 0\n")
            self.make_executable(
                bin_dir / "pgrep",
                "#!/bin/sh\nprintf '1234\\n'\n",
            )
            self.make_executable(
                bin_dir / "svlogd",
                "#!/bin/sh\nexit 0\n",
            )
            self.make_executable(
                bin_dir / "sv",
                textwrap.dedent(
                    """\
                    #!/bin/sh
                    case "$1" in
                      status) printf 'run: %s: (pid 1234) 10s\\n' "$2" ;;
                    esac
                    exit 0
                    """
                ),
            )
            self.make_executable(
                bin_dir / "curl",
                "#!/bin/sh\nprintf '%s\\n' '{\"ok\":true,\"read_only\":true,\"mail_mutation\":false}'\n",
            )

            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "PATH": f"{bin_dir}:/usr/bin:/bin",
                    "NOTMUCH_BROWSER_BIN": str(app),
                    "NOTMUCH_BROWSER_CONTROL": str(browser_control),
                    "NOTMUCH_BROWSER_INDEX_CONTROL": str(index_control),
                    "NOTMUCH_BROWSER_CONFIG": str(config),
                    "NOTMUCH_BROWSER_STATE_DIR": str(state_dir),
                    "NOTMUCH_BROWSER_LOG_DIR": str(log_dir),
                    "NOTMUCH_BROWSER_BACKUP_ROOT": str(backup_dir),
                    "NOTMUCH_BROWSER_ICEWM_STARTUP": str(startup),
                    "NOTMUCH_BROWSER_USER_SERVICE_ROOT": str(usersv),
                    "NOTMUCH_BROWSER_ACTIVE_SERVICE_ROOT": str(active),
                    "NOTMUCH_BROWSER_SESSION_RECONCILE_INTERVAL_SECONDS": "1",
                    "NOTMUCH_BROWSER_SESSION_RECONCILE_STABLE_SECONDS": "1",
                    "NOTMUCH_BROWSER_SESSION_RECONCILE_MAX_SECONDS": "3",
                }
            )

            for _ in range(2):
                result = subprocess.run(
                    ["sh", str(HELPER), "repair-session-startup"],
                    check=False,
                    capture_output=True,
                    text=True,
                    env=env,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(
                    "status=user_runit_session_startup_repaired", result.stdout
                )

            content = startup.read_text(encoding="utf-8")
            self.assertEqual(
                content.count(
                    "# BEGIN NOTMUCH BROWSER USER RUNIT SESSION RECONCILE"
                ),
                1,
            )
            self.assertEqual(
                content.count(
                    "# END NOTMUCH BROWSER USER RUNIT SESSION RECONCILE"
                ),
                1,
            )
            self.assertIn("existing-command &", content)
            self.assertEqual(stat.S_IMODE(startup.stat().st_mode), 0o700)


if __name__ == "__main__":
    unittest.main()
