# Relatório do contrato de ambiente

## Fonte oficial

- `config/.env.example`

## Arquivos reais analisados

- Nenhum `config/<ambiente>.env` encontrado.

## Arquivos criados/atualizados

- `.env.sync.generated.yml`

## Quantidade de variáveis

- total no template oficial: 119
- total no contrato gerado: 119
- protected: 99
- managed: 1
- review_required: 19
- deprecated: 0
- secret: 8

## Variáveis sensíveis identificadas

- `DATABASE_MANAGED_ADMIN_PASSWORD`
- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD`
- `DATABASE_USER`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD`
- `MONITORING_MYSQLD_EXPORTER_USER`
- `NETWORK_SSH_PRIVATE_KEY_PATH`
- `TLS_PRIVATE_KEY_PATH`

## Variáveis com revisão manual

- `DATABASE_DEPLOYMENT_MODE`
- `EXECUTION_HOST_ROLE_DEFAULT`
- `EXECUTION_MODE`
- `GLPI_TIMEZONE_DB_LEGACY_GRANT`
- `GLPI_TIMEZONE_DB_MODE`
- `GLPI_TIMEZONE_SUPPORT_ENABLED`
- `GLPI_VERSION`
- `MONITORING_MYSQLD_EXPORTER_ENABLED`
- `MONITORING_NODE_EXPORTER_ENABLED`
- `NETWORK_DATABASE_ACCESS_MODE`
- `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS`
- `NETWORK_DATABASE_APP_ACCESS_HOST`
- `OPERATIONS_TIMEZONE`
- `RESOURCE_PROFILE_ACTIVE`
- `TLS_MODE`
- `TOPOLOGY_MODE`
- `WEB_HTTPS_PORT`
- `WEB_HTTP_PORT`
- `WEB_SERVER_TYPE`

## Ambiguidades

- Duplicidades no template oficial:
  - `NETWORK_DATABASE_ACCESS_MODE`
  - `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS`
- Variáveis usadas no código e ausentes no template: nenhuma.
- Variáveis extras em ambientes e com uso detectado no código: nenhuma.
- Variáveis extras em ambientes sem uso claro no código: nenhuma.
- Sem ambiguidades por arquivo de ambiente.
- Chaves com variação de valor entre ambientes: nenhuma detectada.

## Cobertura por ambiente

- Não aplicável (nenhum ambiente real disponível).

## Pós-geração: env-sync report

- `config/.env.example`: code=2; missing=1; review_required=0; validation_errors=0; extras=0; ambiguous=0
  - required missing keys:
    - `DATABASE_PASSWORD`

## Validações executadas

- Validação estrutural do YAML gerado (campos obrigatórios e políticas permitidas): OK.
- Cobertura de chaves do template no contrato gerado: OK.
- Pós-checks `env-sync` em modo report: executado para template oficial e ambientes encontrados.
