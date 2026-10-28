# Plano técnico da migração de scripts para Node.js

**Especificação de origem:** `specs/script-runtime/spec.md`  
**Versão do plano:** 1.0  
**Status:** Proposto  
**Runtime alvo:** Node.js 22 LTS ou superior

## 1. Objetivo do plano

Migrar os nove scripts internos atualmente implementados em PowerShell para
módulos `.mjs` executados por Node.js, preservando interfaces, contratos,
artefatos e diagnósticos. A implementação deve ser incremental e permitir
validar cada skill antes de remover os `.ps1` correspondentes.

O plano cobre apenas os artefatos das skills em `src` e a documentação
correspondente em `specs`. Não inclui a execução de comandos de projetos
consumidores nem a conversão de scripts encontrados em workspaces externos.

## 2. Diagnóstico atual

Existem scripts PowerShell ativos em:

- `src/skills/spectro-gates/scripts/`: quatro scripts;
- `src/skills/spectro-init/scripts/`: dois scripts;
- `src/skills/spectro-review/scripts/`: três scripts.

Os comportamentos que exigem maior cuidado na conversão são:

1. descoberta da raiz do projeto subindo pela árvore até `.spectro`;
2. resolução de caminhos relativa à raiz do projeto, e não à pasta do script;
3. parsing limitado de YAML usado pelos gates;
4. execução de comandos configurados pelo projeto;
5. timeout e captura de stdout/stderr em processo filho;
6. propagação de `SPECTRO_GATE_OUTPUT_DIR`;
7. geração e validação de JSON com códigos de saída;
8. hashes SHA-256, diff Git e preservação de arquivos;
9. comportamento idempotente e classificação de conflitos no init;
10. atualização de estado e invalidação de evidências na recuperação.

O repositório não possui manifesto Node.js. A primeira tarefa deve criar um
manifesto mínimo em `src/package.json`, sem dependências de runtime, com
`type: module` e `engines.node >=22`.

## 3. Decisões técnicas

### 3.1 Formato e invocação

- Cada script migrado será um módulo `.mjs` com entrypoint executável via
  `node <caminho-do-script>.mjs`.
- A lógica principal será exportável quando isso facilitar testes, mas a
  execução de CLI ocorrerá somente quando o arquivo for o entrypoint explícito.
- Argumentos serão tratados por um parser interno pequeno, sem dependência
  global. Opções com nomes equivalentes aos parâmetros atuais deverão ser
  documentadas em kebab-case, por exemplo `--project-root`.
- Erros operacionais serão enviados para stderr; JSON e relatórios previstos
  pelo contrato serão enviados para stdout.
- O exit code será definido por uma única função de encerramento para impedir
  divergência entre exceções e resultados estruturados.

### 3.2 Portabilidade de filesystem

- Usar `node:path`, `node:fs/promises` e `node:url` para resolver caminhos.
- Usar `pathToFileURL` ou `import.meta.url` para localizar assets da própria
  skill, sem assumir separadores `\\` ou `/`.
- Comparações de descendência devem usar caminhos absolutos normalizados e
  respeitar as regras de case sensitivity do sistema.
- Escritas de JSON/YAML e Markdown devem usar UTF-8 sem BOM, salvo contrato
  explícito em contrário.
- Links simbólicos, junctions e caminhos que escapem do diretório autorizado
  devem ser rejeitados ou inventariados como diagnóstico, conforme o contrato
  da skill.

### 3.3 Processos e timeout

- Usar `child_process.spawn` ou `execFile` com `shell` explicitamente definido
  somente quando o contrato de comando exigir interpretação de shell.
- O comando configurado deve continuar sendo uma entrada explícita da
  configuração; não haverá descoberta de comandos em `src`.
- O processo filho receberá `cwd` igual a `WorkingDirectory` e uma cópia do
  ambiente com `SPECTRO_GATE_OUTPUT_DIR` definido.
- stdout e stderr serão capturados separadamente, combinados no formato
  compatível com a evidência atual e gravados mesmo em falha ou timeout.
- Timeout deverá encerrar o processo e seus descendentes quando possível,
  retornando status `blocked` e exit code `124`, conforme o comportamento atual.

