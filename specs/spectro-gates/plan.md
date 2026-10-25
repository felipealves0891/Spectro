# Plano técnico da alteração no skill `spectro-gates`

**Especificação de origem:** `specs/spectro-gates/spec.md`  
**Versão do plano:** 1.0  
**Status:** Proposto  
**Escopo:** descobrir e usar a raiz absoluta do projeto ao executar todos os
comandos de gate

## 1. Objetivo do plano

Ajustar o fluxo de execução dos gates para que o diretório de trabalho seja
resolvido uma vez pelo runner principal e propagado ao runner de cada gate.
Com isso, comandos configurados com caminhos relativos terão comportamento
determinístico, mesmo quando o skill for invocado a partir de uma subpasta ou
da pasta onde o skill está instalado.

## 2. Diagnóstico e decisão técnica

O runner pode ser iniciado enquanto o diretório atual aponta para a pasta do
skill. Nesse caso, assumir o diretório atual como `ProjectRoot` faz com que
comandos relativos sejam executados fora do projeto. A raiz deve ser obtida a
partir do diretório inicial capturado antes de qualquer mudança de localização:
subir pelos ancestrais até encontrar `.spectro` e usar o diretório pai dessa
pasta. O `run_gate.ps1` continua precisando receber essa raiz para o
`Start-Job`, pois o job pode iniciar com um diretório diferente.

A solução será explícita e centralizada:

1. `run_gates.ps1` captura o diretório inicial imediatamente ao começar.
2. Se `ProjectRoot` não foi informado, procura `.spectro` no diretório inicial
   e nos ancestrais; a raiz é o diretório pai da primeira ocorrência.
3. `run_gates.ps1` resolve e valida a raiz absoluta.
4. O runner principal passa essa raiz ao `run_gate.ps1` em cada execução.
5. `run_gate.ps1` recebe um parâmetro `WorkingDirectory` obrigatório para as
   execuções iniciadas pelo runner principal.
6. Dentro do job, o runner faz `Set-Location` para o diretório recebido antes de
   criar/executar o scriptblock do comando.
7. O relatório registra o caminho absoluto efetivamente utilizado em
   `project_root`.

Não será feita alteração textual nos comandos configurados, nem será
prefixado cada comando com `Set-Location`. A mudança deve permanecer uma
responsabilidade do runner.

## 3. Arquivos a alterar

### 3.1 `src/skills/spectro-gates/scripts/run_gates.ps1`

- Capturar o diretório atual na primeira instrução executável, antes de
  qualquer `Set-Location` ou resolução relativa.
- Tornar `ProjectRoot` opcional para permitir a descoberta automática.
- Implementar a busca ascendente por `<diretório>/.spectro`, encerrando no
  diretório raiz do volume; usar o `Parent` da pasta encontrada como `$root`.
- Validar que `ProjectRoot` existe e é um diretório antes de iniciar a
  execução.
- Normalizar o caminho absoluto uma única vez.
- Passar `-WorkingDirectory $root` ao chamar `run_gate.ps1`.
- Adicionar `project_root = $root` ao objeto raiz de `gates.json`.
- Manter a resolução de `ConfigPath`, feature, evidências e artefatos baseada
  na mesma variável `$root`.
- Garantir que falha na validação da raiz ocorra antes da criação da execução
  ou de qualquer gate.

### 3.2 `src/skills/spectro-gates/scripts/run_gate.ps1`

- Adicionar parâmetro de diretório de trabalho, com validação de existência.
- Receber o valor no `Start-Job` junto com o comando.
- Executar `Set-Location -LiteralPath $WorkingDirectory` dentro do job antes
  da criação do scriptblock.
- Preservar timeout, captura de stdout/stderr, exit code, limpeza do job e
  estados atuais.
- Retornar erro estruturado se o diretório não puder ser usado.

### 3.3 `src/skills/spectro-gates/references/gate-contract.md`

- Documentar `project_root` como campo obrigatório no nível do relatório para
  novas execuções.
- Registrar que o caminho representa a raiz absoluta usada pelos processos dos
  gates.

### 3.4 `src/skills/spectro-gates/scripts/validate_gates.ps1`

- Verificar a presença e o formato de `project_root` em novos relatórios.
- Não exigir que o caminho exista quando o relatório estiver sendo validado
  após uma execução em ambiente removido; nesse caso, validar formato e
  coerência estrutural.
- Preservar todas as validações existentes.

### 3.5 `src/skills/spectro-gates/SKILL.md`

- Atualizar a instrução do runner para declarar que os comandos são executados
  na raiz do projeto.
- Explicar que `ProjectRoot` é a origem dos caminhos relativos dos comandos e
  das evidências.

## 4. Contrato de execução

