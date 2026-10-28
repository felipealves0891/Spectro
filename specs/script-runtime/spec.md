# Especificação da migração de scripts para Node.js

**Versão:** 1.0  
**Status:** Proposta  
**Tipo:** Alteração de runtime dos scripts internos  
**Escopo:** skills Spectro distribuídas em `src`

## 1. Objetivo

Substituir PowerShell por Node.js como runtime dos scripts internos das skills
Spectro, mantendo os contratos funcionais, os formatos de relatório, os
estados do workflow, a captura de evidências e as regras de segurança já
definidos nas especificações existentes.

A alteração deve permitir que o workflow seja executado em ambientes Windows,
Linux e macOS sem depender de `powershell.exe` ou `pwsh`.

## 2. Escopo

### 2.1 Incluído

- Reescrever os scripts `.ps1` internos como módulos JavaScript executados por
  Node.js.
- Padronizar a extensão dos scripts migrados para `.mjs`.
- Atualizar `SKILL.md`, referências, planos e exemplos que apontem para
  PowerShell ou para arquivos `.ps1`.
- Preservar argumentos, códigos de saída, arquivos gerados, mensagens de erro,
  timeouts, isolamento de diretórios e contratos JSON/YAML existentes.
- Documentar a versão mínima de Node.js e a forma oficial de invocação.
- Adicionar testes de comportamento para execução normal, falhas, timeout,
  caminhos inválidos e execução a partir de diretórios diferentes.

### 2.2 Fora de escopo

- Alterar os contratos de negócio das skills ou o fluxo `Specify → Review`.
- Alterar comandos configurados pelo projeto, como `npm test`, `dotnet test`
  ou `pytest`.
- Converter scripts pertencentes ao projeto consumidor.
- Instalar Node.js automaticamente.
- Fazer descoberta ou execução automática de arquivos encontrados em `src`.

## 3. Inventário da migração

Os seguintes artefatos devem ser convertidos, preservando seus nomes lógicos e
substituindo `.ps1` por `.mjs`:

| Skill | Arquivos atuais | Arquivos alvo |
|---|---|---|
| `spectro-gates` | `run_gates.ps1`, `run_gate.ps1`, `recover.ps1`, `validate_gates.ps1` | `run_gates.mjs`, `run_gate.mjs`, `recover.mjs`, `validate_gates.mjs` |
| `spectro-init` | `init_spectro.ps1`, `validate_spectro.ps1` | `init_spectro.mjs`, `validate_spectro.mjs` |
| `spectro-review` | `prepare_review.ps1`, `validate_traceability.ps1`, `create_remediation_task.ps1` | `prepare_review.mjs`, `validate_traceability.mjs`, `create_remediation_task.mjs` |

Arquivos `.ps1` não devem permanecer como implementações ativas após a
migração. Caso sejam mantidos temporariamente para referência, devem estar
fora do pacote distribuído e claramente marcados como legado.

## 4. Requisitos funcionais

**FR-RUNTIME-001:** cada script interno deve ser iniciado com `node` e retornar
exit code determinístico para sucesso, falha, bloqueio e erro de validação.

**FR-RUNTIME-002:** os scripts devem aceitar os mesmos parâmetros e preservar
seus significados. A interface pode mudar de sintaxe PowerShell para opções
POSIX/Node, mas a documentação deve mostrar a nova forma de uso.

**FR-RUNTIME-003:** os scripts devem resolver caminhos de forma independente do
diretório em que o arquivo do script está localizado. O diretório de trabalho
do projeto deve continuar sendo explícito e não pode ser inferido da pasta de
`src`.

**FR-RUNTIME-004:** operações de filesystem, processos filhos, timeout,
captura de stdout/stderr, serialização e validação devem usar APIs nativas do
Node.js ou dependências declaradas e versionadas.

**FR-RUNTIME-005:** a execução deve produzir os mesmos artefatos e contratos
existentes, incluindo `state.json`, `gates.json`, evidências, relatórios,
status e diagnósticos.

**FR-RUNTIME-006:** comandos do projeto devem continuar sendo executados
somente quando vierem da configuração ou de uma ação explicitamente
autorizada pelo workflow.

## 5. Runtime e dependências

- O runtime oficial é Node.js 22 LTS ou superior; a execução deve rejeitar
  versões incompatíveis com diagnóstico acionável.
- A execução deve funcionar sem módulos globais instalados.
- Dependências externas, se necessárias, devem ser declaradas em um manifesto
  do pacote e ter versões fixadas ou uma faixa controlada.
- A implementação deve preferir APIs nativas para não criar uma dependência
  equivalente a um shell específico.
