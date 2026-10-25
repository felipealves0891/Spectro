# Plano técnico do skill `spectro-init`

**Especificação de origem:** `specs/spectro-init/spec.md`  
**Versão do plano:** 1.0  
**Status:** Proposto  
**Escopo:** implementar o bootstrap local da estrutura `.spectro`

## 1. Objetivo do plano

Implementar o skill `spectro-init` como um bootstrap local, seguro e idempotente para projetos Spectro.

Ao final, o agente deverá conseguir inicializar `.spectro` em um workspace vazio, completar instalações parciais sem destruir dados, preservar customizações e produzir um relatório determinístico sobre a operação.

O plano não inclui a implementação das demais skills nem a execução de comandos do projeto.

## 2. Decisões técnicas

### 2.1 Separação entre instrução e operação determinística

O pacote do skill será composto por:

```text
src/skills/spectro-init/
├── SKILL.md
├── references/
│   ├── init-contract.md
│   └── config-schema.md
├── scripts/
│   ├── init_spectro.ps1
│   └── validate_spectro.ps1
└── assets/
    ├── constitution.md
    ├── config.yaml
    └── templates/
        ├── specification.md
        ├── clarifications.md
        ├── plan.md
        ├── tasks.md
        └── review.md
```

O `SKILL.md` deverá orientar a descoberta do workspace, a escolha das opções, o tratamento de conflitos e a apresentação do resultado. Os scripts deverão concentrar operações repetitivas de filesystem, validação de caminhos, cópia condicional e geração do relatório.

Os arquivos em `assets/` serão tratados como conteúdo de distribuição. Eles não são comandos e não deverão ser executados.

### 2.2 PowerShell como runner local

Como o repositório já possui automações locais em PowerShell, o runner será implementado em PowerShell sem depender de ferramentas externas para criar diretórios, copiar arquivos ou comparar metadados.

A validação de YAML deverá usar o mecanismo disponível no ambiente do executor. Caso não exista parser YAML disponível, o script deve realizar apenas validações determinísticas compatíveis com o contrato definido e retornar `blocked` para validações que exigirem um parser ausente; não deve aceitar sintaxe inválida silenciosamente.

### 2.3 Política de arquivos gerenciados

Os arquivos gerados serão identificados por caminho relativo e tipo de artefato, não por exclusão ampla do diretório `.spectro`.

Arquivos gerenciados na V1:

- `constitution.md`;
- `config.yaml`;
- `templates/specification.md`;
- `templates/clarifications.md`;
- `templates/plan.md`;
- `templates/tasks.md`;
- `templates/review.md`.

Diretórios gerenciados:

- `.spectro`;
- `.spectro/templates`;
- `.spectro/features`.

Arquivos desconhecidos dentro de `.spectro` serão preservados e nunca serão removidos automaticamente.

### 2.4 Idempotência por conteúdo

Antes de gravar um arquivo, o runner deverá:

1. verificar se o destino existe;
2. verificar se é arquivo e não diretório;
3. comparar o conteúdo com o asset de origem, quando aplicável;
4. classificar o resultado como `created`, `preserved` ou `conflict`;
5. gravar somente quando o destino estiver ausente ou quando a substituição tiver sido autorizada pelo contrato.

O timestamp de arquivos não será usado para determinar mudança.

## 3. Contratos a consolidar antes da implementação

Há uma diferença entre a especificação do `spectro-init` e a configuração existente em `src/.spectro/config.yaml`: a especificação exige diretório de templates, estados válidos e políticas de preservação/invalidação, enquanto a configuração existente cobre principalmente workflow, recovery, gates e paths.

Antes da implementação, consolidar em `references/config-schema.md`:

- nome e tipo de cada campo obrigatório;
- valores válidos para status e estágios;
- defaults da V1;
- campos opcionais e compatibilidade futura;
- política para comandos de gates vazios;
- regras para paths relativos ao workspace;
- versão do contrato.

