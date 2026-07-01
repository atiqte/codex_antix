# TODO

## Active

- [ ] Review setup and memory files.
- [ ] Push setup/memory/workflow files using the approved end-of-session workflow.
- [ ] On Fedora, stop Evolution and background services before packing the converted archive.
- [ ] On Fedora, inspect `/home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp` with `src/maildirpp_transport.py inspect`.
- [ ] Pack the converted Maildir++ archive with `src/maildirpp_transport.py pack --source /home/atiq/Evolution-Mailstore/betterbird-archive-maildirpp --out <transfer-dir>`.
- [ ] Transfer `manifest.json`, `inventory.jsonl`, and all `maildirpp-archive.tar.gz.partNNNN` files to antiX.
- [ ] On antiX, run `src/maildirpp_transport.py verify-archive --manifest <transfer-dir>/manifest.json`.
- [ ] On antiX, restore into `/mail/Mailstore/evolution/local-maildir` with `src/maildirpp_transport.py unpack --manifest <transfer-dir>/manifest.json --dest /mail/Mailstore/evolution/local-maildir`.
- [ ] On antiX, run `src/maildirpp_transport.py verify-tree --manifest <transfer-dir>/manifest.json --dest /mail/Mailstore/evolution/local-maildir`.
- [ ] On antiX, run `src/maildirpp_transport.py inspect --source /mail/Mailstore/evolution/local-maildir`.
- [ ] Add `/mail/Mailstore/evolution/local-maildir` to Evolution with `Maildir-format mail directories`.
- [ ] Validate the antiX Evolution archive account: `mail_tagindustries_com_sg.Inbox`, message count, opening, HTML rendering, and no error popup.
- [ ] Monitor the production `provider-live` auto-sync loop with `mbsync-provider-live-control status` during normal antiX use.
- [ ] Decide broader project type beyond the approved mail migration utility.
- [ ] Choose future Git remote provider: GitHub or GitLab.

## Later

- [ ] Consider moving the mbsync `PassCmd` from the current chmod `600` password file to GPG after unattended polling remains stable.
- [ ] Consider `PullFlags` or broader IMAP two-way behavior only as separate controlled changes.
- [ ] Configure notmuch/Astroid only after the Betterbird archive and live Maildir layout are stable.
- [ ] Define the first implementation milestone.
- [ ] Choose language, runtime, and tooling only after the project type is explicit.
- [ ] Add project-specific setup instructions after tooling is selected.
- [ ] Create issue tracker labels or project board after a remote is connected, if useful.

## Done

- [x] Create project memory structure.
- [x] Document future Codex session rules.
- [x] Document language-neutral Git workflow.
- [x] Record approved end-of-session commit and push workflow.
- [x] Implement Python standard-library Betterbird maildir-lite to canonical Maildir++ converter.
- [x] Add portable unit tests for converter folder mapping and syntax validation.
- [x] Implement Python standard-library Betterbird profile transport utility with split archive verification.
- [x] Add portable unit tests for profile transport pack, verify, unpack, and safety failures.
- [x] Create Betterbird profile transport DIY guide in HTML and plain text formats.
- [x] Convert the full Betterbird maildir-lite archive on Fedora into canonical Maildir++ and verify copied hashes.
- [x] Record owner-reported Fedora Evolution GUI validation of the converted Maildir++ archive.
- [x] Implement Python standard-library converted Maildir++ archive transport utility with layout inspection and split archive verification.
- [x] Add portable unit tests for converted Maildir++ archive transport safety.
- [x] Create converted Maildir++ archive transport DIY guide in HTML and plain text formats.
- [x] Validate Evolution Flatpak 3.60.2 on antiX 26 runit with zzzFM/IceWM using `/mail` app-data symlink and a Maildir++ test account.
- [x] Create Evolution Flatpak antiX DIY guide in HTML and plain text formats.
- [x] Add user-level IceWM Evolution Flatpak launcher helper and guide instructions.
- [x] Validate Evolution Flatpak launcher on antiX through IceWM Personal menu and taskbar toolbar.
- [x] Switch Evolution IceWM entries to the official Flatpak-exported SVG icon.
- [x] Create mbsync antiX INBOX test guide in HTML and plain text formats.
- [x] Add antiX mbsync helper for inspect, install, layout, pull-only config, dry-run, sync-once, and status.
- [x] Validate APT `isync`/`mbsync 1.5.1` on antiX with the provider INBOX.
- [x] Pull 144 provider INBOX messages into `/mail/Mailstore/mbsync/provider-inbox-test` with deletion-safe policy.
- [x] Validate Evolution Flatpak reads the mbsync INBOX test Maildir with `BackendName=maildir`.
- [x] Run post-Evolution mbsync and confirm no duplicate flood or unexpected deletions.
- [x] Snapshot the validated antiX mbsync config and logs to `/mail/Backups/mbsync` without copying `provider.pass`.
- [x] Inventory remote IMAP folders read-only with `mbsync -c ~/.config/isyncrc --list-stores provider-remote`.
- [x] Verify empty `FARSUK` and `BASUNDHARA` folders and remove them from the IMAP server at the owner's request.
- [x] Create the deletion-safe production `/mail/Mailstore/mbsync/provider-live` tree for `INBOX`, `Drafts`, `Trash`, `spam`, `Sent`, `Junk`, and `Archive`.
- [x] Run first and second `provider-live` pulls, confirm no duplicate flood, and verify `tmp` remains empty.
- [x] Validate Evolution Flatpak reads the production `provider-live` Maildir with `BackendName=maildir`.
- [x] Validate Evolution SMTP by sending two test messages to Gmail and pulling Gmail replies back into `provider-live`.
- [x] Create and validate the 180-second `provider-live` auto-sync loop with pause, resume, status, sync-now, stop-loop, and start controls.
- [x] Add the `provider-live` auto-sync loop to IceWM startup with a marked block.
- [x] Configure Evolution to save production sent copies into `TAG-Mustang_mbsync-Live/Sent`.
- [x] Add a narrow `provider-live-sent-upload` mbsync channel with `Sync PullNew PushNew` only for Sent.
- [x] Update the auto-sync loop/control target to `provider-live-group`.
- [x] Validate controlled Sent upload, zero-duplicate second Sent sync, full group sync, and automatic loop Sent upload.
- [x] Update the mbsync HTML and text DIY guides with the validated production `provider-live` and Sent-upload setup.
- [x] Update `scripts/mbsync_provider_inbox_setup.sh` with production `provider-live`, Sent-upload, and auto-sync helper commands.
- [x] Add provider-live mbsync log retention with `logs` and `cleanup-logs` controls.
- [x] Harden the mbsync helper and guides with exact provider-live auto-sync reproduction commands.
- [x] Add and validate provider-live auto-sync timeout wrapping, sync-age status, stale-lock clearing, and stale loop PID protection.
- [x] Add a clear Start Here sequence to the mbsync HTML/text guides and label production config snippets as reference-only.
- [x] Add a topic-neutral work validation ledger for future command chunks and pasted-output review.
