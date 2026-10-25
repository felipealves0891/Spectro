# Especificação da alteração no skill `spectro-gates`

**Versão:** 1.0  
**Status:** Proposta  
**Tipo:** Execução de comandos de gate na raiz do projeto  
**Skill afetado:** `spectro-gates`

## 1. Objetivo

Garantir que todo comando configurado para um gate seja executado com a raiz do
projeto como diretório de trabalho, independentemente do diretório a partir do
qual o skill ou o runner seja invocado.

Isso deve tornar previsíveis comandos que usam caminhos relativos, arquivos de
configuração, manifests, soluções, projetos e scripts localizados na raiz do
projeto.

## 2. Escopo

### 2.1 Incluído

- Resolver a raiz do projeto uma única vez no início da execução.
- Usar essa raiz como diretório de trabalho de cada comando de gate.
- Aplicar a mesma raiz ao processo que executa o comando, inclusive quando o
  runner usar um job ou subprocesso.
- Preservar no relatório o comando original configurado e registrar a raiz
  efetiva da execução.
- Manter caminhos de evidência, configuração e artefatos resolvidos a partir da
  raiz do projeto.

### 2.2 Fora de escopo

- Alterar os comandos configurados pelo projeto.
- Fazer descoberta automática de outra raiz por heurística de cada gate.
- Executar gates dentro da pasta da feature.
- Alterar o contrato de estados ou o resultado agregado dos gates.

## 3. Comportamento requerido

1. O runner deve obter a raiz absoluta do projeto antes de carregar a
   configuração e criar os artefatos da execução.
2. Para cada gate, o processo filho deve iniciar com o diretório atual definido
   exatamente como essa raiz absoluta.
3. O diretório atual não deve ser herdado do diretório de onde o agente chamou o
   skill, da pasta `src/skills/spectro-gates` ou da pasta da feature.
4. O comando deve ser executado sem transformação de seus caminhos relativos.
   Assim, `dotnet test`, `npm test`, `pytest`, `./scripts/check.ps1` e comandos
   equivalentes devem resolver seus caminhos relativos a partir da raiz.
5. Se a raiz não puder ser resolvida, ou não existir, a execução deve falhar de
   forma explícita antes de iniciar qualquer gate, sem produzir aprovação.
6. A execução deve continuar respeitando timeout, fail-fast, captura de saída,
   limpeza de recursos e classificação de status já definidos pelo skill.

## 4. Entradas e interface

O parâmetro `ProjectRoot` continua sendo a entrada que define o projeto. Quando
não informado, deve representar o diretório atual no momento da invocação.

Após a resolução, o valor deve ser convertido para caminho absoluto e
normalizado. O restante da execução deve usar somente esse valor resolvido.

## 5. Saídas e evidências

O `gates.json` deve continuar compatível com o contrato existente e incluir, no
nível da execução, um campo `project_root` com o caminho absoluto utilizado.

Cada resultado de gate deve continuar contendo o comando configurado, status,
exit code, duração, diagnósticos e evidência. A evidência deve demonstrar a
execução com a raiz correta quando isso for necessário para diagnosticar o
gate.

## 6. Critérios de aceitação

**AC-GATES-ROOT-001:** ao iniciar o runner a partir de um diretório diferente da
raiz, um comando que leia um arquivo por caminho relativo deve localizar o
arquivo na raiz do projeto.

**AC-GATES-ROOT-002:** todos os gates da mesma execução devem receber o mesmo
diretório de trabalho absoluto.

**AC-GATES-ROOT-003:** a execução em job ou subprocesso não pode alterar o
diretório de trabalho efetivo para o diretório do script ou para o diretório de
invocação.

**AC-GATES-ROOT-004:** o relatório deve registrar `project_root` e manter os
caminhos de evidência relativos à raiz quando aplicável.

**AC-GATES-ROOT-005:** uma raiz inválida deve produzir erro explícito antes da
execução dos comandos e nunca resultar em `passed`.

**AC-GATES-ROOT-006:** o comportamento atual de timeout, fail-fast, códigos de
saída e bloqueio de comandos vazios deve permanecer inalterado.

## 7. Diretriz de implementação

O ajuste deve ser realizado no runner responsável por iniciar os comandos,
passando a raiz resolvida ao processo filho e definindo-a como diretório atual
antes da criação do scriptblock/comando. Não se deve corrigir o problema
prefixando manualmente cada comando com `Set-Location`, pois isso alteraria a
configuração do projeto e poderia produzir comportamentos diferentes entre
gates.

Os artefatos executáveis correspondentes deverão ser alterados em `src`; esta
especificação permanece em `specs`.
