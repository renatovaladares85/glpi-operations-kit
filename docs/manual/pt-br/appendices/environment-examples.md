# Exemplos de Ambiente (PT-BR)

Os exemplos abaixo são modelos de preenchimento. Não copie senhas reais para Git. Troque IPs, domínios e nomes pelos valores aprovados do ambiente.

## Exemplo 1 - Homologação single-server sem SSO

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
DATABASE_PASSWORD=<generate-high-entropy-password>
DATABASE_ROOT_PASSWORD=<generate-high-entropy-password>
TLS_MODE=none
SECURITY_REQUIRE_TLS=false
SECURITY_REQUIRE_HTTPS=false
AUTH_MODE=local
AUTH_EXTERNAL_ENABLED=false
SECURITY_SSO_ENABLED=false
MONITORING_MYSQLD_EXPORTER_PASSWORD=<generate-high-entropy-password>
BACKUP_BASE_DIR=/var/backups/glpi
BACKUP_RETENTION_DAYS=14
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
DATABASE_PASSWORD=<generate-high-entropy-password>
DATABASE_ROOT_PASSWORD=<generate-high-entropy-password>
DATABASE_BIND_ADDRESS=0.0.0.0
TLS_MODE=provided
TLS_COMMON_NAME=glpi.company.com
TLS_CERTIFICATE_PATH=/etc/ssl/certs/glpi-company-fullchain.pem
TLS_PRIVATE_KEY_PATH=/etc/ssl/private/glpi-company.key
TLS_PROVIDED_LOCAL_CERT_PATH=/secure-transfer/glpi-company-fullchain.pem
TLS_PROVIDED_LOCAL_KEY_PATH=/secure-transfer/glpi-company.key
SECURITY_REQUIRE_TLS=true
SECURITY_REQUIRE_HTTPS=true
MONITORING_MYSQLD_EXPORTER_PASSWORD=<generate-high-entropy-password>
BACKUP_RETENTION_DAYS=30
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

## Exemplo 3 - SAML com Azure/Entra ID

```env
AUTH_MODE=saml
AUTH_EXTERNAL_ENABLED=true
AUTH_SAML_ENABLED=true
AUTH_LDAP_ENABLED=false
AUTH_OIDC_ENABLED=false
SSO_PROVIDER=Azure Entra ID
SSO_PROTOCOL=saml
SSO_PUBLIC_URL=https://glpi.company.com
AUTH_SAML_PLUGIN_EXPECTED=true
AUTH_SAML_PLUGIN_NAME=saml
AUTH_SAML_ENTITY_ID=
AUTH_SAML_ACS_URL=
AUTH_SAML_LOGOUT_URL=
AUTH_SAML_IDP_ENTITY_ID=https://sts.windows.net/<tenant-id>/
AUTH_SAML_IDP_SSO_URL=https://login.microsoftonline.com/<tenant-id>/saml2
AUTH_SAML_IDP_SLO_URL=
AUTH_SAML_CLAIM_EMAIL=email
AUTH_SAML_CLAIM_USERNAME=username
AUTH_SAML_CLAIM_FIRSTNAME=firstname
AUTH_SAML_CLAIM_LASTNAME=lastname
AUTH_SAML_CLAIM_GROUPS=groups
AUTH_GROUP_ADMIN=GLPI-Admins
AUTH_GROUP_TECHNICIAN=GLPI-Technicians
AUTH_GROUP_USER=GLPI-Users
SECURITY_SSO_ENABLED=false
SECURITY_REQUIRE_SSO=false
```

Runtime secret estrutural:

```yaml
auth_saml_x509_certificate: "<paste-idp-public-x509-certificate>"
```

Fluxo:

```bash
./scripts/glpictl.sh production auth check
./scripts/glpictl.sh production auth prepare
./scripts/glpictl.sh production auth apply
./scripts/glpictl.sh production auth post-check
```

Depois de testar SSO e fallback local no GLPI, ajuste `SECURITY_SSO_ENABLED=true` se a política exigir.
