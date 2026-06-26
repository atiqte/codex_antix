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