O `config.yaml` distribuído pelo `spectro-init` deverá ser a fonte do novo projeto e não deverá copiar automaticamente configurações específicas existentes no repositório.

## 4. Fluxo de execução

### 4.1 Preparação

1. Receber o workspace e as opções equivalentes a `--path`, `--force`, `--dry-run` e `--format`.
2. Normalizar o caminho e resolver o diretório absoluto.
3. Verificar que o workspace existe, é diretório e está acessível.
4. Resolver o destino `.spectro` dentro do workspace.
5. Rejeitar caminhos que escapem do workspace por traversal ou junção inválida.

### 4.2 Planejamento das operações

1. Montar a lista esperada de diretórios e arquivos.
2. Inspecionar cada destino sem alterar o workspace.
3. Classificar cada item como ausente, compatível, customizado, conflitante ou inválido.
4. Em `--dry-run`, produzir o relatório dessa classificação e encerrar sem escrita.
5. Em modo normal, bloquear conflitos que não possam ser resolvidos sem substituir dados.

### 4.3 Aplicação

1. Criar `.spectro`, `templates` e `features` quando ausentes.
2. Criar arquivos ausentes a partir dos assets.
3. Preservar arquivos existentes por padrão.
4. Aplicar `--force` apenas aos arquivos gerenciados cuja substituição seja permitida pelo contrato.
5. Nunca remover arquivos desconhecidos, diretórios não vazios ou configurações existentes.

Quando uma operação de escrita falhar, interromper a aplicação, registrar o progresso e retornar `failed`. O runner não deve tentar desfazer ou apagar dados automaticamente.

### 4.4 Validação e relatório

1. Validar estrutura, arquivos obrigatórios, configuração, templates e paths.
2. Classificar o resultado agregado:
   - `completed`: estrutura e validações aprovadas, sem conflitos bloqueantes;
   - `completed_with_warnings`: estrutura válida, mas há itens preservados ou avisos não bloqueantes;
   - `blocked`: conflito ou dependência de validação que impede afirmar a validade;
   - `failed`: erro operacional ou validação obrigatória reprovada.
3. Emitir formato textual ou JSON com os campos do contrato.

## 5. Tarefas de implementação

| ID | Tarefa | Dependências | Critérios de aceite |
|---|---|---|---|
| `TASK-INIT-001` | Consolidar o contrato de configuração e do relatório em `references/`. | Nenhuma | AC-INIT-002, AC-INIT-011, AC-INIT-012 |
| `TASK-INIT-002` | Criar os assets de constituição, configuração e cinco templates. | `TASK-INIT-001` | AC-INIT-002, AC-INIT-003 |
| `TASK-INIT-003` | Implementar resolução e validação segura do workspace. | `TASK-INIT-001` | AC-INIT-009 |
| `TASK-INIT-004` | Implementar classificação de destinos e modo `--dry-run`. | `TASK-INIT-002`, `TASK-INIT-003` | AC-INIT-006, AC-INIT-007, AC-INIT-008, AC-INIT-012 |
| `TASK-INIT-005` | Implementar criação condicional de diretórios e arquivos. | `TASK-INIT-004` | AC-INIT-001, AC-INIT-004, AC-INIT-010 |
| `TASK-INIT-006` | Implementar política de conflitos e comportamento de `--force`. | `TASK-INIT-004`, `TASK-INIT-005` | AC-INIT-007, AC-INIT-008, AC-INIT-010 |
| `TASK-INIT-007` | Implementar validação final da estrutura, YAML, templates e paths. | `TASK-INIT-001`, `TASK-INIT-002`, `TASK-INIT-005` | AC-INIT-002, AC-INIT-003, AC-INIT-009, AC-INIT-011 |
| `TASK-INIT-008` | Implementar relatório textual e JSON. | `TASK-INIT-004`, `TASK-INIT-006`, `TASK-INIT-007` | AC-INIT-010, AC-INIT-012 |
| `TASK-INIT-009` | Escrever `SKILL.md` com entradas, fluxo, limites e uso dos scripts. | `TASK-INIT-001`, `TASK-INIT-008` | AC-INIT-004, AC-INIT-005, AC-INIT-007 |
| `TASK-INIT-010` | Executar validação do pacote do skill e testes de comportamento em workspace temporário. | Todas | AC-INIT-001 a AC-INIT-012 |

