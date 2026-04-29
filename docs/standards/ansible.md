# Ansible Standard

## Estrutura principal

- `ansible/inventories/<environment>/hosts.yml`
- `ansible/inventories/<environment>/group_vars/all.yml`
- `ansible/roles/<role>/tasks/main.yml`
- `ansible/roles/<role>/handlers/main.yml`
- `ansible/roles/<role>/templates/*.j2`

## Regras

- Prefira roles pequenas e focadas.
- Use `group_vars` para valores nao sensiveis por ambiente.
- Nao versione segredos em inventories ou vars.
- Use templates para configuracoes variaveis.
- Valide sintaxe antes de considerar um bloco pronto.

## Validacao minima

- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`

## Secrets

- Secrets devem entrar em runtime via script guiado.
- O script pode gerar arquivo temporario local fora do Git.
- O playbook deve falhar com mensagem clara se secret critico nao existir.
