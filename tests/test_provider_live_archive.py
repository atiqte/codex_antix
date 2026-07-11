import importlib.util
import json
import os
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "src" / "provider_live_archive.py"
SRC_DIR = SCRIPT.parent
if str(SRC_DIR) not in sys.path:
    sys.path.insert(0, str(SRC_DIR))
SPEC = importlib.util.spec_from_file_location("provider_live_archive", SCRIPT)
archive = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = archive
SPEC.loader.exec_module(archive)


class ProviderLiveArchiveTests(unittest.TestCase):
    def write_production_config(self, path: Path, dangerous: bool = False):
        sync = "PullNew PushGone" if dangerous else "PullNew"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            f'''FSync yes

IMAPAccount provider
Host imap.example.test
Port 993
User user@example.test
PassCmd "cat ~/.config/isync/provider.pass"
TLSType IMAPS
SystemCertificates yes
Timeout 60
PipelineDepth 1

IMAPStore provider-remote
Account provider
UseNamespace yes

MaildirStore provider-live-local
Inbox /mail/Mailstore/mbsync/provider-live
SubFolders Maildir++

Channel provider-live
Far :provider-remote:
Near :provider-live-local:
Patterns "INBOX" "Drafts" "Trash" "spam" "Junk" "Archive"
Sync {sync}
Create Near
Remove None
Expunge None
CopyArrivalDate yes
SyncState /mail/AppData/isync/state/provider-live/

Channel provider-live-sent-upload
Far :provider-remote:Sent
Near :provider-live-local:Sent
Sync PullNew PushNew
Create None
Remove None
Expunge None
CopyArrivalDate yes
SyncState /mail/AppData/isync/state/provider-live/

Group provider-live-group
Channel provider-live
Channel provider-live-sent-upload
''',
            encoding="ascii",
        )

    def make_environment(self, base: Path, count: int = 3):
        live = base / "mail" / "Mailstore" / "mbsync" / "provider-live"
        archive_root = base / "mail" / "Mailstore" / "evolution" / "provider-live-archive"
        state = base / "mail" / "AppData" / "provider-live-archive"
        backup = base / "mail" / "Backups" / "provider-live-archive"
        mbsync_state = base / "mail" / "AppData" / "isync" / "state" / "provider-live"
        config = base / "home" / ".config" / "isyncrc"
        for state_name in ("cur", "new", "tmp"):
            (live / state_name).mkdir(parents=True, exist_ok=True)
        mbsync_state.mkdir(parents=True)
        (mbsync_state / "INBOX").write_text("state\n", encoding="ascii")
        config.parent.mkdir(parents=True)
        self.write_production_config(config)
        delimiter = archive.info_delimiter()
        for index in range(1, count + 1):
            flags = "FS" if index == 1 else ("S" if index == 2 else "")
            name = f"170000000{index}.test,U={index}{delimiter}2,{flags}"
            path = live / "cur" / name
            path.write_bytes(f"Message-ID: <message-{index}@example.test>\n\nbody-{index}\n".encode())
            stamp = 1700000000 + index * 2678400
            os.utime(path, (stamp, stamp))
        archive.create_layout(archive_root, state, backup)
        return live, archive_root, state, backup, mbsync_state, config

    def snapshot(self, base: Path, count: int = 3, run_id: str = "20260711-120000"):
        env = self.make_environment(base, count)
        live, archive_root, state, backup, mbsync_state, config = env
        data = archive.snapshot_run(
            run_id,
            live,
            archive_root,
            state,
            backup,
            mbsync_state,
            config,
            threshold=1,
        )
        return env, data

    def complete_copy(self, base: Path, count: int = 3, run_id: str = "20260711-120000"):
        env, _data = self.snapshot(base, count, run_id)
        live, archive_root, state, backup, _mbsync_state, _config = env
        external = base / "external"
        external.mkdir()
        archive.external_pack(
            run_id,
            external,
            state,
            backup,
            mail_root=base / "mail",
            part_size=256,
            allow_same_filesystem=True,
        )
        archive.copy_to_archive(run_id, state, backup, archive_root)
        verified = archive.verify_copy(run_id, live, archive_root, state, backup)
        return env, verified

    def complete_gates(self, base: Path, count: int = 3, run_id: str = "20260711-120000"):
        env, _data = self.complete_copy(base, count, run_id)
        live, archive_root, state, backup, _mbsync_state, _config = env
        archive.mark_evolution_validated(run_id, state, backup, "test attestation")
        indexed = base / "indexed.txt"
        id_map = archive.build_archive_id_map(archive_root)
        indexed.write_text("\n".join(str(path) for path in id_map.values()) + "\n", encoding="utf-8")
        archive.verify_notmuch_paths(
            run_id,
            indexed,
            state,
            backup,
            archive_root,
            base / "mail" / "Mailstore" / "evolution" / "local-maildir",
        )
        return env

    def test_estimate_selects_all_messages_for_target_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            live, *_rest = self.make_environment(Path(tmp), 4)
            result = archive.estimate(live, threshold=4)

            self.assertEqual(result["live_inbox_count"], 4)
            self.assertEqual(result["selected_count"], 4)
            self.assertTrue(result["alert_required"])
            self.assertEqual(result["uid_min"], 1)
            self.assertEqual(result["uid_max"], 4)
            self.assertEqual(result["full_provider_live_snapshot_bytes"], result["selected_bytes"])

    def test_estimate_below_threshold_does_not_alert(self):
        with tempfile.TemporaryDirectory() as tmp:
            live, *_rest = self.make_environment(Path(tmp), 2)

            result = archive.estimate(live, threshold=3)

            self.assertFalse(result["alert_required"])
            self.assertEqual(result["selected_count"], 2)

    def test_mbsync_policy_audit_accepts_exact_validated_channels(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "isyncrc"
            self.write_production_config(config)

            result = archive.audit_mbsync_config(config)

            self.assertEqual(result["mbsync_policy"], "validated")

    def test_mbsync_policy_audit_refuses_disappearance_propagation(self):
        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "isyncrc"
            self.write_production_config(config, dangerous=True)

            with self.assertRaises(archive.ArchiveError):
                archive.audit_mbsync_config(config)

    def test_notmuch_ignore_keeps_only_approved_scope(self):
        result = archive.compute_notmuch_ignore(
            current={"evolution", "mbsync", "existing-ignore"},
            mail_root_children={"evolution", "mbsync", "unexpected-root"},
            evolution_children={"provider-live-archive", "betterbird-delta-maildirpp-20260704", "local-maildir", "old-delta"},
            mbsync_children={"provider-live", "provider-inbox-test"},
        )

        self.assertIn("local-maildir", result)
        self.assertIn("old-delta", result)
        self.assertIn("provider-inbox-test", result)
        self.assertIn("unexpected-root", result)
        self.assertNotIn("evolution", result)
        self.assertNotIn("mbsync", result)
        self.assertNotIn("provider-live-archive", result)
        self.assertNotIn("provider-live", result)

    def test_layout_refuses_unexpected_existing_archive_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            archive_root = base / "archive"
            archive_root.mkdir()
            (archive_root / "unexpected.txt").write_text("not mail", encoding="ascii")

            with self.assertRaises(archive.ArchiveError):
                archive.create_layout(archive_root, base / "state", base / "backup")

    def test_snapshot_manifest_preserves_uids_hashes_flags_and_months(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, data = self.snapshot(base)
            _live, _archive_root, state, backup, *_rest = env
            paths = archive.run_paths("20260711-120000", state, backup)
            records = archive.read_jsonl(paths["manifest"])

            self.assertEqual(data["phase"], "snapshotted")
            self.assertEqual([row.uid for row in records], [1, 2, 3])
            self.assertEqual(records[0].flags, "FS")
            self.assertNotIn(",U=", records[0].archive_rel)
            self.assertIn(".Inbox.2023.", records[0].archive_rel)
            if os.name != "nt":
                self.assertEqual(paths["manifest"].stat().st_mode & 0o777, 0o600)

    def test_duplicate_uid_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            live, *_rest = self.make_environment(base, 1)
            delimiter = archive.info_delimiter()
            (live / "cur" / f"duplicate,U=1{delimiter}2,S").write_bytes(b"Message-ID: <duplicate@test>\n\nbody")

            with self.assertRaises(archive.ArchiveError):
                archive.estimate(live, threshold=1)

    def test_external_backup_copy_and_verification(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, verified = self.complete_copy(base)
            _live, archive_root, state, backup, *_rest = env
            paths = archive.run_paths("20260711-120000", state, backup)
            records = archive.read_jsonl(paths["manifest"])

            self.assertTrue(verified["external_verified"])
            self.assertTrue(verified["copy_verified"])
            self.assertEqual(len(archive.build_archive_id_map(archive_root)), len(records))
            self.assertEqual(archive.tmp_file_count(archive_root), 0)

    def test_valid_partial_archive_copy_is_resumed_and_published(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, _data = self.snapshot(base, count=1)
            _live, archive_root, state, backup, *_rest = env
            external = base / "external"
            external.mkdir()
            archive.external_pack(
                "20260711-120000",
                external,
                state,
                backup,
                mail_root=base / "mail",
                part_size=256,
                allow_same_filesystem=True,
            )
            paths = archive.run_paths("20260711-120000", state, backup)
            record = archive.read_jsonl(paths["manifest"])[0]
            destination = archive_root / record.archive_rel
            month = destination.parent.parent
            parts = month.name.lstrip(".").split(".")
            archive.ensure_maildir(archive_root / ".Inbox")
            archive.ensure_maildir(archive_root / f".Inbox.{parts[1]}")
            archive.ensure_maildir(month)
            partial = month / "tmp" / f"{destination.name}.partial"
            partial.write_bytes((paths["snapshot_live"] / record.snapshot_rel).read_bytes())

            archive.copy_to_archive("20260711-120000", state, backup, archive_root)

            self.assertFalse(partial.exists())
            self.assertTrue(destination.is_file())
            self.assertEqual(archive.sha256_file(destination), record.sha256)

    def test_external_target_under_mail_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, _data = self.snapshot(base)
            _live, _archive_root, state, backup, *_rest = env
            target = base / "mail" / "external"
            target.mkdir()

            with self.assertRaises(archive.ArchiveError):
                archive.external_pack(
                    "20260711-120000",
                    target,
                    state,
                    backup,
                    mail_root=base / "mail",
                    allow_same_filesystem=True,
                )

    def test_corrupted_external_part_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, _verified = self.complete_copy(base)
            _live, _archive_root, state, backup, *_rest = env
            data = archive.run_status("20260711-120000", state, backup)
            manifest = Path(data["external_manifest"])
            manifest_data = json.loads(manifest.read_text(encoding="utf-8"))
            part = manifest.parent / manifest_data["archive"]["parts"][0]["name"]
            with part.open("r+b") as handle:
                first = handle.read(1)
                handle.seek(0)
                handle.write(b"X" if first != b"X" else b"Y")

            with self.assertRaises(archive.transport.TransportError):
                archive.verify_external_manifest(data)

    def test_evolution_flag_rename_remains_resolvable_by_archive_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, _verified = self.complete_copy(base)
            _live, archive_root, *_rest = env
            before = archive.build_archive_id_map(archive_root)
            archive_id, path = next(iter(before.items()))
            renamed = path.with_name(path.name.rsplit(",", 1)[0] + ",RS")
            path.rename(renamed)

            after = archive.build_archive_id_map(archive_root)
            self.assertEqual(after[archive_id], renamed)

    def test_notmuch_forbidden_archive_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env, _verified = self.complete_copy(base)
            _live, archive_root, state, backup, *_rest = env
            archive.mark_evolution_validated("20260711-120000", state, backup, "ok")
            indexed = base / "indexed.txt"
            current = list(archive.build_archive_id_map(archive_root).values())
            forbidden = base / "mail" / "Mailstore" / "evolution" / "local-maildir"
            forbidden.mkdir(parents=True)
            indexed.write_text("\n".join(str(path) for path in current + [forbidden / "cur" / "bad"]) + "\n", encoding="utf-8")

            with self.assertRaises(archive.ArchiveError):
                archive.verify_notmuch_paths("20260711-120000", indexed, state, backup, archive_root, forbidden)

    def test_cleanup_canary_bulk_cleanup_and_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env = self.complete_gates(base)
            live, archive_root, state, backup, *_rest = env
            run_id = "20260711-120000"

            canary = archive.cleanup_canary(run_id, live, archive_root, state, backup)
            self.assertEqual(canary["phase"], "canary_removed")
            archive.verify_canary(run_id, live, archive_root, state, backup)
            archive.cleanup_remaining(run_id, live, archive_root, state, backup)
            result = archive.verify_cleanup(run_id, live, archive_root, state, backup)

            self.assertTrue(result["cleanup_verified"])
            self.assertEqual(result["post_cleanup_live_count"], 0)
            restored = archive.rollback(run_id, live, state, backup)
            self.assertEqual(restored["rollback_restored_count"], 3)
            self.assertEqual(len(archive.build_uid_map(live)), 3)

    def test_canary_redownload_is_detected(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env = self.complete_gates(base)
            live, archive_root, state, backup, *_rest = env
            run_id = "20260711-120000"
            data = archive.cleanup_canary(run_id, live, archive_root, state, backup)
            paths = archive.run_paths(run_id, state, backup)
            record = {row.uid: row for row in archive.read_jsonl(paths["manifest"])}[data["canary_uid"]]
            os.link(paths["snapshot_live"] / record.snapshot_rel, live / record.source_rel)

            with self.assertRaises(archive.ArchiveError):
                archive.verify_canary(run_id, live, archive_root, state, backup)

    def test_changed_source_refuses_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env = self.complete_gates(base)
            live, archive_root, state, backup, *_rest = env
            source = next(archive.iter_inbox_files(live))
            source.write_bytes(b"changed")

            with self.assertRaises(archive.ArchiveError):
                archive.cleanup_canary("20260711-120000", live, archive_root, state, backup)

    def test_snapshot_retirement_requires_age_and_verified_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            env = self.complete_gates(base, count=1)
            live, archive_root, state, backup, *_rest = env
            run_id = "20260711-120000"
            archive.cleanup_canary(run_id, live, archive_root, state, backup)
            archive.verify_canary(run_id, live, archive_root, state, backup)
            archive.cleanup_remaining(run_id, live, archive_root, state, backup)
            archive.verify_cleanup(run_id, live, archive_root, state, backup)
            paths = archive.run_paths(run_id, state, backup)

            with self.assertRaises(archive.ArchiveError):
                archive.retire_snapshot(run_id, state, backup, minimum_days=30, archive=archive_root)

            data = archive.read_json(paths["run_json"])
            data["created_at_utc"] = (datetime.now(timezone.utc) - timedelta(days=31)).isoformat()
            archive.atomic_json(paths["run_json"], data)
            retired = archive.retire_snapshot(run_id, state, backup, minimum_days=30, archive=archive_root)
            self.assertTrue(retired["snapshot_retired"])
            self.assertFalse(paths["snapshot_bundle"].exists())


if __name__ == "__main__":
    unittest.main()