## 6. Estratégia de testes

Os testes devem verificar comportamento observável em workspaces temporários e não apenas o texto dos arquivos.

### 6.1 Cenários obrigatórios

1. Workspace vazio: cria a estrutura completa.
2. Segunda execução: não altera arquivos compatíveis.
3. Arquivo customizado: preserva o conteúdo e relata `preserved` ou `conflict` conforme o caso.
4. Instalação parcial: cria somente itens ausentes.
5. `.spectro/templates` como arquivo: bloqueia sem apagar o arquivo.
6. Arquivo obrigatório onde deveria existir diretório: bloqueia.
7. `--dry-run`: não cria nem altera arquivos.
8. `--format json`: produz os campos estruturados do contrato.
9. Caminho inexistente ou apontando para arquivo: falha sem artefatos.
10. Caminho com traversal: rejeita a operação.
11. Configuração inválida: não retorna `completed`.
12. Arquivos desconhecidos em `.spectro`: preserva os arquivos.
13. Falha de escrita simulada: informa progresso parcial e não executa limpeza destrutiva.
14. Verificação de não-execução: nenhum comando definido em arquivos do projeto é chamado.

### 6.2 Testes de qualidade

- Validar o pacote `src/skills/spectro-init` com o validador do `skill-creator`, quando o pacote estiver implementado.
- Validar que todos os links e referências do `SKILL.md` apontam para recursos existentes.
- Verificar que os assets gerados contêm placeholders explícitos e os campos exigidos pelos contratos.
- Comparar duas execuções idempotentes por conteúdo e lista de mudanças.

## 7. Riscos e mitigação

| Risco | Impacto | Mitigação |
|---|---|---|
| Parser YAML ausente | Configuração pode não ser validada corretamente. | Declarar a dependência de validação; bloquear quando ela for obrigatória e indisponível. |
| `--force` substituir configuração customizada | Perda de decisões do projeto. | Limitar a arquivos gerenciados, registrar cada substituição e nunca remover desconhecidos. |
| Falha no meio da escrita | Instalação parcial. | Relatar progresso, permitir retomada idempotente e não fazer limpeza automática. |
| Contrato de configuração divergente | Skills posteriores podem interpretar campos de forma diferente. | Consolidar `config-schema.md` antes dos scripts e versionar o contrato. |
| Templates incompatíveis com skills existentes | Artefatos não consumíveis. | Mapear cada seção do template para a skill consumidora e testar geração mínima. |
| Confusão entre assets e comandos | Execução indevida de conteúdo distribuído. | Tratar `assets` apenas como dados e manter a regra explícita no `SKILL.md`. |

## 8. Critérios de conclusão do plano

O plano será considerado pronto para implementação quando:

- o schema de configuração e o relatório estiverem fechados;
- os assets necessários estiverem definidos;
- as tarefas estiverem vinculadas aos critérios de aceite;
- os cenários de teste cobrirem criação, idempotência, conflitos, segurança e falhas;
- não houver decisão pendente sobre sobrescrita de arquivos existentes;
- a implementação permanecer restrita ao pacote do skill e aos artefatos previstos em `src`.

## 9. Ordem de execução recomendada

1. `TASK-INIT-001` — contratos.
2. `TASK-INIT-002` — assets.
3. `TASK-INIT-003` — segurança de caminhos.
4. `TASK-INIT-004` e `TASK-INIT-005` — planejamento e aplicação.
5. `TASK-INIT-006` — conflitos.
6. `TASK-INIT-007` e `TASK-INIT-008` — validação e relatório.
7. `TASK-INIT-009` — instruções do skill.
8. `TASK-INIT-010` — validação integrada.
