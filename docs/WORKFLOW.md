# Workflow

This repository currently uses a language-neutral Git workflow. Do not add runtime-specific setup steps until the project type is decided.

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
5. Ask before installing dependencies, deleting files, or performing non-routine remote operations.

## Update Project Memory

Update memory files as part of meaningful work:

- `docs/PROJECT_STATE.md`: update when repository state, phase, objective, structure, or next actions change.
- `docs/DECISIONS.md`: update when the owner approves a meaningful architectural, tooling, hosting, or workflow choice.
- `docs/TODO.md`: update when tasks are added, completed, removed, or reprioritized.
- `docs/IDEAS.md`: add uncommitted possibilities that are not yet decisions.
- `docs/CHANGELOG.md`: add user-visible or repository-level changes after meaningful updates.
- `docs/WORK_VALIDATION_LEDGER.md`: update after terminal-guided command chunks, pasted terminal-output review, validation-heavy work, or operator-run steps.

Keep entries concise, dated when useful, and easy to scan.

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

## Later Connect GitHub or GitLab

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
