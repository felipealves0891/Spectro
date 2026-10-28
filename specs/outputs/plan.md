# Plano técnico da centralização dos outputs dos gates

**Especificação de origem:** `specs/outputs/spec.md`  
**Versão do plano:** 1.0  
**Status:** Proposto  
**Skill afetado:** `spectro-gates`

## 1. Objetivo

Alterar a execução dos gates para criar e usar a estrutura:

```text
.spectro/features/<feature>/outputs/<execution-id>/
├── evidence/
├── <gate-1>/
├── <gate-2>/
└── ...
```

O diretório de trabalho dos comandos continuará sendo a raiz do projeto. A
pasta por gate será disponibilizada por `SPECTRO_GATE_OUTPUT_DIR`, enquanto os
logs de auditoria serão armazenados em `outputs/<execution-id>/evidence/`.

## 2. Diagnóstico atual

O runner atual:

- cria evidências em `.spectro/features/<feature>/evidence/<execution-id>/`;
- grava stdout/stderr no arquivo de evidência de cada gate;
- não cria uma pasta de output por execução ou por gate;
- não fornece um diretório de output ao comando;
- não registra inventário de outputs no `gates.json`.

A alteração deve preservar o comportamento de raiz do projeto já implementado
e migrar a localização das evidências para dentro de `outputs/<execution-id>/`.

## 3. Decisões técnicas

### 3.1 Estrutura e isolamento

- `outputsRoot = .spectro/features/<feature>/outputs`.
- `executionOutputDir = outputsRoot/<execution-id>`.
- `evidenceDir = executionOutputDir/evidence`.
- `gateOutputDir = executionOutputDir/<gate-name>`.
- Os nomes dos gates devem ser validados ou normalizados para impedir separadores
  de caminho, `..` e colisões entre diretórios.
- O `execution-id` já usado pelo runner será a chave de isolamento entre
  execuções.

### 3.2 Comunicação com o processo filho

O `run_gates.mjs` deve passar ao `run_gate.mjs`:

- o comando;
- a raiz do projeto como `WorkingDirectory`;
- o diretório do gate como `OutputDirectory`;
- o caminho do arquivo de evidência dentro de
  `outputs/<execution-id>/evidence/`.

O `run_gate.mjs` deve definir `SPECTRO_GATE_OUTPUT_DIR` no processo filho, antes
da execução do comando. O valor deve ser absoluto e específico do gate.

### 3.3 Captura e inventário

- stdout e stderr continuam sendo capturados pelo runner.
- O conteúdo capturado será gravado em
  `outputs/<execution-id>/evidence/<gate>.log`.
- Arquivos produzidos pelo comando dentro de `OutputDirectory` serão listados
  após a execução.
- O inventário deve conter caminhos relativos ao diretório do gate e ignorar
  links ou caminhos que escapem dele.
- O inventário deve ocorrer mesmo quando o comando falhar ou expirar.

### 3.4 Compatibilidade do relatório

Novos resultados devem adicionar a cada gate:

```json
{
  "output_directory": ".spectro/features/001-feature/outputs/gate-.../build",
  "output_files": ["result.xml", "summary.json"],
  "output_file_count": 2
}
```

`gates.json` e `state.json` permanecem diretamente na pasta da feature.
Relatórios antigos poderão continuar sendo aceitos pelo validador como legado,
mas relatórios novos devem exigir os campos de output.

## 4. Arquivos a alterar

### 4.1 `src/skills/spectro-gates/scripts/run_gates.mjs`

- Substituir a criação atual de `feature/evidence/<execution-id>` por
  `feature/outputs/<execution-id>`.
- Criar `evidence` dentro do diretório da execução.
- Criar o diretório específico de cada gate antes de iniciá-lo.
- Montar o caminho do log de evidência dentro de `outputs/<execution-id>/evidence`.
- Passar `OutputDirectory` ao runner individual.
- Após o runner retornar, coletar o inventário de arquivos do diretório do gate.
- Adicionar `output_directory`, `output_files` e `output_file_count` ao objeto
  do gate.
- Registrar caminhos de output relativos à raiz do projeto.
- Preservar outputs parciais para `failed`, `blocked` e `error`.

### 4.2 `src/skills/spectro-gates/scripts/run_gate.mjs`

- Adicionar o parâmetro obrigatório `OutputDirectory`.
- Validar e resolver esse diretório antes de criar o job.
- Definir `SPECTRO_GATE_OUTPUT_DIR` dentro do job.
- Garantir que o diretório exista antes da execução do comando.
- Manter `WorkingDirectory` como diretório atual do comando.
- Gravar stdout/stderr no caminho de evidência recebido, inclusive em timeout
  ou erro.
- Não considerar ausência de arquivos adicionais como falha.

### 4.3 `src/skills/spectro-gates/scripts/recover.mjs`