### 3.4 Parsing de configuração

- Na primeira migração, preservar o comportamento do parser textual existente
  para evitar ampliar o escopo para um parser YAML completo.
- Isolar o parser em módulo reutilizável, com testes para chaves escalares,
  listas e bloco `commands`.
- Se o contrato passar a exigir YAML completo, essa alteração será uma tarefa
  separada com dependência explícita e validação própria.

### 3.5 Regra de `src`

Os scripts dentro de `src` serão tratados como artefatos internos da skill,
não como comandos descobertos do projeto. Apenas os entrypoints referenciados
explicitamente pela própria skill poderão ser iniciados. A migração não deve
adicionar varredura, `require`/`import` dinâmico de arquivos arbitrários ou
execução baseada apenas na presença de um arquivo em `src`.

## 4. Arquivos previstos

### 4.1 Novos arquivos

- `src/package.json` — metadados do runtime, `type: module` e engine mínima.
- `src/skills/spectro-gates/scripts/*.mjs` — quatro entrypoints migrados.
- `src/skills/spectro-init/scripts/*.mjs` — dois entrypoints migrados.
- `src/skills/spectro-review/scripts/*.mjs` — três entrypoints migrados.
- Fixtures e testes no diretório de testes adotado pelo repositório, caso ainda
  não exista uma convenção, sem transformá-los em comandos distribuídos de
  `src`.

### 4.2 Arquivos a atualizar

- `src/skills/spectro-gates/SKILL.md` e referências de contrato/recuperação.
- `src/skills/spectro-init/SKILL.md` e referências de contrato/configuração.
- `src/skills/spectro-review/SKILL.md` e referências de contrato.
- `src/README.md`.
- `specs/spectro/plan.md`.
- `specs/spectro-gates/spec.md` e `specs/spectro-gates/plan.md`.
- `specs/spectro-init/plan.md`.
- `specs/outputs/plan.md`.
- Exemplos e comandos que mencionem `.ps1`, `powershell` ou `pwsh`.

### 4.3 Arquivos a remover ao final

Os nove `.ps1` só poderão ser removidos depois da validação de paridade. Se a
distribuição exigir uma transição, eles devem ser movidos para uma área de
legado fora dos pacotes ativos, acompanhados de aviso de descontinuação e sem
serem referenciados por nenhuma skill.

## 5. Tarefas de implementação

