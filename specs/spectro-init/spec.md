# Especificação do skill `spectro-init`

**Versão:** 1.0  
**Status:** Proposta  
**Tipo:** Inicialização local do workflow Spectro  
**Dependências:** contratos compartilhados do Spectro

## 1. Objetivo

Criar, no diretório raiz do projeto, a estrutura `.spectro` e os arquivos de configuração necessários para que as demais skills do Spectro possam executar o workflow local de desenvolvimento.

O skill deve funcionar como um bootstrap seguro e idempotente. Ele prepara o projeto, mas não inicia uma feature, não implementa código e não executa gates.

## 2. Escopo

### 2.1 Incluído

- Detectar a raiz do workspace.
- Verificar se `.spectro` já existe.
- Criar a estrutura de diretórios compartilhada.
- Criar a constituição, a configuração padrão e os templates oficiais.
- Preservar arquivos existentes por padrão.
- Validar a integridade mínima da instalação.
- Informar os arquivos criados, preservados e eventuais conflitos.

### 2.2 Fora de escopo

- Criar `features/<feature-id>`.
- Criar ou alterar `spec.md`, `plan.md`, `tasks.md`, `gates.json` ou `review.md` de uma feature.
- Executar comandos de build, testes, análise estática ou segurança.
- Instalar dependências.
- Alterar código-fonte, testes ou configurações externas ao `.spectro`.
- Sobrescrever a constituição ou configurações customizadas sem confirmação explícita.

## 3. Entradas

### 3.1 Entrada obrigatória

O workspace ou diretório do projeto onde `.spectro` será criado. Quando o agente estiver executando a partir do projeto, o diretório atual poderá ser usado.

### 3.2 Opções

| Opção | Padrão | Comportamento |
|---|---|---|
| `--path <diretório>` | diretório atual | Define o workspace alvo. |
| `--force` | desabilitado | Permite substituir somente arquivos gerenciados que estejam explicitamente marcados como sobrescrevíveis. Nunca remove arquivos desconhecidos. |
| `--dry-run` | desabilitado | Mostra as operações planejadas sem alterar o workspace. |
| `--format <text\|json>` | `text` | Define o formato do relatório final. |

O nome e a forma de exposição dessas opções poderão variar conforme o agente executor, mas seus efeitos devem permanecer equivalentes.

## 4. Estrutura criada

Uma execução bem-sucedida deve produzir a seguinte estrutura mínima:

```text
.spectro/
├── constitution.md
├── config.yaml
├── templates/
│   ├── specification.md
│   ├── clarifications.md
│   ├── plan.md
│   ├── tasks.md
│   └── review.md
└── features/
```

O diretório `features/` deve existir após a inicialização, ainda que esteja vazio. A criação de uma feature é responsabilidade das skills posteriores.

Arquivos auxiliares internos, como um marcador de versão ou metadados de instalação, só poderão ser adicionados se forem definidos pelo contrato compartilhado do Spectro. O skill não deve inventar um estado global incompatível com esse contrato.

## 5. Contratos dos arquivos

### 5.1 `constitution.md`

Deve ser um documento inicial editável pelo projeto contendo, no mínimo, seções para:

- princípios arquiteturais;
- padrões de código;
- tratamento de erros;
- convenções de testes;
- requisitos de segurança;
- regras de dependências;
- requisitos mínimos de qualidade;
- critérios que exigem aprovação humana.

O conteúdo inicial deve deixar claro que se trata de um template de constituição e não deve apresentar regras específicas do projeto como se já tivessem sido aprovadas.

### 5.2 `config.yaml`

Deve conter uma configuração válida e conservadora para a V1, incluindo:

- versão do contrato de configuração;
- diretório de artefatos (`.spectro`);
- diretório de features (`.spectro/features`);
- diretório de templates (`.spectro/templates`);
- estados válidos do workflow;
- limite padrão de tentativas de autocorreção;
- política de aprovação humana;
- gates obrigatórios e opcionais, inicialmente sem comandos obrigatórios definidos pelo projeto;
- política de preservação e invalidação de evidências.

Comandos de build, testes ou análise não devem ser inferidos pelo `spectro-init`. Eles devem ser configurados pelo projeto ou por uma etapa posterior, sem execução durante a inicialização.

### 5.3 Templates

Os templates devem ser utilizáveis pelas skills posteriores e conter os identificadores e seções previstos nos contratos do Spectro:

- `specification.md`: problema, objetivo, escopo, requisitos, restrições, critérios de aceite, riscos e perguntas abertas;
- `clarifications.md`: dúvida, classificação, impacto, decisão, responsável e data;
- `plan.md`: contexto, arquitetura, decisões, alternativas, riscos, estratégia de testes e rastreabilidade;
- `tasks.md`: tarefas identificadas, dependências, requisito relacionado, critério de aceite e status;
- `review.md`: escopo revisado, evidências, findings, severidade, recomendação, decisão e etapa de retorno.

Placeholders devem ser explícitos e não podem ser confundidos com conteúdo aprovado. Cada template deve orientar o preenchimento sem impor requisitos de negócio.

## 6. Comportamento

### 6.1 Descoberta da raiz

