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

Keep entries concise, dated when useful, and easy to scan.

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

3. Read the required memory files from the start of this workflow.
4. Run:

```powershell
git status --short --branch
```

or:

```sh
git status --short --branch
```

5. Continue from `docs/PROJECT_STATE.md` and `docs/TODO.md`.
