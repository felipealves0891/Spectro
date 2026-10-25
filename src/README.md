# Spectro — Guia de uso

O Spectro organiza o desenvolvimento de uma funcionalidade em seis fases rastreáveis:

`Specify → Clarify → Plan → Implement → Gates → Review`

Cada fase produz artefatos locais. O workflow só pode ser concluído quando os gates obrigatórios passam, a revisão é aprovada e as aprovações humanas configuradas foram registradas.

## Pré-requisitos

- PowerShell 5.1 ou PowerShell 7+.
- As ferramentas de build, análise e testes do projeto instaladas localmente.
- As skills disponíveis no agente consumidor. Neste repositório, elas ficam em `skills/`.

## Estrutura

```text
skills/
├── spectro-specify/
├── spectro-clarify/
├── spectro-plan/
├── spectro-implement/
├── spectro-gates/
└── spectro-review/

.spectro/
├── constitution.md
├── config.yaml
├── scripts/workflow.ps1
├── templates/
└── features/<feature-id>/
```

## 1. Configure os gates

Edite `.spectro/config.yaml` com os comandos reais do projeto:

```yaml
gates:
  required: [build, static-analysis, security, unit-tests, acceptance]
  optional: [integration-tests, performance]
  commands:
    build: "dotnet build --no-restore"
    static-analysis: "dotnet format --verify-no-changes"
    security: "dotnet list package --vulnerable"
    unit-tests: "dotnet test --no-build"
    integration-tests: "dotnet test --filter Category=Integration"
    performance: "dotnet test --filter Category=Performance"
    acceptance: "dotnet test --filter Category=Acceptance"
```

Comandos vazios ficam `blocked`; nunca são considerados aprovados.

## 2. Execute as fases

Escolha um identificador, por exemplo `001-login`, e use as skills na ordem:

1. `spectro-specify` — cria `spec.md` com requisitos e critérios de aceite.
2. `spectro-clarify` — resolve ambiguidades e registra decisões.
3. `spectro-plan` — cria `plan.md` e `tasks.md`.
4. `spectro-implement` — implementa tarefas e testes.
5. `spectro-gates` — executa validações locais.
6. `spectro-review` — revisa código, requisitos, testes e evidências.

Os artefatos ficam em:

```text
.spectro/features/001-login/
├── spec.md
├── clarifications.md
├── plan.md
├── tasks.md
├── gates.json
├── review.md
└── outputs/
    └── <execution-id>/
        ├── evidence/
        └── <gate>/
```

## 3. Controle o workflow

O controlador persistente fica em `.spectro/scripts/workflow.ps1`.

Consultar o estado:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action status `
  -FeatureId 001-login
```

Retomar uma execução interrompida:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action resume `
  -FeatureId 001-login
```

Avançar uma fase após os artefatos necessários estarem prontos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action transition `
  -FeatureId 001-login `
  -TargetPhase plan
```

## 4. Registre aprovações humanas

As fases que exigem aprovação são configuradas em `workflow.human_approval_stages`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action approve `
  -FeatureId 001-login `
  -ApprovalStage plan `
  -ApprovedBy "Nome do aprovador" `
  -Note "Plano revisado e aprovado"
```

## 5. Execute os gates

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action run-gates `
  -FeatureId 001-login
```

O resultado fica em `gates.json`. Os outputs dos gates e as evidências ficam em:

```text
.spectro/features/001-login/outputs/<execution-id>/
```

O diretório específico de cada gate é disponibilizado pela variável de
ambiente `SPECTRO_GATE_OUTPUT_DIR`.

Para validar um relatório existente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/spectro-gates/scripts/validate_gates.ps1 `
  -ReportPath .spectro/features/001-login/gates.json
```

## 6. Recupere falhas

Use `recover.ps1` para classificar uma falha, persistir o estado, controlar tentativas e invalidar evidências antigas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/spectro-gates/scripts/recover.ps1 `
  -FeatureId 001-login `
  -FailureCategory implementation-defect
```

Categorias disponíveis:

- `implementation-defect`
- `test-defect`
- `environment-failure`
- `specification-gap`
- `planning-defect`
- `needs-human-review`

Correções automáticas exigem um comando explícito:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/spectro-gates/scripts/recover.ps1 `
  -FeatureId 001-login `
  -FailureCategory environment-failure `
  -CorrectionCommand "docker compose up -d db" `
  -ResumeGates
```

O estado e o histórico ficam em `state.json` e `events.jsonl`. O limite padrão é de três tentativas por diagnóstico.

## 7. Prepare a review

Crie um pacote independente com diff, hashes e manifest:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/spectro-review/scripts/prepare_review.ps1 `
  -FeatureId 001-login
```

Valide a rastreabilidade:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/spectro-review/scripts/validate_traceability.ps1 `
  -FeatureId 001-login
```

A review deve produzir `.spectro/features/001-login/review.md`. Para criar uma tarefa de correção vinculada a um finding:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/spectro-review/scripts/create_remediation_task.ps1 `
  -FeatureId 001-login `
  -FindingId FINDING-001 `
  -Severity High `
  -Description "Corrigir validação de autorização" `
  -ReturnStage implement
```

## 8. Finalize

A finalização exige gates aprovados, `review.md` com decisão `approved` e as aprovações configuradas:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action approve `
  -FeatureId 001-login `
  -ApprovalStage completed `
  -ApprovedBy "Nome do aprovador"

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .spectro/scripts/workflow.ps1 `
  -Action finalize `
  -FeatureId 001-login
```

O relatório final será salvo em:

```text
.spectro/features/001-login/final-report.md
```

## Regras importantes

- Não altere requisitos para fazer testes passarem.
- Não remova ou enfraqueça testes com falha.
- Não trate gate não executado como aprovado.
- Alterações no código invalidam evidências afetadas.
- Alterações de especificação ou plano exigem revisão das fases posteriores.
- Findings `Critical` ou `High` não resolvidos impedem aprovação.
- Segredos não devem ser gravados em logs, evidências ou relatórios.
