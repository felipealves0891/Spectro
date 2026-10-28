# Spectro — Guia de uso

O Spectro organiza o desenvolvimento de uma funcionalidade em seis fases rastreáveis:

`Specify → Clarify → Plan → Implement → Gates → Review`

Cada fase produz artefatos locais. O workflow só pode ser concluído quando os gates obrigatórios passam, a revisão é aprovada e as aprovações humanas configuradas foram registradas.

## Pré-requisitos

- Node.js 22 LTS ou superior.
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
├── scripts/workflow.mjs
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

O controlador persistente fica em `.spectro/scripts/workflow.mjs`.

Consultar o estado:

```text
node .spectro/scripts/workflow.mjs \
  --action status \
  --feature-id 001-login
```

Retomar uma execução interrompida:

```text
node .spectro/scripts/workflow.mjs \
  --action resume \
  --feature-id 001-login
```

Avançar uma fase após os artefatos necessários estarem prontos:

```text
node .spectro/scripts/workflow.mjs \
  --action transition \
  --feature-id 001-login \
  --target-phase plan
```

## 4. Registre aprovações humanas

As fases que exigem aprovação são configuradas em `workflow.human_approval_stages`.

```text
node .spectro/scripts/workflow.mjs \
  --action approve \
  --feature-id 001-login \
  --approval-stage plan \
  --approved-by "Nome do aprovador" \
  --note "Plano revisado e aprovado"
```

## 5. Execute os gates

```text
node .spectro/scripts/workflow.mjs \
  --action run-gates \
  --feature-id 001-login
```

O resultado fica em `gates.json`. Os outputs dos gates e as evidências ficam em:

```text
.spectro/features/001-login/outputs/<execution-id>/
```

O diretório específico de cada gate é disponibilizado pela variável de
ambiente `SPECTRO_GATE_OUTPUT_DIR`.

### Saída esperada

O comando do gate não precisa produzir um formato específico: não é necessário
imprimir JSON, uma mensagem determinada ou qualquer outro marcador de sucesso.
O runner considera o código de saída do comando:

- código `0`: gate `passed`;
- código diferente de `0`: gate `failed`;
- timeout: gate `blocked`;
- erro do próprio runner ou resultado ilegível: gate `error`.

stdout e stderr são capturados no arquivo de evidência e usados nos diagnósticos
quando o gate falha, mas não são interpretados para decidir se o gate passou.
Se o comando precisar produzir arquivos, eles devem ser gravados em
`$env:SPECTRO_GATE_OUTPUT_DIR`; esses arquivos são apenas inventariados no
relatório.

O runner imprime no console o relatório completo em JSON e também grava esse
conteúdo em `.spectro/features/001-login/gates.json`. A execução retorna código
de saída `0` somente quando todos os gates obrigatórios passam. Em caso de
`failed`, `blocked` ou `error` em um gate obrigatório, o relatório ainda é
gravado, mas o processo retorna código `1`.

Exemplo reduzido de uma execução aprovada:

```json
{
  "schema_version": "1.0",
  "feature_id": "001-login",
  "execution_id": "gate-20261025T220000Z",
  "project_root": "C:/projetos/minha-api",
  "code_revision": "a1b2c3d",
  "started_at": "2026-10-25T22:00:00.0000000Z",
  "duration_ms": 18420,
  "gates": [
    {
      "id": "GATE-001",
      "name": "build",
      "required": true,
      "status": "passed",
      "command": "dotnet build --no-restore",
      "exit_code": 0,
      "duration_ms": 8120,
      "diagnostics": [],
      "evidence": [
        ".spectro/features/001-login/outputs/gate-20261025T220000Z/evidence/01-build.log"
      ],
      "output_directory": ".spectro/features/001-login/outputs/gate-20261025T220000Z/build",
      "output_files": [],
      "output_file_count": 0
    }
  ],
  "result": "passed"
}
```

Os valores de `execution_id`, hashes, duração e caminhos variam a cada
execução. Cada item em `gates` registra o comando, o código de saída, os
diagnósticos, o log de evidência e os arquivos produzidos pelo gate. Portanto,
um comando como `dotnet test`, `npm test` ou um script customizado pode manter
sua saída normal; basta retornar `0` ao concluir com sucesso e um valor
diferente de `0` ao detectar falha.

