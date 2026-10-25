# Recovery contract

`state.json` records the resumable workflow state:

```json
{
  "schema_version": "1.0",
  "feature_id": "001-feature-name",
  "current_phase": "implement",
  "status": "waiting_input",
  "phases": {
    "gates": { "status": "invalidated", "execution_id": "..." }
  },
  "attempts": {
    "implementation-defect:GATE-004": 1
  },
  "invalidated_executions": ["gate-..."],
  "last_failure": {
    "category": "implementation-defect",
    "stage": "implement",
    "diagnostics": []
  },
  "updated_at": "2026-01-01T12:00:00Z"
}
```

Failure categories are `implementation-defect`, `test-defect`, `environment-failure`, `specification-gap`, `planning-defect`, and `needs-human-review`. Corrections require an explicit command; the recovery tool never invents or silently executes a code change.
