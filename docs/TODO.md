# TODO

## Active

- [ ] Review setup and memory files.
- [ ] Push setup/memory/workflow files using the approved end-of-session workflow.
- [ ] Run `src/betterbird_maildirlite_to_maildirpp.py --dry-run` on antiX against a staged Betterbird sample profile.
- [ ] Review converter logs: `conversion.jsonl`, `folder-map.tsv`, `summary.tsv`, `duplicates.tsv`, `errors.tsv`, and `skipped.tsv`.
- [ ] Run a small antiX copy test and verify byte/hash preservation before full migration.
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
