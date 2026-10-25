---
name: spectro-review
description: Review a Spectro implementation against its specification, plan, tests, gates, security expectations, and diff, then produce an actionable review report.
metadata:
  short-description: Review a Spectro implementation
---

# Spectro Review

Use this skill after required gates pass, or when a human requests an independent review of the implementation.

## Inputs

- `spec.md`, `clarifications.md`, `plan.md`, `tasks.md`.
- `gates.json` and its evidence.
- Current diff, changed files, and tests.
- `.spectro/constitution.md`, when present.

## Workflow

1. Verify that artifacts and gate evidence refer to the same valid code revision.
2. Prepare an independent review packet with `scripts/prepare_review.ps1`; do not rely on implementer explanations as evidence.
3. Run `scripts/validate_traceability.ps1` and inspect uncovered requirements, acceptance criteria, and validation links.
4. Review scope: omitted requirements, unauthorized changes, incomplete tasks, and accidental scope.
5. Review functional behavior, errors, boundaries, invariants, architecture, maintainability, performance, tests, and security.
6. Compare the specification, plan, tasks, code, tests, and gate results for inconsistencies.
7. Record each finding with ID, severity, category, location, evidence, impact, recommendation, and return stage.
8. Use `scripts/create_remediation_task.ps1` for accepted findings that require tracked work.
9. Create `.spectro/features/<feature-id>/review.md` with summary, artifacts examined, verified requirements, findings, residual risks, and final decision.

## Rules

- Review the result, not merely the fact that tests passed.
- Do not silently modify production code; corrections return to `spectro-implement` or an earlier stage.
- Treat unmeasured performance concerns as risks, not facts.
- Critical or High unresolved findings prevent approval.
- Use `approved`, `changes_requested`, `blocked`, or `needs_human_review` as the final decision.
- A review packet is an input snapshot, not approval evidence; the final report must still reason about behavior and risks.

## Completion

Report the review path, final decision, findings by severity, residual risks, and the stage required for any remediation.

## Review tooling

The helper scripts create an immutable local review context, validate traceability, and create remediation tasks without changing production code. Read `references/review-contract.md` before interpreting their JSON outputs.
