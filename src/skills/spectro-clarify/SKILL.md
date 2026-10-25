---
name: spectro-clarify
description: Resolve blocking and major ambiguities in a Spectro specification, record decisions, and keep the consolidated spec consistent.
metadata:
  short-description: Clarify a Spectro specification
---

# Spectro Clarify

Use this skill after `spectro-specify` when a specification contains ambiguity, contradiction, or missing behavior that could change the solution.

## Inputs

- `.spectro/features/<feature-id>/spec.md`.
- `.spectro/constitution.md`, when present.
- Relevant documentation and prior developer answers.

## Workflow

1. Check completeness of inputs, outputs, errors, limits, security, persistence, concurrency, and performance expectations.
2. Identify each ambiguity and assign `Blocking`, `Major`, or `Minor` severity.
3. Resolve questions from existing project evidence when possible; do not ask the user to confirm facts already documented.
4. Ask concise grouped questions for decisions that require human input, including alternatives and impact when useful.
5. Record every decision in `.spectro/features/<feature-id>/clarifications.md` with an ID, question, decision, rationale, affected requirements, and date.
6. Update `spec.md` so it remains the single consolidated source of requirements.

## Rules

- Do not silently convert a hypothesis into an approved requirement.
- Do not keep contradictory versions of a requirement in `spec.md`.
- Minor questions may become explicit assumptions when safe; document them.
- Blocking questions without an answer leave the phase in `waiting_input` and prevent planning.

## Completion

Report resolved questions, remaining questions by severity, changed requirements, and whether any blocking ambiguity remains.
