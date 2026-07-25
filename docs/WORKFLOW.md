# Workflow

This repository uses a portable Git workflow across Windows 11 and Debian/antiX. The approved application workflow includes Python standard-library migration utilities and the pinned Go/templ/chi/HTMX/Bun/Tailwind notmuch browser stack; do not add another runtime or dependency family without owner approval.

## Start a Work Session

1. Open the repository root.
2. Read:
   - `AGENTS.md`
   - `README.md`
   - `docs/PROJECT_STATE.md`
   - `docs/TODO.md`
   - `docs/DECISIONS.md`
   - `docs/WORK_VALIDATION_LEDGER.md`
3. Check repository state:

```powershell
git status --short --branch
```

On Debian Linux:

```sh
git status --short --branch
```

4. Confirm the current task is consistent with `docs/TODO.md` and `docs/PROJECT_STATE.md`.
5. Ask before installing dependencies outside the approved lockfiles, deleting files without explicit owner approval, or performing non-routine remote operations.

## Update Project Memory

Update memory files as part of meaningful work:

- `docs/PROJECT_STATE.md`: update when repository state, phase, objective, structure, or next actions change.
- `docs/DECISIONS.md`: update when the owner approves a meaningful architectural, tooling, hosting, or workflow choice.
- `docs/TODO.md`: update when tasks are added, completed, removed, or reprioritized.
- `docs/IDEAS.md`: add uncommitted possibilities that are not yet decisions.
- `docs/CHANGELOG.md`: add user-visible or repository-level changes after meaningful updates.
- `docs/WORK_VALIDATION_LEDGER.md`: update after terminal-guided command chunks, pasted terminal-output review, validation-heavy work, or operator-run steps.

Keep entries concise, dated when useful, and easy to scan.

## Run Reviewed antiX Operator Gates

Codex prepares exactly one active batch at:

```text
codex-output/notmuch-browser-operator/current.sh
```

The owner runs it only through the committed logger:

```sh
cd /home/atiq/orca/workspaces/codex_antix/branch-codex
./scripts/notmuch_browser_operator_run.sh
```

The runner mirrors stdout/stderr to the terminal and writes a private millisecond-stamped log under `codex-output/notmuch-browser-operator/logs/`. It also records batch identity, timestamps, exit status, and the saved-log hash. Codex reads that exact log and updates the validation ledger before replacing `current.sh` with the next reviewed gate. Do not include secrets, credentials, private message content, or unredacted configuration in batches or logs.

## Record Command-Chunk Validation

When Codex gives command chunks for the owner to run outside this repository, especially on antiX, Fedora, or Windows, record the outcome in `docs/WORK_VALIDATION_LEDGER.md`.

Use the ledger for:

- command chunks copied into another terminal;
- terminal output returned through `codex-input/pasted-text.txt`;
- validation steps that prove a setup is safe or complete;
- failed, partial, skipped, or superseded steps that future sessions should not rediscover.

Do not store secrets or massive raw logs in the ledger. Reference the source path or log path and summarize the key result.

## Commit Changes

Recommended review flow:

```powershell
git status --short
git diff
```

On Debian Linux:

```sh
git status --short
git diff
```

Stage, commit, and push at the end of each working session:

```powershell
git add .
git commit -m "Set up project memory and workflow docs"
git push
```

Equivalent Debian Linux commands:

```sh
git add .
git commit -m "Set up project memory and workflow docs"
git push
```

Use the most appropriate self-explanatory commit message for the work completed.

## Connecting a New Remote

After the owner chooses a provider and creates an empty remote repository:

```powershell
git remote -v
git remote add origin <remote-url>
git push -u origin main
```

On Debian Linux:

```sh
git remote -v
git remote add origin <remote-url>
git push -u origin main
```

If `origin` already exists, inspect it before changing anything:

```powershell
git remote -v
```

Do not replace remotes or perform non-routine remote operations without explicit owner approval.

## Resume on Another Machine

1. Install Git.
2. Clone the repository:

```powershell
git clone <remote-url>
cd <repo-folder>
```

On Debian Linux:

```sh
git clone <remote-url>
cd <repo-folder>
```

3. Read the required memory files from the start of this workflow, including `docs/WORK_VALIDATION_LEDGER.md`.
4. Run:

```powershell
git status --short --branch
```

or:

```sh
git status --short --branch
```

5. Continue from `docs/PROJECT_STATE.md` and `docs/TODO.md`.
