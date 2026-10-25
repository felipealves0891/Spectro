---
name: spectro-plan
description: Convert an approved Spectro specification into a technically grounded plan and traceable implementation tasks without changing production code.
metadata:
  short-description: Plan a Spectro feature
---

# Spectro Plan

Use this skill when `spec.md` has no unresolved blocking ambiguity and a feature needs an executable technical plan.

## Inputs

- `.spectro/features/<feature-id>/spec.md`.
- `clarifications.md`, when present.
- `.spectro/constitution.md` and `.spectro/config.yaml`, when present.
- Current source tree, build configuration, dependencies, and tests.

## Workflow

1. Verify that the specification is sufficiently clarified; stop if a blocking ambiguity remains.
2. Inspect the existing architecture, relevant modules, interfaces, persistence, build, test strategy, and local conventions.
3. Analyze created, modified, removed, migrated, and tested components, including regression risk.
4. Document the chosen solution, contracts, data flow, errors, persistence, concurrency, observability, and important alternatives.
5. Define validation for each acceptance criterion and relevant non-functional requirement.
6. Create `.spectro/features/<feature-id>/plan.md` and `tasks.md` from the project templates.
7. Give each task a unique `TASK-###` ID, requirement links, dependencies, affected components, completion criteria, expected tests, and risk.
8. Verify that every in-scope requirement maps to tasks and validation, with no dependency cycles or accidental scope.

## Rules

- Prefer patterns already used by the project.
- Do not implement production code.
- Proofs of concept are allowed only when explicitly bounded and needed for a technical decision.
- Record uncertainty and risks instead of hiding them in task wording.

## Completion

Report the plan and task paths, requirement coverage, task order, risks, validation strategy, and approval blockers.
