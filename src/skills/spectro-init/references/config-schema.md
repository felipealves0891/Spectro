# Spectro Init — Schema da configuração V1

The generated `.spectro/config.yaml` uses these required fields:

```yaml
version: "1.0"
paths:
  root: .spectro
  features: .spectro/features
  templates: .spectro/templates
  evidence: evidence
workflow:
  states: [pending, running, completed, failed, blocked, waiting_input, invalidated]
  retry_limit: 3
  fail_fast: true
  timeout_seconds: 900
  require_human_approval_for_scope_changes: true
  human_approval_stages: [plan, completed]
recovery:
  automatic_correction: false
  preserve_evidence: true
  invalidate_on_change: true
gates:
  required: []
  optional: []
  commands: {}
```

## Rules

- `version` is a string and must be supported by the initializer.
- All workflow states must be present in `workflow.states`.
- Paths are relative to the workspace and must remain within it.
- Gate commands are intentionally empty at initialization; no command is inferred or executed.
- `automatic_correction` defaults to `false` until the project explicitly configures a correction policy.
- Unknown keys may be preserved by later skills, but missing required keys make validation fail.
