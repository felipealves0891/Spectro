# Gate contract

`gates.json` must contain:

```json
{
  "schema_version": "1.0",
  "feature_id": "001-feature-name",
  "execution_id": "gate-2026-01-01T120000Z",
  "project_root": "C:\\workspace\\project",
  "code_revision": "git-or-local-revision",
  "config_hash": "sha256:...",
  "artifact_hashes": {},
  "started_at": "2026-01-01T12:00:00Z",
  "duration_ms": 0,
  "gates": [
    {
      "id": "GATE-001",
      "name": "build",
      "required": true,
      "status": "passed",
      "command": "...",
      "exit_code": 0,
      "duration_ms": 0,
      "diagnostics": [],
      "evidence": [
        ".spectro/features/001-feature-name/outputs/gate-20260101T120000Z/evidence/01-build.log"
      ],
      "output_directory": ".spectro/features/001-feature-name/outputs/gate-20260101T120000Z/build",
      "output_files": ["result.xml", "summary.json"],
      "output_file_count": 2
    }
  ],
  "result": "passed"
}
```

Allowed gate statuses are `passed`, `failed`, `blocked`, `error`, and `skipped`. Allowed aggregate results are `passed`, `failed`, `blocked`, and `error`.

`project_root` is required for new reports and contains the absolute directory
used as the working directory for every gate process in that execution. It is
validated as an absolute path; the directory does not need to remain available
when an archived report is validated.

For new reports, `output_directory` is the path relative to the project root
where the gate may write files. `output_files` contains paths relative to that
directory, and `output_file_count` must equal the number of listed files.
Evidence paths must be stored below
`.spectro/features/<feature>/outputs/<execution-id>/evidence/`. The control
artifacts `gates.json` and `state.json` remain directly under the feature
directory.
