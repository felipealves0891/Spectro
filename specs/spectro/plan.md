# Spectro — Plano de criação das skills

## Objetivo

Criar um workflow local de desenvolvimento orientado por especificações, composto por seis skills Agent Skills:

`Specify → Clarify → Plan → Implement → Gates → Review`

O processo deverá preservar artefatos, estado, evidências e rastreabilidade entre requisitos, tarefas, código, testes e decisões.

## 1. Contratos compartilhados

Antes das skills, definir a base do workflow:

```text
.agents/skills/
.spectro/
├── constitution.md
├── config.yaml
├── templates/
│   ├── specification.md
│   ├── plan.md
│   ├── tasks.md
│   └── review.md
└── features/
```

Também devem ser definidos:

- Estados: `pending`, `running`, `completed`, `failed`, `blocked`, `waiting_input` e `invalidated`.
- Formato de `state.json` e `gates.json`.
- Convenções de IDs: `FR`, `NFR`, `CON`, `AC`, `TASK`, `GATE` e `FINDING`.
- Regras de hashes, versões, evidências e invalidação.
- Limite de tentativas e critérios de aprovação humana.

## 2. Skills

### `spectro-specify`

Transforma uma solicitação em `spec.md`.

- Identificar problema, objetivo, usuários, restrições e dependências.
- Separar requisitos funcionais, não funcionais e restrições.
- Criar critérios de aceite observáveis.
- Registrar ambiguidades sem inventar requisitos.
- Delimitar escopo, premissas e exclusões.
- Não modificar código nem instalar dependências.

### `spectro-clarify`

Resolve ambiguidades da especificação.

- Classificar dúvidas como `Blocking`, `Major` ou `Minor`.
- Fazer perguntas objetivas e explicar impactos relevantes.
- Registrar decisões em `clarifications.md`.
- Atualizar `spec.md` como fonte consolidada.
- Bloquear o avanço quando uma decisão obrigatória estiver ausente.

### `spectro-plan`

Cria `plan.md` e `tasks.md`.

- Inspecionar arquitetura, dependências, build e testes existentes.
- Avaliar impacto, compatibilidade e riscos.
- Documentar solução, contratos e alternativas importantes.
- Associar requisitos a tarefas verificáveis.
- Definir estratégia de testes e dependências sem ciclos.
- Não implementar código de produção.

### `spectro-implement`

Executa as tarefas aprovadas.

- Trabalhar incrementalmente por tarefa.
- Preservar alterações preexistentes não relacionadas.
- Criar ou atualizar testes comportamentais.
- Registrar arquivos alterados e progresso.
- Respeitar o escopo do plano.
- Encaminhar falhas de especificação ou planejamento para a etapa apropriada.

### `spectro-gates`

Executa as validações locais e gera `gates.json`.

Ordem padrão:

1. Build.
2. Análise estática.
3. Segurança.
4. Testes unitários.
5. Testes de integração.
6. Performance, quando aplicável.
7. Acceptance.

Gates obrigatórios reprovados bloqueiam o workflow. A execução deve registrar comandos, versões, duração, diagnósticos e evidências.

### `spectro-review`

Revisa a implementação contra os artefatos anteriores e produz `review.md`.

Deve avaliar escopo, requisitos, arquitetura, testes, segurança, performance, consistência e riscos de regressão. Findings devem conter severidade, evidência, impacto, correção recomendada e etapa de retorno.

Decisões possíveis:

- `approved`
- `changes_requested`
- `blocked`
- `needs_human_review`

## 3. Ordem de implementação

1. Definir contratos de artefatos e estados.
2. Criar constituição, configuração e templates.
3. Criar `spectro-specify`.
4. Criar `spectro-clarify`.
5. Criar `spectro-plan`.
6. Criar `spectro-implement`.
7. Criar `spectro-gates`.
8. Criar `spectro-review`.
9. Executar validação integrada com uma feature fictícia.

A ordem reduz retrabalho porque cada skill posterior depende dos contratos produzidos pelas anteriores.

## 4. Organização dos recursos

