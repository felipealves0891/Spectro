# Workflow contract

The V1 controller is `.spectro/scripts/workflow.ps1` and persists feature state in:

```text
.spectro/features/<feature-id>/
├── state.json
├── events.jsonl
└── final-report.md
```

Supported actions:

```powershell
workflow.ps1 -Action status -FeatureId <id>
workflow.ps1 -Action resume -FeatureId <id>
workflow.ps1 -Action transition -FeatureId <id> -TargetPhase <phase>
workflow.ps1 -Action approve -FeatureId <id> -ApprovalStage <stage> -ApprovedBy <person>
workflow.ps1 -Action run-gates -FeatureId <id>
workflow.ps1 -Action finalize -FeatureId <id>
```

The controller never fabricates a specification, implementation, gate result, or review approval. Missing artifacts and missing human approvals block transitions. Historical events remain append-only in `events.jsonl`.
