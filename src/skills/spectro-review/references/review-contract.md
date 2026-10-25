# Review contract

Each review creates:

```text
.spectro/features/<feature-id>/reviews/<review-id>/
├── review-packet.md
├── manifest.json
├── diff.patch
└── traceability.json
```

`manifest.json` records the review ID, code revision, artifact hashes, and creation time. `traceability.json` records requirements, acceptance criteria, linked tasks, and missing links.

Findings in `review.md` must use:

| Field | Meaning |
|---|---|
| ID | Stable `FINDING-###` identifier |
| Severity | `Critical`, `High`, `Medium`, or `Low` |
| Category | Functional, architecture, test, security, performance, scope, or consistency |
| Location | File and line or artifact section when applicable |
| Evidence | Reproducible observation or command output |
| Impact | Consequence if unresolved |
| Recommendation | Concrete remediation |
| Return stage | `specify`, `clarify`, `plan`, `implement`, `gates`, or `human_review` |

Approval requires no unresolved `Critical` or `High` findings and no blocking traceability gaps.
