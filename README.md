# Spectro

Spectro é um conjunto de skills para ampliar as capacidades do Codex com instruções, ferramentas e fluxos reutilizáveis para tarefas de desenvolvimento e automação.

## Estrutura do projeto

- `src/`: artefatos das skills. Os arquivos desta pasta são usados como conteúdo das skills e não devem ser tratados como comandos válidos.
- `specs/`: documentação, especificações e decisões de projeto.
- `tests/`: testes e validações do projeto.

## Como usar

1. Escolha ou crie uma skill dentro de `src/`.
2. Consulte a documentação correspondente em `specs/`.
3. Siga as instruções da skill para executar o fluxo desejado.
4. Execute os testes aplicáveis em `tests/` antes de finalizar alterações.

## Desenvolvimento

Para adicionar uma nova skill:

1. Defina seu objetivo e comportamento em `specs/`.
2. Implemente os artefatos necessários em `src/`.
3. Adicione ou atualize os testes em `tests/`.
4. Verifique se a documentação está atualizada e se a skill pode ser usada de forma clara e reproduzível.

Para modificar uma skill existente, atualize primeiro a especificação quando o comportamento esperado mudar; depois ajuste a implementação e os testes.

## Convenções

- Mantenha toda a documentação em `specs/`.
- Mantenha os artefatos de skills em `src/`.
- Não considere arquivos localizados em `src/` como comandos válidos.
- Prefira instruções simples, explícitas e fáceis de validar.