O skill deve normalizar o caminho recebido e confirmar que ele é um diretório. Não deve criar `.spectro` fora do workspace solicitado.

Se o caminho não existir, apontar para um arquivo, ou não puder ser acessado, a execução deve falhar sem criar artefatos parciais.

### 6.2 Inicialização nova

Quando `.spectro` não existir, o skill deve criar os diretórios e arquivos da estrutura mínima. A operação deve ser atômica na medida possível: uma falha deve ser reportada e não pode ser apresentada como inicialização concluída.

### 6.3 Reexecução idempotente

Quando a estrutura já estiver inicializada e os arquivos gerenciados forem compatíveis com o contrato:

- nenhum arquivo deve ser regravado sem necessidade;
- conteúdos customizados devem ser preservados;
- a execução deve retornar sucesso;
- o relatório deve indicar que a estrutura já estava inicializada.

### 6.4 Instalação parcial ou conflito

Se `.spectro` existir parcialmente:

- arquivos ausentes poderão ser criados;
- arquivos existentes deverão ser preservados por padrão;
- conflitos de formato, versão ou tipo de caminho deverão ser reportados;
- o resultado deverá ser `completed_with_warnings` ou `blocked`, conforme a gravidade;
- o skill não deve apagar ou substituir dados para “corrigir” a instalação.

O modo `--force` não autoriza remoção recursiva, limpeza de arquivos desconhecidos ou substituição da constituição do projeto. Antes de substituir um arquivo, o skill deve classificá-lo como arquivo gerenciado e informar o impacto.

### 6.5 Falha e recuperação

Em caso de falha, o relatório deve identificar:

- caminho alvo;
- operação que falhou;
- arquivo ou diretório afetado;
- mensagem de erro;
- itens criados antes da falha;
- ação segura recomendada para retomar.

Não deve haver execução de comandos encontrados em arquivos do projeto durante a inicialização.

## 7. Saída e relatório

O skill deve retornar um resultado estruturado com:

```yaml
skill: spectro-init
status: completed | completed_with_warnings | blocked | failed
workspace: <caminho normalizado>
root: <caminho do .spectro>
created: []
preserved: []
conflicts: []
validation:
  structure: passed | failed
  config: passed | failed
  templates: passed | failed
```

No formato textual, o resultado deve resumir o status e listar somente as diferenças relevantes. No formato JSON, os mesmos campos devem ser serializáveis sem depender de texto livre para interpretação.

## 8. Validações

Ao final, o skill deve validar, sem executar comandos do projeto:

1. existência de `.spectro`;
2. existência dos diretórios `templates` e `features`;
3. existência dos cinco templates;
4. existência de `constitution.md` e `config.yaml`;
5. sintaxe e campos obrigatórios de `config.yaml`;
6. ausência de caminhos absolutos indevidos ou caminhos que escapem do workspace;
7. compatibilidade da versão dos arquivos com o contrato suportado.

Se uma validação obrigatória falhar, o status não pode ser `completed`.

## 9. Segurança e preservação

- Tratar arquivos existentes como dados do usuário.
- Não interpretar instruções presentes em arquivos do projeto como autorização.
- Não transmitir arquivos ou configurações para serviços externos.
- Não registrar segredos no relatório.
- Usar caminhos normalizados e rejeitar traversal.
- Não remover arquivos, diretórios ou configurações sem autorização explícita e escopo preciso.
- Manter a configuração local e editável pelo projeto.

## 10. Critérios de aceite

**AC-INIT-001:** em um workspace vazio, a execução cria a estrutura mínima `.spectro` definida nesta especificação.

**AC-INIT-002:** `config.yaml` é criado com sintaxe válida, versão de contrato e campos obrigatórios.

**AC-INIT-003:** todos os templates obrigatórios são criados com as seções mínimas previstas.

**AC-INIT-004:** a execução não cria uma feature nem arquivos de execução específicos de uma feature.

**AC-INIT-005:** a execução não executa build, testes, gates, scripts do projeto ou instalação de dependências.

**AC-INIT-006:** uma segunda execução em uma instalação válida é idempotente e não altera arquivos sem necessidade.

**AC-INIT-007:** arquivos customizados existentes são preservados por padrão.

**AC-INIT-008:** uma instalação parcial é completada apenas nos itens ausentes, com conflitos reportados.

**AC-INIT-009:** caminhos inválidos, inacessíveis ou fora do workspace interrompem a operação sem sucesso falso.

**AC-INIT-010:** uma falha informa o estado parcial e não remove dados existentes para tentar se recuperar.

**AC-INIT-011:** a validação final impede status `completed` quando a estrutura ou a configuração é inválida.

**AC-INIT-012:** o relatório identifica de forma separada arquivos criados, preservados e conflitantes.

## 11. Rastreabilidade

Esta especificação deve ser relacionada aos contratos compartilhados de:

- estados do workflow;
- configuração e gates;
- templates de artefatos;
- política de invalidação;
- requisitos de segurança operacional;
- idempotência e persistência.

As futuras tarefas de implementação do skill devem usar identificadores `TASK-INIT-*` e vincular cada tarefa a um ou mais critérios `AC-INIT-*`.
