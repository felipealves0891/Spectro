# Spectro Init — Contrato operacional

## Managed paths

The initializer manages only these paths:

```text
.spectro/
├── constitution.md
├── config.yaml
├── templates/
│   ├── specification.md
│   ├── clarifications.md
│   ├── plan.md
│   ├── tasks.md
│   └── review.md
└── features/
```

Files not listed above are unknown and must be preserved.

## Result

```yaml
skill: spectro-init
status: completed | completed_with_warnings | blocked | failed
workspace: <normalized absolute path>
root: <normalized absolute .spectro path>
created: []
preserved: []
conflicts: []
validation:
  structure: passed | failed
  config: passed | failed
  templates: passed | failed
```

## Classification

- `created`: destination did not exist and was written, or a missing directory was created.
- `preserved`: destination already existed and was compatible or intentionally left untouched.
- `conflict`: destination has the wrong type, invalid content, incompatible contract, or custom content that would be replaced.

## Managed marker

Generated files begin with a format-appropriate managed marker:

```text
<!-- spectro-managed: true -->
```

YAML files use `# spectro-managed: true`.

`--force` can replace a conflicting regular file only when this marker is present. A project-owned file without the marker remains untouched and is reported as a conflict.

## Status rules

- `completed`: all mandatory validation passes and no blocking conflict exists.
- `completed_with_warnings`: mandatory validation passes and only non-blocking preserved items or warnings exist.
- `blocked`: a conflict or unavailable validation prevents asserting a valid installation.
- `failed`: an operational error or mandatory validation failure occurred.
