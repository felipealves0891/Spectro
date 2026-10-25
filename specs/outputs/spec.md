# Especificação da alteração de outputs do skill `spectro-gates`

**Versão:** 1.0  
**Status:** Proposta  
**Tipo:** Centralização dos outputs dos gates  
**Skill afetado:** `spectro-gates`

## 1. Objetivo

Garantir que todos os arquivos produzidos pelos comandos dos gates sejam
armazenados dentro de:

```text
.spectro/features/<feature>/outputs/
```

A mudança deve evitar que outputs de build, testes, análise, segurança ou
outros gates sejam espalhados pela raiz do projeto, pela pasta do skill ou por
outras features.

## 2. Escopo

### 2.1 Incluído

- Criar a pasta `outputs` da feature antes da execução dos gates.
- Disponibilizar o caminho absoluto dessa pasta para cada comando executado.
- Direcionar para `outputs` os arquivos de saída gerados pelo runner e pelos
  comandos quando o projeto usar o caminho fornecido pelo skill.
- Manter os outputs de features diferentes isolados.
- Preservar outputs entre execuções para auditoria, sem sobrescrever arquivos de
  execuções anteriores.
- Registrar no relatório os caminhos dos outputs produzidos.

### 2.2 Fora de escopo

- Mover `gates.json` ou `state.json`, que continuam sendo artefatos de controle
  diretamente em `.spectro/features/<feature>/`.
- Alterar o diretório de trabalho dos comandos, que continua sendo a raiz do
  projeto conforme a especificação de execução na raiz.
- Apagar outputs anteriores automaticamente.
- Reescrever comandos existentes para descobrir ou modificar seus próprios
  caminhos de saída.

## 3. Estrutura esperada

Uma execução deverá produzir uma estrutura equivalente a:

```text
.spectro/features/<feature>/
├── gates.json
├── state.json
└── outputs/
    └── <execution-id>/
        ├── evidence/
        │   ├── build.log
        │   ├── static-analysis.log
        │   └── ...
        ├── build/
        ├── static-analysis/
        ├── security/
        ├── unit-tests/
        ├── integration-tests/
        ├── performance/
        └── acceptance/
```

O diretório `outputs/` deve ser criado dentro da pasta da feature antes do
primeiro gate. Cada execução deve possuir uma subpasta própria em
`outputs/<execution-id>/`, contendo `evidence/` e os diretórios dos gates.
Somente diretórios correspondentes aos gates executados precisam ser criados
dentro da execução. O identificador da execução deve impedir colisões entre
execuções da mesma feature.

## 4. Comportamento requerido

1. O runner deve resolver a pasta da feature e criar, antes do primeiro gate,
   `.spectro/features/<feature>/outputs/<execution-id>/`.
2. Cada gate deve receber um diretório de output próprio, por exemplo
   `outputs/<execution-id>/unit-tests/`.
3. A execução deve possuir o diretório
   `outputs/<execution-id>/evidence/`, onde serão preservados os registros
   necessários para auditoria.
4. Cada gate deve possuir evidência própria dentro de
   `outputs/<execution-id>/evidence/`.
5. O caminho absoluto do diretório do gate deve ser disponibilizado pela
   variável de ambiente `SPECTRO_GATE_OUTPUT_DIR` durante a execução do
   comando.
5. O diretório de trabalho do comando deve continuar sendo a raiz do projeto;
   a variável de ambiente é o mecanismo para indicar onde os arquivos de saída
   devem ser gravados.
6. A saída textual capturada pelo runner, incluindo stdout e stderr, deve ser
   armazenada no diretório do gate dentro de `outputs`.
7. Se o comando falhar, expirar ou produzir erro de infraestrutura, seus
   outputs parciais devem ser preservados.
8. Um comando que não produza arquivos não deve ser tratado como falha por esse
   motivo; o diretório do gate ainda deve existir e o resultado deve registrar
   que nenhum arquivo adicional foi produzido.