- O launcher/documentação deve usar `node caminho/do/script.mjs`; não deve
  depender de associação de extensão, `npm exec`, `npx` ou política de execução
  do PowerShell.

## 6. Segurança e regra sobre `src`

Os arquivos em `src` são artefatos de distribuição das skills e não são, por
si só, comandos válidos do projeto consumidor. Nenhum runner deve varrer `src`,
interpretar arquivos encontrados ali ou executá-los por convenção de nome.

Um script interno só pode ser executado quando:

1. for o entrypoint definido pela própria skill;
2. tiver sido selecionado pelo fluxo da skill correspondente; e
3. receber entradas e caminhos validados pelo contrato aplicável.

A migração não pode ampliar permissões de execução, permitir traversal, aceitar
comandos concatenados implicitamente ou expor segredos em logs. Caminhos devem
ser normalizados, e operações fora do workspace ou dos diretórios de output
permitidos devem ser rejeitadas.

## 7. Compatibilidade

- Relatórios produzidos antes da migração devem continuar legíveis quando os
  contratos existentes preveem compatibilidade legada.
- A mudança de runtime deve ser identificável no relatório ou metadado de
  execução, sem alterar o schema já consumido por outras etapas.
- Mensagens podem ser reescritas para remover terminologia PowerShell, mas
  devem manter diagnóstico, severidade e status equivalentes.
- Documentação e exemplos não devem instruir o usuário a chamar `.ps1`,
  `powershell` ou `pwsh` para executar o workflow migrado.

## 8. Critérios de aceite

**AC-RUNTIME-001:** nenhum script ativo das skills inventariadas depende de
PowerShell ou possui extensão `.ps1`.

**AC-RUNTIME-002:** cada entrypoint migrado executa com `node` e retorna os
exit codes documentados em cenários de sucesso e falha.

**AC-RUNTIME-003:** `spectro-init` mantém criação idempotente, preservação de
arquivos, validação e relatório equivalentes ao contrato atual.

**AC-RUNTIME-004:** `spectro-gates` mantém diretório de trabalho, timeout,
captura de stdout/stderr, `SPECTRO_GATE_OUTPUT_DIR`, outputs por execução e
`gates.json` equivalentes ao contrato atual.

**AC-RUNTIME-005:** `spectro-review` mantém preparação de evidências,
validação de rastreabilidade e criação de tarefas de remediação.

**AC-RUNTIME-006:** executar a partir da raiz do projeto, de uma subpasta ou
de outro diretório não altera a resolução dos recursos da skill nem grava fora
dos caminhos autorizados.

**AC-RUNTIME-007:** arquivos presentes em `src` que não sejam entrypoints
explicitamente selecionados não são executados nem tratados como comandos.

**AC-RUNTIME-008:** os testes verificam Windows e, quando o ambiente permitir,
um sistema POSIX, sem depender de sintaxe específica de PowerShell.

**AC-RUNTIME-009:** toda documentação do repositório aponta para os arquivos
`.mjs` e para a invocação oficial com Node.js.

## 9. Estratégia de testes

1. Validar a versão do Node.js e a ausência de dependências globais.
2. Executar testes unitários para normalização de caminhos, argumentos,
   códigos de saída, serialização e classificação de erros.
3. Executar testes de integração para init, gates e review em workspace
   temporário.
4. Verificar sucesso, falha de comando, timeout, diretório inacessível,
   arquivo parcialmente criado e recuperação.
5. Comparar os artefatos gerados pelo runner Node.js com os contratos e
   fixtures existentes, sem exigir igualdade textual de mensagens.
6. Fazer uma busca final por `.ps1`, `powershell` e `pwsh` em documentação e
   código ativo; cada ocorrência restante deve ser justificada como histórico
   ou referência de migração.

## 10. Ordem de implementação

1. Fixar o contrato de runtime e a versão mínima de Node.js.
2. Migrar utilitários e validações compartilhadas, se existirem.
3. Migrar `spectro-init`.
4. Migrar `spectro-gates`, incluindo timeout, processos filhos e outputs.
5. Migrar `spectro-review`.
6. Atualizar `SKILL.md`, referências, planos e exemplos.
7. Executar a suíte de testes e a busca de referências PowerShell.
8. Remover ou isolar os `.ps1` legados somente após confirmar a paridade dos
   contratos.

## 11. Resultado esperado

Ao final, o Spectro terá um único runtime de scripts internos baseado em
Node.js, com comportamento e contratos preservados, documentação consistente e
sem tratar artefatos arbitrários em `src` como comandos executáveis.
