# AGENTS.md

Este arquivo e o ponto de entrada principal para qualquer agente de IA neste repositorio.

## 1. Leitura obrigatoria

Antes de qualquer proposta, analise ou execucao, leia nesta ordem:

1. `README.md`
2. `AGENTS.md`
3. `docs/standards/index.md`
4. Apenas os arquivos tematicos de `docs/standards/` relevantes para a tarefa

## 2. Objetivo do projeto

- Padronizar, automatizar e operar a implantacao do GLPI na SoEnergy.
- Preservar segregacao entre `staging` e `production`.
- Trabalhar com baixo custo de contexto, baixo desperdicio de tokens e baixa repeticao.
- Manter regras claras para rollback, auditoria e recuperacao.

## 3. Stack principal

- `Ubuntu`
- `Ansible`
- `Nginx`
- `PHP-FPM`
- `MariaDB`
- scripts operacionais em `bash`

## 4. Onde procurar cada padrao

- Commits, checkpoints e rollback: [commit-convention.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/commit-convention.md)
- Inventories, roles, templates e secrets de infraestrutura: [ansible.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/ansible.md)
- Scripts guiados, prompts, runtime secrets e comportamento interativo: [bash-scripts.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/bash-scripts.md)
- Seguranca, permissoes, TLS, LGPD e dados sensiveis: [security.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/security.md)
- Monitoração, exporters, alertas e thresholds: [monitoring.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/monitoring.md)
- Backup, restore, retencao e testes: [backup-restore.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/backup-restore.md)
- Comandos repetitivos aprovados: [repetitive-commands.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/repetitive-commands.md)
- Erros aprendidos e prevencoes: [learned-lessons.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/learned-lessons.md)
- Regras obrigatorias sem excecao: [mandatory-rules.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/mandatory-rules.md)

## 5. Quando consultar docs/standards

- Sempre consulte apenas o minimo necessario para a tarefa atual.
- Nao releia todos os arquivos se a tarefa tocar apenas um tema.
- Se o padrao ja existir, reutilize-o e nao o reescreva em outro arquivo.
- Se uma regra estiver ambigua, atualize o arquivo tematico correto em vez de duplicar no `AGENTS.md`.

## 6. Regras de commit

- O padrao oficial e `Conventional Commits`.
- Commits devem acontecer ao fechar um `bloco funcional validado`.
- Nao misture em um mesmo commit mudancas de objetivo, risco ou tecnologia diferentes.
- Se o bloco nao estiver isolavel ou validado, mantenha no working tree e nao comite ainda.
- Sempre use mensagem descritiva com `tipo(escopo): descricao`.

## 7. Como registrar novo aprendizado

- Se um erro se repetir ou causar retrabalho, registre em `learned-lessons.md`.
- Se um comando se repetir de forma segura e util, registre em `repetitive-commands.md`.
- Se uma regra se tornar obrigatoria para evitar risco ou desperdicio, promova para `mandatory-rules.md`.
- Nao trate memoria do agente como fonte de verdade; documente no repositorio.

## 8. Regras obrigatorias de atuacao

- Prefira alterar arquivos existentes antes de criar novos.
- Nao versione segredos.
- Dados sensiveis devem ser solicitados em runtime quando aplicavel.
- Preserve diretorios sensiveis fora da web root.
- Nao reescreva documentacao ja consolidada em outro markdown tematico.
- Sempre minimize chamadas, leitura desnecessaria de arquivos e uso excessivo de tokens.
- Ao identificar comando repetitivo, promova-o para padrao documentado.
- Ao identificar erro recorrente, documente causa, solucao e regra preventiva.

## 9. Validacao minima esperada

Quando aplicavel, valide o maximo possivel antes de considerar um bloco pronto para commit:

- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`
- `nginx -t`
- `php-fpm8.3 -t`
- testes de conectividade
- smoke tests

## 10. Referencias principais

- Visao geral do projeto: [README.md](/D:/Stefanini/SoEnergy/glpi-soenergy/README.md)
- Plano vivo de implantacao: [implementation-plan.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/implementation-plan.md)
- Catalogo de padroes: [docs/standards/index.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/index.md)