| ID | Tarefa | Dependências | Critérios relacionados |
|---|---|---|---|
| TASK-RUNTIME-001 | Criar `src/package.json`, declarar Node.js 22+, `type: module`, política de dependências e convenção de CLI. | — | AC-RUNTIME-001, AC-RUNTIME-002 |
| TASK-RUNTIME-002 | Criar utilitários compartilhados para argumentos, caminhos, JSON, UTF-8, hashes, exit codes e descoberta segura da raiz. | TASK-RUNTIME-001 | AC-RUNTIME-002, AC-RUNTIME-006, AC-RUNTIME-007 |
| TASK-RUNTIME-003 | Isolar e migrar o parser de configuração usado pelos gates, mantendo o subconjunto YAML atual. | TASK-RUNTIME-002 | AC-RUNTIME-004 |
| TASK-INIT-001 | Migrar `validate_spectro.ps1` para `validate_spectro.mjs`, preservando o modo objeto, validações e exit codes. | TASK-RUNTIME-002 | AC-RUNTIME-003 |
| TASK-INIT-002 | Migrar `init_spectro.ps1` para `init_spectro.mjs`, incluindo assets, dry-run, force, idempotência e chamada explícita do validador Node. | TASK-INIT-001 | AC-RUNTIME-003, AC-RUNTIME-006, AC-RUNTIME-007 |
| TASK-GATES-001 | Migrar `run_gate.ps1` para `run_gate.mjs`, incluindo `cwd`, ambiente, captura, timeout, evidência e JSON de resultado. | TASK-RUNTIME-002 | AC-RUNTIME-002, AC-RUNTIME-004 |
| TASK-GATES-002 | Migrar `run_gates.ps1` para `run_gates.mjs`, incluindo outputs por execução, inventário, fail-fast, hashes, relatório e chamada explícita do runner individual. | TASK-GATES-001, TASK-RUNTIME-003 | AC-RUNTIME-004, AC-RUNTIME-006, AC-RUNTIME-007 |
| TASK-GATES-003 | Migrar `validate_gates.ps1` para `validate_gates.mjs` e manter validação de relatórios novos e legados. | TASK-RUNTIME-002 | AC-RUNTIME-004 |
| TASK-GATES-004 | Migrar `recover.ps1` para `recover.mjs`, usando os runners Node e preservando tentativas, estado, invalidação e retomada. | TASK-GATES-001, TASK-GATES-002 | AC-RUNTIME-004 |
| TASK-REVIEW-001 | Migrar `prepare_review.ps1` para `prepare_review.mjs`, preservando manifest, hashes, Git diff e pacote de revisão. | TASK-RUNTIME-002 | AC-RUNTIME-005, AC-RUNTIME-006 |
| TASK-REVIEW-002 | Migrar `validate_traceability.ps1` para `validate_traceability.mjs`, preservando extração de IDs, relatório e diagnóstico de gaps. | TASK-RUNTIME-002 | AC-RUNTIME-005 |
| TASK-REVIEW-003 | Migrar `create_remediation_task.ps1` para `create_remediation_task.mjs`, preservando alocação de IDs, validações e escrita append-only. | TASK-RUNTIME-002 | AC-RUNTIME-005, AC-RUNTIME-006 |
| TASK-RUNTIME-004 | Atualizar skills, referências, README e specs para usar Node/.mjs e remover instruções PowerShell ativas. | TASK-INIT-002, TASK-GATES-004, TASK-REVIEW-003 | AC-RUNTIME-009 |
| TASK-RUNTIME-005 | Criar fixtures e testes de paridade para init, gates e review em workspace temporário. | TASK-INIT-002, TASK-GATES-004, TASK-REVIEW-003 | AC-RUNTIME-003, AC-RUNTIME-004, AC-RUNTIME-005, AC-RUNTIME-008 |
| TASK-RUNTIME-006 | Executar auditoria final, remover/isolar `.ps1` legados e validar que nenhum entrypoint ativo depende de PowerShell. | TASK-RUNTIME-004, TASK-RUNTIME-005 | AC-RUNTIME-001, AC-RUNTIME-009 |

## 6. Estratégia de testes

### 6.1 Testes unitários

- Parser de opções: defaults, obrigatoriedade, booleanos, valores inválidos e
  mensagens de erro.
- Caminhos: raiz, subpasta, separadores de plataforma, traversal, symlink e
  diretório inexistente.
- JSON e texto: UTF-8, saída em stdout, erros em stderr e ausência de BOM.
- Processos: exit code zero/não zero, stderr, timeout, processo inexistente e
  variável `SPECTRO_GATE_OUTPUT_DIR`.
- Inventário: arquivos regulares, links, caminhos fora do gate e contagem.

### 6.2 Testes de integração por skill

**Init**

- workspace vazio;
- segunda execução idempotente;
- conflito com arquivo customizado;
- `--force` somente em arquivo gerenciado;
- dry-run sem escrita;
- assets ausentes e workspace inválido.

**Gates**

- execução a partir da raiz e de subpasta;
- gate aprovado, falho, bloqueado por fail-fast e sem comando;
- stdout/stderr e evidência;
- arquivo produzido em `SPECTRO_GATE_OUTPUT_DIR`;
- timeout com output parcial;
- duas execuções sem sobrescrita;
- recuperação com e sem comando de correção;
- relatório válido, inválido e legado.

**Review**

- pacote de revisão com e sem commit/base ref;
- hashes e manifest;
- rastreabilidade completa e com gaps;
- criação de tarefa de remediação e rejeição de Finding duplicado.

### 6.3 Testes de portabilidade e segurança

- Rodar a suíte em Windows e, quando disponível, em ambiente POSIX.
- Verificar que nenhum teste chama `powershell`, `pwsh` ou arquivos `.ps1`.
- Verificar que um arquivo arbitrário em `src` não é executado.
- Verificar rejeição de traversal e de caminhos fora do workspace/output.
- Verificar que segredos de ambiente não aparecem em relatórios ou evidências.