| Status do gate | Significado |
|---|---|
| `passed` | O comando terminou com código `0`. |
| `failed` | O comando terminou com código diferente de `0`. |
| `blocked` | O gate não pôde ser aprovado, por exemplo por comando vazio, timeout ou por fail-fast após uma falha obrigatória. |
| `error` | O runner não conseguiu executar ou interpretar o resultado do comando. |
| `skipped` | O gate foi registrado sem execução; deve permanecer visível no relatório. |

O campo raiz `result` pode ser `passed`, `failed`, `blocked` ou `error`. Gates
opcionais com falha ou bloqueio permanecem no relatório, mas não alteram o
resultado agregado; qualquer gate obrigatório nesses estados impede a
aprovação. Por padrão, o fail-fast bloqueia os gates seguintes após uma falha
ou bloqueio obrigatório. Para continuar executando os demais gates:

```text
node skills/spectro-gates/scripts/run_gates.mjs \
  --feature-id 001-login \
  --continue-on-failure
```

A árvore gerada fica semelhante a esta:

```text
.spectro/features/001-login/
├── gates.json
├── state.json
└── outputs/<execution-id>/
    ├── evidence/
    │   ├── 01-build.log
    │   └── 02-unit-tests.log
    ├── build/
    │   └── <arquivos produzidos pelo comando>
    └── unit-tests/
        └── <arquivos produzidos pelo comando>
```

`output_directory` e `output_files` são caminhos relativos à raiz do projeto.
Para criar arquivos de relatório, os comandos configurados devem usar o
diretório absoluto de `SPECTRO_GATE_OUTPUT_DIR`; assim, os outputs de um
gate não contaminam a execução de outro.

Para validar um relatório existente:

```text
node skills/spectro-gates/scripts/validate_gates.mjs \
  --report-path .spectro/features/001-login/gates.json
```

Em caso de sucesso, o validador imprime:

```text
Gate report is valid: .spectro/features/001-login/gates.json
```

e retorna código `0`. Um relatório inválido produz mensagens de erro e retorna
código `1`.

## 6. Recupere falhas

Use `recover.mjs` para classificar uma falha, persistir o estado, controlar tentativas e invalidar evidências antigas:

```text
node skills/spectro-gates/scripts/recover.mjs \
  --feature-id 001-login \
  --failure-category implementation-defect
```

Categorias disponíveis:

- `implementation-defect`
- `test-defect`
- `environment-failure`
- `specification-gap`
- `planning-defect`
- `needs-human-review`

Correções automáticas exigem um comando explícito:

```text
node skills/spectro-gates/scripts/recover.mjs \
  --feature-id 001-login \
  --failure-category environment-failure \
  --correction-command "docker compose up -d db" \
  --resume-gates
```

O estado e o histórico ficam em `state.json` e `events.jsonl`. O limite padrão é de três tentativas por diagnóstico.

## 7. Prepare a review

Crie um pacote independente com diff, hashes e manifest:

```text
node skills/spectro-review/scripts/prepare_review.mjs \
  --feature-id 001-login
```

Valide a rastreabilidade:

```text
node skills/spectro-review/scripts/validate_traceability.mjs \
  --feature-id 001-login
```

A review deve produzir `.spectro/features/001-login/review.md`. Para criar uma tarefa de correção vinculada a um finding:

```text
node skills/spectro-review/scripts/create_remediation_task.mjs \
  --feature-id 001-login \
  --finding-id FINDING-001 \
  --severity High \
  --description "Corrigir validação de autorização" \
  --return-stage implement
```

## 8. Finalize

A finalização exige gates aprovados, `review.md` com decisão `approved` e as aprovações configuradas:

```text
node .spectro/scripts/workflow.mjs \
  --action approve \
  --feature-id 001-login \
  --approval-stage completed \
  --approved-by "Nome do aprovador"

node .spectro/scripts/workflow.mjs \
  --action finalize \
  --feature-id 001-login
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
