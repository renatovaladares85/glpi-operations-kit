# Exemplos de Ambiente (PT-BR)

Os exemplos abaixo são modelos de preenchimento com valores fictícios. Mantenha credenciais reais fora do Git.
Valores de retenção, janelas e governança devem seguir a política local do projeto.

## Exemplo 1 - Homologação single-server

```env
ENVIRONMENT_NAME=staging
ENVIRONMENT_STAGE=staging
EXECUTION_MODE=local
EXECUTION_HOST_ROLE_DEFAULT=all
TOPOLOGY_MODE=single-server
TOPOLOGY_APP_HOST=192.0.2.10
TOPOLOGY_DB_HOST=192.0.2.10
NETWORK_DATABASE_APP_ACCESS_HOST=127.0.0.1
NETWORK_DATABASE_ACCESS_MODE=restricted
NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=127.0.0.1,192.0.2.10
GLPI_VERSION=11.0.7
GLPI_DOMAIN=glpi-staging.example.internal
WEB_SERVER_TYPE=nginx
DATABASE_NAME=glpi_staging
DATABASE_USER=nehemiah_glpi
DATABASE_PASSWORD=kit-demo-Db9!vP2qL8x
DATABASE_ROOT_PASSWORD=kit-demo-Root7#kM4wN1z
TLS_MODE=none
SECURITY_REQUIRE_TLS=false
SECURITY_REQUIRE_HTTPS=false
MONITORING_MYSQLD_EXPORTER_PASSWORD=kit-demo-Mon5@hR8tQ3y
BACKUP_BASE_DIR=/var/backups/glpi
BACKUP_RETENTION_DAYS=21
```

Fluxo:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

## Exemplo 2 - Dual-server local com TLS fornecido

No host DB use `EXECUTION_HOST_ROLE_DEFAULT=db`. No host APP use `EXECUTION_HOST_ROLE_DEFAULT=app`.

```env
ENVIRONMENT_NAME=production
ENVIRONMENT_STAGE=production
EXECUTION_MODE=local
TOPOLOGY_MODE=dual-server
TOPOLOGY_APP_HOST=192.0.2.10
TOPOLOGY_DB_HOST=192.0.2.20
NETWORK_DATABASE_APP_ACCESS_HOST=192.0.2.10
NETWORK_DATABASE_ACCESS_MODE=restricted
NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=192.0.2.10
GLPI_VERSION=11.0.7
GLPI_DOMAIN=glpi.company.com
WEB_SERVER_TYPE=nginx
DATABASE_NAME=glpi_prod
DATABASE_USER=nehemiah_glpi
DATABASE_PASSWORD=kit-demo-Db9!vP2qL8x
DATABASE_ROOT_PASSWORD=kit-demo-Root7#kM4wN1z
DATABASE_BIND_ADDRESS=0.0.0.0
TLS_MODE=provided
TLS_COMMON_NAME=glpi.company.com
TLS_CERTIFICATE_PATH=/etc/ssl/certs/glpi-company-fullchain.pem
TLS_PRIVATE_KEY_PATH=/etc/ssl/private/glpi-company.key
TLS_PROVIDED_LOCAL_CERT_PATH=/secure-transfer/glpi-company-fullchain.pem
TLS_PROVIDED_LOCAL_KEY_PATH=/secure-transfer/glpi-company.key
SECURITY_REQUIRE_TLS=true
SECURITY_REQUIRE_HTTPS=true
MONITORING_MYSQLD_EXPORTER_PASSWORD=kit-demo-Mon5@hR8tQ3y
BACKUP_RETENTION_DAYS=21
```

Fluxo DB:

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
```

Fluxo APP:

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production tls check
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

## Exemplo 3 - Modo open no acesso ao DB (qualquer origem)

```env
ENVIRONMENT_NAME=staging
ENVIRONMENT_STAGE=staging
EXECUTION_MODE=local
TOPOLOGY_MODE=dual-server
TOPOLOGY_APP_HOST=192.0.2.10
TOPOLOGY_DB_HOST=192.0.2.20
NETWORK_DATABASE_APP_ACCESS_HOST=192.0.2.10
NETWORK_DATABASE_ACCESS_MODE=open
NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=
GLPI_VERSION=11.0.7
GLPI_DOMAIN=glpi-staging.example.internal
WEB_SERVER_TYPE=nginx
DATABASE_NAME=glpi_staging
DATABASE_USER=nehemiah_glpi
DATABASE_PASSWORD=kit-demo-Db9!vP2qL8x
DATABASE_ROOT_PASSWORD=kit-demo-Root7#kM4wN1z
MONITORING_MYSQLD_EXPORTER_PASSWORD=kit-demo-Mon5@hR8tQ3y
```

`NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=` permanece ativo e vazio quando `NETWORK_DATABASE_ACCESS_MODE=open`.

## Nota sobre SSO

A configuração de SSO é manual no GLPI/IdP e intencionalmente não aparece como exemplo dirigido por script com `AUTH_*`/`SSO_*`.