9. Falha ao criar ou acessar a pasta de outputs ou de evidências deve produzir
   status `error` ou
   `blocked`, conforme a classificação existente, e nunca `passed`.
10. Caminhos fornecidos ao comando por configuração devem permanecer sob o
   diretório do gate. O runner não deve permitir que um caminho de output
   configurado escape da pasta da feature por `..` ou por caminho absoluto,
   quando o caminho for controlado pelo runner.

## 5. Relatório e evidências

O `gates.json` deve continuar em `.spectro/features/<feature>/gates.json` e
passar a registrar, para cada gate:

- `output_directory`: caminho relativo à raiz do projeto para a pasta do gate;
- `output_files`: lista dos arquivos produzidos, com caminhos relativos ao
  diretório do gate;
- `output_file_count`: quantidade de arquivos registrados.

Os logs de stdout/stderr capturados pelo runner devem ser incluídos em
`output_files`. As evidências de auditoria devem ser registradas em
`outputs/<execution-id>/evidence/`, separadas dos outputs dos comandos em
`outputs/<execution-id>/<gate>/`.

## 6. Compatibilidade e segurança

- A execução de comandos continua ocorrendo na raiz do projeto.
- `SPECTRO_GATE_OUTPUT_DIR` não deve conter segredos nem credenciais.
- O inventário de arquivos deve ignorar links ou caminhos que apontem para fora
  da pasta do gate e registrar um diagnóstico de segurança.
- Outputs de uma feature não podem ser reutilizados silenciosamente por outra
  feature.
- Relatórios antigos sem os novos campos poderão ser validados como legados,
  mas novas execuções devem sempre preencher os campos de output.

## 7. Critérios de aceitação

**AC-GATES-OUTPUT-001:** após iniciar uma execução, a pasta
`.spectro/features/<feature>/outputs/<execution-id>/` existe antes do primeiro
gate.

**AC-GATES-OUTPUT-002:** após iniciar uma execução, a pasta
`.spectro/features/<feature>/outputs/<execution-id>/evidence/` existe antes do
primeiro gate.

**AC-GATES-OUTPUT-003:** cada gate executado possui um diretório próprio dentro
da pasta da execução.

**AC-GATES-OUTPUT-004:** cada gate executado possui evidência registrada em
`outputs/<execution-id>/evidence/`.

**AC-GATES-OUTPUT-005:** um comando que grava um arquivo em
`$env:SPECTRO_GATE_OUTPUT_DIR` produz o arquivo no diretório correto da
feature, sem alterar o diretório de trabalho na raiz do projeto.

**AC-GATES-OUTPUT-006:** stdout e stderr capturados são preservados dentro do
diretório de output do respectivo gate, inclusive em caso de falha ou timeout.

**AC-GATES-OUTPUT-007:** `gates.json` registra `output_directory`,
`output_files` e `output_file_count` para cada gate.

**AC-GATES-OUTPUT-008:** outputs e evidências de duas execuções consecutivas da mesma
feature não são sobrescritos.

**AC-GATES-OUTPUT-009:** falha na criação ou acesso do diretório de outputs
ou evidências
impede que o gate seja considerado aprovado.

**AC-GATES-OUTPUT-010:** `gates.json` e `state.json` permanecem diretamente na
pasta da feature e não são movidos para `outputs`.

## 8. Diretriz de implementação

O ajuste deve ser realizado nos runners de gates, criando o diretório por
execução e por gate, definindo `SPECTRO_GATE_OUTPUT_DIR` no processo filho,
capturando stdout/stderr nesse diretório e inventariando os arquivos ao final
do gate. O diretório de trabalho do processo deve continuar sendo controlado
pela alteração já implementada para a raiz do projeto.

Os artefatos executáveis correspondentes deverão ser alterados em `src`; esta
especificação permanece em `specs`.
