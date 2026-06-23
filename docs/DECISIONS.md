# Decisions

This file records meaningful project decisions. Add a new entry when the project owner makes or approves a choice that affects architecture, tooling, workflow, dependencies, hosting, or long-term direction.

## Decision Log

### 2026-06-23: Commit and Push After Each Working Session

- Status: accepted
- Context: The owner wants repository state preserved at the end of each working session.
- Decision: Run `git add .`, commit with a clear self-explanatory message, and run `git push` after each working session.
- Consequence: Future sessions should expect recent work to be available from the configured remote. Non-routine remote operations still require explicit owner approval.

### 2026-06-23: Keep Repository Language-Neutral During Setup

- Status: accepted
- Context: The project type has not been decided.
- Decision: Do not add runtime dependencies, package managers, framework files, Docker files, devcontainers, or application features during setup.
- Consequence: The repository remains portable and low-commitment until the first implementation objective is chosen.

### 2026-06-23: Use Markdown Project Memory

- Status: accepted
- Context: Future Codex sessions need immediate project context.
- Decision: Maintain project memory in Markdown files under `docs/`, with `AGENTS.md` as the operating guide for AI sessions.
- Consequence: Memory is Git-native, easy to diff, and portable across Windows 11 and Debian Linux.

## Pending Decisions

- Project type
- Programming language and runtime
- Framework or no-framework direction
- Git hosting provider: GitHub or GitLab
- First implementation milestone
- Dependency installation policy after project type is chosen
