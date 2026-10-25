---
name: spectro-specify
description: Transform a feature request into a structured, testable Spectro specification without implementing code or inventing business requirements.
metadata:
  short-description: Create a Spectro specification
---

# Spectro Specify

Use this skill when a feature, bug, or behavior change needs to become a tracked Spectro specification.

## Inputs

- The user's feature or problem description.
- Existing repository context, when relevant.
- `.spectro/constitution.md`, when present.
- Existing documentation or a previous specification, when explicitly in scope.

## Workflow

1. Inspect only the project context needed to understand related behavior, conventions, and constraints.
2. Identify the problem, objective, users, requested behavior, explicit constraints, and known dependencies.
3. Write stable identifiers for functional requirements (`FR-###`), non-functional requirements (`NFR-###`), and constraints (`CON-###`).
4. Give every functional requirement at least one observable acceptance criterion (`AC-###`), preferably using Given/When/Then.
5. Record unknowns, conflicts, assumptions, included scope, and excluded scope.
6. Create or update `.spectro/features/<feature-id>/spec.md` using `.spectro/templates/specification.md` when available.

## Rules

- Describe what and why; do not choose implementation architecture prematurely.
- Do not implement code, install dependencies, or modify application files.
- Never turn an inferred business rule into a confirmed requirement.
- Preserve existing requirements when updating a specification unless the user explicitly changes them.
- A specification may contain open questions; unresolved blocking questions belong to `spectro-clarify`.

## Completion

Report the feature path, requirements and acceptance-criteria counts, open questions, scope boundaries, and whether the artifact is ready for clarification.