## 7. Sequência de implementação

1. Implementar `TASK-RUNTIME-001` e `TASK-RUNTIME-002`.
2. Migrar e testar `spectro-init`.
3. Migrar `run_gate`, pois ele é a base de execução dos gates e da recuperação.
4. Migrar `run_gates`, o validador de relatórios e a recuperação.
5. Migrar os três scripts de `spectro-review`.
6. Atualizar a documentação e as specs de origem para eliminar referências
   operacionais ao PowerShell.
7. Executar a suíte completa e os testes de portabilidade.
8. Fazer a auditoria de referências e remover/isolar os `.ps1` somente após
   todos os critérios de aceite passarem.

## 8. Riscos e mitigação

### Risco: diferença de semântica entre PowerShell e Node ao executar comandos

Mitigação: centralizar a execução em `run_gate.mjs`, definir explicitamente
`cwd`, ambiente, shell e captura de streams, e testar comandos com stdout,
stderr, exit code e timeout.

### Risco: encerramento incompleto de processos em timeout

Mitigação: implementar encerramento do processo e descendentes conforme a
plataforma, registrar o timeout como `blocked` e preservar a evidência antes
de retornar.

### Risco: divergência de caminhos entre Windows e POSIX

Mitigação: nunca concatenar separadores manualmente; usar `node:path`, testar
case sensitivity e manter caminhos relativos nos relatórios.

### Risco: parser YAML textual aceitar configuração inválida

Mitigação: manter o comportamento atual na primeira etapa, cobrir suas regras
com testes e bloquear explicitamente estruturas não suportadas; não declarar
suporte a YAML completo sem parser adequado.

### Risco: regressão de contratos ou artefatos

Mitigação: comparar fixtures JSON e árvores de saída, validar cada skill por
etapa e só remover os `.ps1` após a auditoria final.

### Risco: execução indevida de artefatos em `src`

Mitigação: manter entrypoints explícitos, não fazer descoberta por varredura e
adicionar teste negativo que coloque um arquivo executável arbitrário em `src`.

## 9. Critério de conclusão

O plano será considerado implementado quando:

- os nove scripts ativos forem `.mjs` executáveis com Node.js 22+;
- não houver dependência operacional de PowerShell;
- os contratos e relatórios existentes permanecerem compatíveis;
- os testes unitários, de integração, segurança e portabilidade passarem;
- a documentação apontar somente para Node.js e `.mjs`;
- arquivos arbitrários em `src` não forem tratados como comandos;
- os `.ps1` antigos tiverem sido removidos ou isolados fora do pacote ativo,
  com a decisão registrada no histórico da alteração.

## 10. Rastreabilidade

| Grupo de requisitos | Tarefas principais | Evidência |
|---|---|---|
| FR-RUNTIME-001 a FR-RUNTIME-005 | TASK-RUNTIME-001/002, TASK-INIT-*, TASK-GATES-*, TASK-REVIEW-* | Execução dos entrypoints, fixtures e relatórios |
| FR-RUNTIME-006 | TASK-GATES-001/002, TASK-RUNTIME-004/005 | Configuração explícita e testes de comando |
| Segurança e regra de `src` | TASK-RUNTIME-002, TASK-RUNTIME-005/006 | Testes negativos e auditoria de referências |
| AC-RUNTIME-001/002 | TASK-RUNTIME-001, TASK-RUNTIME-006 | `package.json`, exit codes e busca final |
| AC-RUNTIME-003 | TASK-INIT-001/002, TASK-RUNTIME-005 | Fixtures de init |
| AC-RUNTIME-004 | TASK-GATES-001/002/003/004, TASK-RUNTIME-005 | Fixtures de gates/recovery |
| AC-RUNTIME-005 | TASK-REVIEW-001/002/003, TASK-RUNTIME-005 | Fixtures de review |
| AC-RUNTIME-006/007 | TASK-RUNTIME-002, TASK-RUNTIME-005 | Testes de cwd, traversal e não-execução |
| AC-RUNTIME-008/009 | TASK-RUNTIME-004/005/006 | Matriz de plataformas e auditoria documental |