O fluxo esperado será:

```text
invocação
  -> captura diretório inicial
  -> procura .spectro nos ancestrais
  -> usa o pai de .spectro como raiz do projeto
  -> resolve e valida raiz absoluta
  -> valida diretório
  -> carrega config e cria evidências
  -> run_gate(command, WorkingDirectory=ProjectRoot)
       -> Start-Job(command, ProjectRoot)
       -> Set-Location ProjectRoot
       -> executa comando sem reescrita
  -> grava gates.json.project_root
```

O diretório de trabalho deverá ser igual para todos os gates de uma mesma
execução. A pasta da feature continuará sendo usada para artefatos e evidências,
mas nunca como diretório de trabalho do comando.

## 5. Estratégia de testes

Os testes devem ser determinísticos e usar um projeto temporário com:

- um arquivo marcador na raiz;
- uma subpasta de onde o runner será invocado;
- um comando que leia o marcador com caminho relativo;
- um comando que registre `(Get-Location).Path` em sua saída;
- uma configuração com pelo menos dois gates.

### 5.1 Cenários obrigatórios

| ID | Cenário | Resultado esperado |
|---|---|---|
| T-ROOT-001 | Invocar de uma subpasta sem `-ProjectRoot` | O runner encontra `.spectro`, usa seu pai como raiz e o comando encontra o arquivo relativo. |
| T-ROOT-002 | Executar dois gates | Ambos registram o mesmo diretório absoluto. |
| T-ROOT-003 | Invocar a partir da pasta do skill e executar por `Start-Job` | O diretório observado é a raiz do projeto, não a pasta do skill. |
| T-ROOT-004 | Informar raiz inexistente | Falha explícita antes do primeiro gate. |
| T-ROOT-005 | Validar relatório gerado | `project_root` está presente e o contrato permanece válido. |
| T-ROOT-006 | Usar timeout e fail-fast | Comportamento anterior permanece inalterado. |
| T-ROOT-007 | Configurar comando vazio | Gate continua `blocked`, sem aprovação indevida. |
| T-ROOT-008 | Iniciar fora de qualquer projeto com `.spectro` ancestral | Falha explícita antes de criar ou executar gates. |

### 5.2 Regressão

- Executar a validação existente do contrato de `gates.json`.
- Executar o runner com configuração mínima existente.
- Verificar que os caminhos de evidência continuam relativos à raiz quando
  registrados no relatório.
- Verificar que a execução continua gerando `state.json` e atualizando o
  estado da fase Gates.

## 6. Sequência de implementação

1. Atualizar o contrato documentado do relatório.
2. Alterar `run_gates.ps1` para capturar o caminho inicial e descobrir a raiz pelo `.spectro`.
3. Alterar `run_gate.ps1` para aceitar e aplicar o diretório de trabalho.
4. Atualizar `validate_gates.ps1` conforme a obrigatoriedade de
   `project_root`.
5. Atualizar `SKILL.md` com o comportamento operacional.
6. Criar ou ajustar testes para os cenários T-ROOT-001 a T-ROOT-007.
7. Executar os testes e uma execução manual controlada a partir de uma
   subpasta.
8. Conferir `gates.json`, evidências e `state.json` antes de concluir.

## 7. Riscos e mitigação

### Risco: comando depende de um diretório diferente da raiz

Mitigação: a alteração formaliza o contrato; comandos que precisarem de outro
diretório deverão explicitar isso no próprio comando, sem alterar o diretório
de trabalho padrão dos gates.

### Risco: `.spectro` aninhado ou múltiplas ocorrências

Mitigação: usar a ocorrência ancestral mais próxima do diretório capturado e
documentar que ela define o projeto ativo. `ProjectRoot` explícito continua
disponível para cenários que exigem outra raiz.

### Risco: caminhos absolutos no relatório quebrarem consumidores

Mitigação: manter os caminhos de evidência existentes e adicionar apenas
`project_root`; atualizar o validador de forma compatível com relatórios
anteriores, caso o contrato permita retrocompatibilidade.

### Risco: `Set-Location` persistir fora do job

Mitigação: aplicar a mudança dentro do processo do job, que é isolado, e não
alterar o diretório do processo chamador.

### Risco: erro de resolução ocorrer depois de artefatos criados

Mitigação: validar `ProjectRoot` antes da criação de evidências, execução de
gates ou gravação de relatório.

## 8. Critério de conclusão

A alteração estará concluída quando os critérios `AC-GATES-ROOT-001` a
`AC-GATES-ROOT-006` forem atendidos, os cenários T-ROOT-001 a T-ROOT-007 forem
executados com sucesso e nenhuma regressão for observada no timeout, fail-fast,
classificação de status, evidências ou estado persistido.
