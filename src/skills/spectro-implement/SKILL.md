---
name: spectro-implement
description: Implement approved Spectro tasks incrementally with behavior-focused tests, scope control, and progress tracking.
metadata:
  short-description: Implement Spectro tasks
---

# Spectro Implement

Use this skill when a feature has an approved `spec.md`, `plan.md`, and `tasks.md`.

## Inputs

- `.spectro/features/<feature-id>/spec.md`.
- `plan.md` and `tasks.md`.
- `.spectro/constitution.md` and project configuration.
- Current repository state and previous gate diagnostics, when present.

## Workflow

1. Inspect the workspace and preserve unrelated pre-existing changes.
2. Select the next approved task whose dependencies are complete; do not skip a prerequisite.
3. Read its requirements, completion criteria, expected tests, affected components, and risk.
4. Inspect the relevant files, implement the smallest coherent change, and add or update behavior-focused tests.
5. Run targeted checks, record modified files and results, and update task status.
6. Continue only while the change remains inside approved scope and the evidence supports progress.
7. Leave a clear diagnostic when blocked by a specification gap, planning defect, environment failure, or repeated implementation failure.

## Rules

- Do not overwrite unknown changes without authorization.
- Do not weaken, delete, or skip tests to make a gate pass.
- Do not change requirements or relax quality policies during implementation.
- Keep production and test changes traceable to task IDs.
- Use the repository's existing language, framework, formatting, and test conventions.
- Respect the configured retry limit; repeated identical failures require intervention.

## Completion

Report completed and remaining tasks, files changed, tests executed, known limitations, and whether the workspace is ready for `spectro-gates`.
