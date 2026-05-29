# Relatório do contrato de ambiente

## Fonte oficial

- `config/.env.example` (template oficial versionado do projeto)

## Arquivos reais analisados

- `config/.env.example` (template baseline versionado)
- `config/development.env` (não encontrado)
- `config/staging.env` (não encontrado)
- `config/production.env` (não encontrado)
- `.env` (não encontrado)

## Arquivos criados/atualizados

- `.env.sync.yml` (criado)
- `docs/env-sync-contract-report.md` (criado)
- `docs/manual/pt-br/appendices/command-reference.md` (atualizado)
- `docs/manual/en/appendices/command-reference.md` (atualizado)

## Arquivos preservados

- `config/.env.example` (preservado)
- `config/development.env` (não encontrado)
- `config/staging.env` (não encontrado)
- `config/production.env` (não encontrado)
- `.env` (não encontrado)

## Variáveis documentadas

| Chave | Política | Obrigatória | Segredo | Observação |
|---|---|---:|---:|---|
| PRODUCT_NAME | managed | sim | não | baseline estável do produto |
| CUSTOMER_DISPLAY_NAME | protected | sim | não | rótulo de cliente por ambiente |
| ENVIRONMENT_NAME | protected | sim | não | identidade de ambiente |
| TOPOLOGY_APP_ALIAS | protected | sim | não | alias de inventário |
| TOPOLOGY_APP_HOST | protected | sim | não | endpoint de host |
| TOPOLOGY_DB_ALIAS | protected | sim | não | alias de inventário |
| TOPOLOGY_DB_HOST | protected | sim | não | endpoint de host |
| NETWORK_DATABASE_APP_ACCESS_HOST | protected | sim | não | origem de grant DB |
| NETWORK_DATABASE_ACCESS_MODE | review_required | sim | não | muda exposição de rede |
| NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS | review_required | não | não | lista de origem sensível a topologia |
| GLPI_VERSION | review_required | sim | não | troca de release |
| GLPI_DOMAIN | protected | sim | não | endpoint público |
| WEB_SERVER_TYPE | review_required | sim | não | muda pacotes/templates |
| DATABASE_NAME | protected | sim | não | schema de dados |
| DATABASE_USER | protected | sim | sim | credencial de acesso |
| DATABASE_PASSWORD | protected | sim | sim | segredo obrigatório |
| DATABASE_MANAGED_ADMIN_PASSWORD | protected | não | sim | segredo opcional de fallback |
| DATABASE_ROOT_PASSWORD | protected | não | sim | obrigatório apenas em self_hosted |
| WEB_HTTP_PORT | review_required | sim | não | impacto em conectividade |
| WEB_HTTPS_PORT | review_required | sim | não | impacto em TLS/rede |
| TLS_MODE | review_required | sim | não | fluxo de certificados |
| MONITORING_MYSQLD_EXPORTER_USER | protected | sim | sim | credencial do exporter |
| MONITORING_MYSQLD_EXPORTER_PASSWORD | protected | não | sim | obrigatório apenas em self_hosted |
| OPERATIONS_TIMEZONE | review_required | sim | não | impacto em logs e cron |
| RESOURCE_PROFILE_ACTIVE | review_required | sim | não | tuning operacional |

## Variáveis sensíveis

- `DATABASE_USER`
- `DATABASE_PASSWORD`
- `DATABASE_MANAGED_ADMIN_PASSWORD`
- `DATABASE_ROOT_PASSWORD`
- `MONITORING_MYSQLD_EXPORTER_USER`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD`

## Variáveis com revisão manual

- `NETWORK_DATABASE_ACCESS_MODE`: altera exposição de rede e regras de firewall/grant.
- `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS`: depende da topologia e da malha de rede do ambiente.
- `GLPI_VERSION`: altera versão da release com risco funcional/operacional.
- `WEB_SERVER_TYPE`: muda engine web e templates aplicados.
- `WEB_HTTP_PORT`: pode exigir ajustes de firewall/proxy/health checks.
- `WEB_HTTPS_PORT`: pode exigir ajustes de TLS/firewall/proxy.
- `TLS_MODE`: altera pré-requisitos e fluxo operacional de certificados.
- `OPERATIONS_TIMEZONE`: afeta cron, logs e janelas operacionais.
- `RESOURCE_PROFILE_ACTIVE`: altera parâmetros de tuning de runtime.

## Variáveis usadas no código mas ausentes no `.env.example`

- Usando `config/.env.example` como fonte oficial desta execução: **não foram encontradas variáveis usadas em `scripts/lib/render_product_config.py` ausentes do template**.

## Variáveis presentes nos arquivos reais mas ausentes no `.env.example`

- Não aplicável no momento porque não há arquivos reais de ambiente disponíveis em `config/` para comparação nesta execução.

## Ambiguidades

- `config/.env.example` tem 119 chaves totais, mas apenas 25 chaves ativas (descomentadas).
- Há 55 chaves usadas no renderer que estão comentadas/inativas no baseline e, por compatibilidade operacional com `env-sync.py`, não entraram neste contrato inicial.
- As chaves opcionais comentadas devem ser cobertas em uma evolução futura do contrato (ou com expansão da estratégia de source para incluir opcionalidade comentada).
- `.env.example` encontrado: sim.
- Classificação sugerida de `.env.example`: **template oficial versionado** (não é arquivo real por ambiente).
- Ação recomendada para `.env.example`: **manter**.

## Decisões tomadas na execução dos próximos passos

- Ambiguidades revisadas e decisão operacional aplicada: manter o contrato com as 25 chaves ativas para compatibilidade direta com `scripts/env-sync.py` no modo atual de parsing.
- Revisão das 9 chaves `review_required`: **concluída**; todas possuem `reason`, `impact` e `validation`.
- Execução de `env-sync` por ambiente esperado:
  - `config/development.env`: não encontrado.
  - `config/staging.env`: não encontrado.
  - `config/production.env`: não encontrado.
  - `config/.env.example`: executado em `report`, `exit code 2` com `DATABASE_PASSWORD` ausenta/vazia no template baseline.

## Validações executadas

- Validação sintática YAML de `.env.sync.yml` com `python3` e `yaml.safe_load`: **OK**.
- Validação de campos obrigatórios por chave (`description`, `required`, `policy`): **OK**.
- Cobertura de chaves ativas de `config/.env.example` no contrato: **25/25**.
- Execução `env-sync` em modo `report` (sem apply):
  - `python3 scripts/env-sync.py --source config/.env.example --target config/.env.example --rules .env.sync.yml --mode report --no-color`
  - Resultado: `exit code 2` (diferença esperada por `required missing` em `DATABASE_PASSWORD`, vazio no baseline).
- Verificação de completude de metadados `review_required`:
  - Script de validação confirmou `reason`, `impact` e `validation` em 9/9 chaves.
- Verificação de alvos esperados para execução por ambiente:
  - `config/development.env`, `config/staging.env`, `config/production.env` não existem no repositório nesta data.

## Próximos passos recomendados

- Criar `config/development.env`, `config/staging.env` e `config/production.env` a partir de `config/.env.example` quando o fluxo operacional do ambiente estiver pronto.
- Preencher segredos obrigatórios de cada ambiente real (`DATABASE_PASSWORD` e demais condicionais).
- Executar `env-sync` em modo `report` para cada `config/<environment>.env` real e revisar divergências antes de qualquer `apply`.
