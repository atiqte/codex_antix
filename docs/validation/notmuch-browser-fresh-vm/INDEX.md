# Fresh-VM Notmuch Browser Validation

This directory preserves the exact privacy-reviewed operator evidence for the
release-pinned antiX reconstruction workflow. Private recovery data remains
outside Git; committed evidence contains only commands, paths, counts, hashes,
modes, capacity, and health status.

| Gate | Result | Exact batch | Complete log | Record | Summary |
|---|---|---|---|---|---|
| 01 canonical recovery set | success | `batches/01-canonical-recovery-set.sh` (`2c2caac2...`) | `logs/01-canonical-recovery-set.log` (`2c25eaf6...`) | `records/01-canonical-recovery-set.env` | Verified the 21-part historical package and exact 247-message delta, proved XFS reflink support, created and twice verified the private 27-file recovery set, and finalized `recovery-set.env` SHA256 `6858d505...`. All directories/files are mode 700/600, symlinks and incoming residue are zero, physical consumption was 293,964 KiB, production stayed exact/read-only at 31,668 messages and 51,947 files, and no mail/notmuch/service mutation ran. |

The complete 135-line log and exact batch passed automated credential-shape
scanning and manual review for addresses, Message-IDs, headers, subjects,
capability tokens, cookies, credentials, private keys, and message content.
Annotated release-candidate tag `notmuch-browser-antix-v1.0.0-rc1` resolves to
the exact tested pin/evidence commit `ef915e00e3802d5bebd4fb7d74b383b7083a685d`.
