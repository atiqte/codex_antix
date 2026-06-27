# TODO

## Active

- [ ] Review setup and memory files.
- [ ] Push setup/memory/workflow files using the approved end-of-session workflow.
- [ ] On Fedora, stop Betterbird fully and confirm no profile lock markers remain.
- [ ] Pack the full Betterbird profile with `src/betterbird_profile_transport.py pack --source ~/Betterbird-Email --out <transfer-dir>`.
- [ ] Transfer `manifest.json`, `inventory.jsonl`, and all `betterbird-profile.tar.gz.partNNNN` files to antiX.
- [ ] On antiX, run `src/betterbird_profile_transport.py verify-archive --manifest <transfer-dir>/manifest.json`.
- [ ] On antiX, restore the profile with `src/betterbird_profile_transport.py unpack --manifest <transfer-dir>/manifest.json --dest /mail/import-staging/betterbird-maildir`.
- [ ] On antiX, run `src/betterbird_profile_transport.py verify-tree --manifest <transfer-dir>/manifest.json --dest /mail/import-staging/betterbird-maildir`.
- [ ] Run `src/betterbird_maildirlite_to_maildirpp.py --dry-run` on antiX against a staged Betterbird sample profile.
- [ ] Review converter logs: `conversion.jsonl`, `folder-map.tsv`, `summary.tsv`, `duplicates.tsv`, `errors.tsv`, and `skipped.tsv`.
- [ ] Run a small antiX copy test and verify byte/hash preservation before full migration.
- [ ] Convert validated Betterbird mail into `/mail/Mailstore/evolution/local-maildir` after staging and dry-run checks pass.
- [ ] Add the validated production Maildir++ tree to Evolution with `Maildir-format mail directories`.
- [ ] On antiX, snapshot the validated mbsync config and logs to `/mail/Backups/mbsync` without copying `provider.pass`.
- [ ] On antiX, inventory remote IMAP folders read-only with `mbsync -c ~/.config/isyncrc --list-stores provider-remote`.
- [ ] Choose exactly one small non-INBOX, non-special folder for the second isolated mbsync test.
- [ ] On antiX, create `/mail/Mailstore/mbsync/provider-folder-test` and `/mail/AppData/isync/state/provider-folder-test`.
- [ ] Add one second-folder mbsync channel using `Sync PullNew`, `Create Near`, `Remove None`, and `Expunge None`.
- [ ] Run the second-folder sync twice, confirm no duplicate flood, and verify `tmp` remains empty.
- [ ] Add the second-folder test tree to Evolution as `Maildir-format mail directories` only after mbsync exits, if GUI validation is needed.
- [ ] Create `/mail/Mailstore/mbsync/provider-live` only after the second-folder test passes.
- [ ] Decide broader project type beyond the approved mail migration utility.
- [ ] Choose future Git remote provider: GitHub or GitLab.

## Later

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