- Manter cada `SKILL.md` focado no propósito, entradas, saídas, invariantes e limites da skill.
- Colocar schemas, políticas e procedimentos extensos em `references/`.
- Usar `scripts/` para operações determinísticas e repetitivas, especialmente nos gates.
- Evitar duplicar o README inteiro nas skills.
- Manter a invocação automática habilitada por padrão.

Estrutura inicial sugerida para os gates:

```text
spectro-gates/
├── SKILL.md
├── references/
│   ├── gate-contract.md
│   └── evidence-format.md
└── scripts/
    ├── run_gate.ps1
    └── validate_gates.py
```

## 5. Roadmap

### V0 — Fluxo manual

- Seis skills.
- Templates.
- Estado persistido.
- Execução manual.
- Sem autocorreção automática.

### V0.1 — Gates executáveis — implementada

- Build, análise estática, testes unitários e integração.
- Evidências estruturadas.
- Configuração por projeto.

Implementação entregue:

- `skills/spectro-gates/scripts/run_gates.ps1` para executar a sequência configurada.
- `skills/spectro-gates/scripts/run_gate.ps1` para timeout, captura de saída e exit code.
- `skills/spectro-gates/scripts/validate_gates.ps1` para validar relatórios.
- `.spectro/config.yaml` com gates obrigatórios/opcionais e comandos configuráveis.
- Evidências por execução em `.spectro/features/<feature-id>/evidence/`.

### V0.2 — Recuperação — implementada

- Classificação de falhas.
- Retorno à etapa apropriada.
- Limite de tentativas.
- Invalidação de artefatos.
- Retomada após interrupção.

Implementação entregue:

- `skills/spectro-gates/scripts/recover.ps1` para classificar falhas, persistir `state.json`, controlar tentativas e executar correções explicitamente autorizadas.
- `skills/spectro-gates/references/recovery-contract.md` com o contrato do estado persistido.
- `run_gates.ps1` agora atualiza o estado da fase Gates.
- Execuções anteriores permanecem armazenadas e são marcadas como invalidadas após uma recuperação.
- O limite padrão de três tentativas bloqueia o workflow quando não há progresso.

### V0.3 — Review avançado — implementada

- Rastreamento completo de requisitos.
- Findings estruturados.
- Revisão independente.
- Encaminhamento de correções.

Implementação entregue:

- `prepare_review.ps1` cria um pacote independente com diff, manifest e hashes.
- `validate_traceability.ps1` verifica cobertura de requisitos, critérios de aceite e tarefas.
- `create_remediation_task.ps1` cria tarefas `TASK-REV-###` vinculadas a findings.
- `review-contract.md` e template de review estruturam findings e decisões.

### V1 — Workflow completo — implementada

- Orquestração das seis fases.
- Retomada confiável.
- Gates configuráveis.
- Política de aprovação humana.
- Relatório final auditável.

Implementação entregue:

- `.spectro/scripts/workflow.ps1` para status, retomada, transições, aprovações, execução de gates e finalização.
- `.spectro/references/workflow-contract.md` com os comandos e contratos da orquestração.
- Estado persistido em `state.json` e histórico append-only em `events.jsonl`.
- Transições protegidas por artefatos, gates aprovados e aprovações humanas configuradas.
- `final-report.md` com decisão, hashes, gates, revisão e referências de auditoria.

## 6. Validação

Para cada skill:

- Executar `quick_validate.py` do `skill-creator`.
- Verificar frontmatter, nome e descrição.
- Testar com uma feature fictícia em workspace isolado.
- Confirmar os arquivos de saída.
- Verificar rastreabilidade entre requisitos, tarefas, testes e evidências.
- Confirmar que falhas retornam à etapa correta.
- Confirmar que alterações invalidam resultados antigos.

## 7. Localização implementada

As skills foram criadas em `skills/` porque `.agents/` está disponível apenas para leitura neste workspace. A estrutura `.spectro/` é usada para configuração, templates, estado e artefatos do workflow.

Quando o agente consumidor exigir `.agents/skills/`, o conteúdo de `skills/` deverá ser instalado ou copiado para essa localização por um processo de empacotamento com permissão de escrita.