- Passar um diretório de output próprio para comandos de correção.
- Usar a mesma execução/feature para preservar a rastreabilidade da correção.
- Manter o log de correção dentro de `outputs/<execution-id>/evidence/` ou em
  um subdiretório de recuperação claramente identificado.

### 4.4 `src/skills/spectro-gates/scripts/validate_gates.mjs`

- Exigir os campos de output em relatórios novos.
- Validar que `output_directory` seja relativo à raiz do projeto e permaneça
  dentro de `.spectro/features/<feature>/outputs/`.
- Validar que `output_file_count` corresponda à quantidade de itens em
  `output_files`.
- Aceitar relatórios legados sem esses campos somente quando identificados como
  formato anterior, conforme a política de compatibilidade adotada.

### 4.5 `src/skills/spectro-gates/references/gate-contract.md`

- Atualizar o exemplo do contrato com os novos campos.
- Documentar o significado de `output_directory`, `output_files` e
  `output_file_count`.
- Documentar a localização de `evidence` dentro da execução de outputs.

### 4.6 `src/skills/spectro-gates/SKILL.md`

- Informar que outputs de comandos ficam em
  `.spectro/features/<feature>/outputs/<execution-id>/<gate>/`.
- Informar que evidências ficam em
  `.spectro/features/<feature>/outputs/<execution-id>/evidence/`.
- Explicar o uso de `SPECTRO_GATE_OUTPUT_DIR`.

## 5. Estratégia de testes

Criar um fixture temporário com dois gates, executado a partir de uma
subpasta:

- um comando grava `result.txt` em `$env:SPECTRO_GATE_OUTPUT_DIR`;
- um comando escreve stdout e stderr e falha;
- um comando expira, quando o teste de timeout for executado;
- duas execuções usam o mesmo `FeatureId`.

### Cenários obrigatórios

| ID | Cenário | Resultado esperado |
|---|---|---|
| T-OUTPUT-001 | Iniciar uma execução | `outputs/<execution-id>/` e `evidence/` existem antes do primeiro gate. |
| T-OUTPUT-002 | Gate grava arquivo pela variável de ambiente | Arquivo fica somente no diretório do gate. |
| T-OUTPUT-003 | Gate emite stdout/stderr | Log fica em `outputs/<execution-id>/evidence/`. |
| T-OUTPUT-004 | Gate falha | Outputs parciais e evidência são preservados. |
| T-OUTPUT-005 | Gate expira | Evidência e outputs parciais são preservados. |
| T-OUTPUT-006 | Dois gates | Cada gate possui diretório isolado. |
| T-OUTPUT-007 | Duas execuções | Nenhuma execução sobrescreve a outra. |
| T-OUTPUT-008 | Validar `gates.json` | Campos e inventário são aceitos pelo validador. |
| T-OUTPUT-009 | Caminho de escape | Output fora da pasta permitida gera diagnóstico e não é aprovado. |
| T-OUTPUT-010 | Relatório e estado | `gates.json` e `state.json` permanecem na raiz da feature. |

## 6. Sequência de implementação

1. Atualizar o contrato de `gates.json`.
2. Alterar `run_gate.mjs` para receber `output-directory` e definir a variável
   de ambiente.
3. Alterar `run_gates.mjs` para criar a nova árvore e inventariar outputs.
4. Atualizar `recover.mjs` para usar a nova estrutura.
5. Atualizar `validate_gates.mjs` e as regras de compatibilidade.
6. Atualizar `SKILL.md`.
7. Executar os cenários T-OUTPUT-001 a T-OUTPUT-010.
8. Verificar manualmente a árvore criada, o relatório, as evidências e o
   estado persistido.

## 7. Riscos e mitigação

### Risco: comandos existentes gravam outputs fora da variável fornecida

Mitigação: o diretório de trabalho permanece na raiz para compatibilidade, mas
o contrato documenta `SPECTRO_GATE_OUTPUT_DIR` como destino oficial. O runner
não deve mover arquivos arbitrários da raiz sem configuração explícita.

### Risco: outputs de um gate contaminarem outro

Mitigação: criar diretório exclusivo por gate e definir a variável de ambiente
individualmente em cada job.

### Risco: caminhos escaparem da pasta autorizada

Mitigação: resolver caminhos absolutos, verificar que são descendentes do
diretório do gate e registrar diagnóstico quando não forem.

### Risco: quebra de consumidores de relatórios antigos

Mitigação: manter leitura compatível para relatórios legados e exigir os novos
campos somente em relatórios gerados após a alteração.

## 8. Critério de conclusão

A alteração estará concluída quando os critérios `AC-GATES-OUTPUT-001` a
`AC-GATES-OUTPUT-010` forem atendidos, os cenários T-OUTPUT-001 a
T-OUTPUT-010 passarem e os gates continuarem executando na raiz do projeto,
sem perda de evidências, outputs parciais, timeout, fail-fast ou estado
persistido.
