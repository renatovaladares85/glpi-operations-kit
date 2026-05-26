# Environment Configuration Field Guide (EN)

This guide explains how to fill `config/<environment>.env` from `config/product.env`. It is written for operators who do not yet know the kit or the customer infrastructure.

Use this guide before running `deploy check`, `auth check`, `tls check`, or any mutable operation.

## Golden rule

- Public values stay in `config/<environment>.env`.
- Deployment secrets currently read from the environment file are `DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, and `MONITORING_MYSQLD_EXPORTER_PASSWORD`.
- External-auth secrets must remain only in `.runtime/<environment>/secrets.yml`, such as `auth_saml_x509_certificate`, `ldap_bind_password`, and `oidc_client_secret`.
- Never commit private certificates, tokens, passwords, or dumps to Git.
- Replace placeholders such as `<generate-high-entropy-password>` with strong random secrets before real execution.

## First steps

1. Copy the template: `cp config/product.env config/staging.env`.
2. Fill identity, topology, network, DB, app, paths, and policy first.
3. Choose TLS mode: `none`, `self_signed`, or `provided`.
4. If SSO is enabled, fill `AUTH_*`, `SSO_*`, and keep secrets only in `.runtime/<environment>/secrets.yml`.
5. Run `bash scripts/bootstrap-permissions.sh`.
6. Run `./scripts/glpictl.sh <environment> deploy check all` before any `apply`.

## Information collection checklist

| Area | Usual owner | Ask for |
|---|---|---|
| DNS and network | Infrastructure/network | GLPI FQDN, app host IP/FQDN, DB host IP/FQDN, allowed ports, APP -> DB rule. |
| Operating system | Linux/infrastructure | Operational user, sudo, `glpiops` group, Linux shell, allowed packages. |
| Database | DBA/infrastructure | Schema name, application user, strong password, root/provisioning password, port, bind address, allowed sources. |
| TLS | Security/PKI | HTTPS server certificate, full chain, matching private key, FQDN/SAN. |
| SSO | IAM/Azure/Entra ID | Public HTTPS URL, Entity ID, ACS/Reply URL, Logout URL, claims, groups, IdP public certificate. |
| Monitoring | Observability/NOC | Exporter toggles, labels, thresholds, alert routes, DB exporter credential. |
| Backup | Infrastructure/backup | Backup directory, retention, space, external encryption if required, restore window. |

## Product and environment identity

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `PRODUCT_NAME` | Product display name. | Keep default or use the approved internal product name. | Plain text. |
| `PRODUCT_SLUG` | Lowercase short identifier. | Derive from `PRODUCT_NAME` using hyphens. | Avoid spaces and accents. |
| `PRODUCT_DEPLOYMENT_LABEL` | Label for this deployment. | Use `staging-kit` or `production-kit`. | Must distinguish deployments. |
| `CUSTOMER_DISPLAY_NAME` | Customer/environment display name. | Use generic or approved naming only. | Do not hardcode real customer names in reusable templates. |
| `CUSTOMER_SHORT_NAME` | Short customer identifier. | Use a slug, for example `example-customer`. | Used in labels and dashboards. |
| `ENVIRONMENT_NAME` | CLI/runtime environment name. | Match the file name: `config/staging.env` uses `staging`. | `./scripts/glpictl.sh staging ...` must find the file. |
| `ENVIRONMENT_STAGE` | Lifecycle stage. | Use `staging`, `production`, `dev`, or equivalent. | Must reflect operational risk. |

## Execution and topology

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `EXECUTION_MODE` | `local` or `ssh`. | Use `local` when each host runs its own commands; use `ssh` only when remote orchestration is allowed. | In `ssh`, key and remote access are mandatory. |
| `EXECUTION_HOST_ROLE_DEFAULT` | `app`, `db`, or `all`. | In single-server use `all`; in dual-server local use `db` on DB host and `app` on APP host. | Prevents applying steps on the wrong host. |
| `TOPOLOGY_MODE` | `single-server` or `dual-server`. | Confirm whether APP and DB are colocated or split. | Must match host values. |
| `TOPOLOGY_APP_ALIAS` | Ansible alias for app host. | Use a short name such as `app-node`. | Does not need DNS resolution. |
| `TOPOLOGY_APP_HOST` | App host IP or FQDN. | Ask infrastructure/network. | Must be reachable by executor in `ssh` mode. |
| `TOPOLOGY_DB_ALIAS` | Ansible alias for DB host. | Use a short name such as `db-node`. | Does not need DNS resolution. |
| `TOPOLOGY_DB_HOST` | DB host IP or FQDN. | Ask infrastructure/network. | In dual-server it must point to the real DB host. |

## Network, SSH, and DB access

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `NETWORK_SSH_USER` | Linux SSH user. | Ask the Linux team; use an approved named or operational account. | Required only with `EXECUTION_MODE=ssh`. |
| `NETWORK_SSH_PRIVATE_KEY_PATH` | SSH private key path on executor. | Generate or request one key pair per environment; keep mode `0600`. | Required only with `EXECUTION_MODE=ssh`. |
| `NETWORK_DATABASE_APP_ACCESS_HOST` | Source granted DB access. | Usually the app host address as seen by DB. | Must match the real APP -> DB source. |
| `NETWORK_DATABASE_ACCESS_MODE` | DB access policy mode. | Use `restricted` to limit source hosts or `open` to allow any source. | Default is `restricted` when omitted. |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | CSV allowlist of DB sources used in restricted mode. | Include APP and approved maintenance hosts only. | No spaces; example `192.0.2.10,192.0.2.11`. |

Risk note:
`NETWORK_DATABASE_ACCESS_MODE=open` removes source restrictions at both firewall and DB grant layers. Use only with explicit risk acceptance.

## GLPI, web server, and PHP

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `GLPI_VERSION` | Target GLPI version. | Use the homologated version, for example `11.0.7` when that is the approved baseline. | Must be compatible with PHP minimum 8.2. |
| `GLPI_DOMAIN` | Hostname used to access GLPI. | Ask DNS/network team. | Must be present in certificate when TLS is enabled. |
| `WEB_SERVER_TYPE` | `nginx`, `apache`, or `lighttpd`. | Choose according to environment standard. The Linux kit does not automate IIS. | Only one web engine should be active on the host. |
| `GLPI_UPLOAD_MAX_FILESIZE` | PHP upload limit. | Size it for expected attachments. | PHP size syntax, e.g. `32M` or `128M`. |
| `GLPI_POST_MAX_SIZE` | PHP POST body limit. | Make it equal to or larger than upload. | PHP size syntax. |
| `GLPI_MEMORY_LIMIT` | PHP memory ceiling. | Tune based on usage profile. | `512M` is a safe initial baseline. |
| `GLPI_MAX_EXECUTION_TIME` | PHP max execution time. | Increase for long imports. | Integer seconds. |
| `GLPI_OPCACHE_MEMORY_CONSUMPTION` | OPcache memory in MB. | Tune based on environment size. | Integer, example `192`. |
| `GLPI_CRON_SCHEDULE` | GLPI cron schedule. | Use every 5 minutes unless policy differs. | Quote it because it contains spaces. |
| `GLPI_FILESYSTEM_OWNER` | Owner for writable paths. | Usually the web user, such as `www-data`. | User must exist on host. |
| `GLPI_FILESYSTEM_GROUP` | Group for writable paths. | Usually `www-data`. | Group must exist on host. |
| `GLPI_APP_PACKAGES` | CSV package list or empty. | Leave empty for automatic mapping by `WEB_SERVER_TYPE`; fill only for full operator-owned override. | Manual override must include every required package. |

## Database

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `DATABASE_NAME` | GLPI schema name. | Define with DBA, e.g. `glpi_operational`. | Simple SQL identifier. |
| `DATABASE_USER` | GLPI SQL user. | Define with DBA; prefer contextual non-obvious names, e.g. `nehemiah_glpi`. | Avoid `admin`, `root`, `glpi`. |
| `DATABASE_PASSWORD` | Password for GLPI SQL user. | Generate a strong random secret. | Required secret; do not commit. |
| `DATABASE_ROOT_PASSWORD` | MariaDB root/provisioning password. | Generate or request from DBA. | Required secret; do not commit. |
| `DATABASE_PORT` | MariaDB/MySQL TCP port. | Usually `3306`. | Firewall must allow APP source. |
| `DATABASE_BIND_ADDRESS` | DB bind address. | Use `0.0.0.0` for all approved interfaces or the specific DB IP. | Must match firewall policy. |
| `DATABASE_PACKAGES` | CSV DB packages. | Keep default unless OS policy requires a change. | Current baseline: `mariadb-server,mariadb-client,python3-pymysql`. |

## PHP-FPM and web ports

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `PHP_FPM_SERVICE_NAME` | PHP-FPM service name. | Confirm installed PHP version, e.g. `php8.3-fpm`. | `systemctl status <service>` should exist after install. |
| `PHP_FPM_SOCKET` | PHP-FPM Unix socket. | Confirm distro/PHP default. | Must match web template. |
| `PHP_FPM_PM` | `static`, `dynamic`, or `ondemand`. | Use `dynamic` unless there is a specific reason. | Must be accepted by PHP-FPM. |
| `NGINX_HTTP_PORT` | HTTP port. | Usually `80`. | Used by Nginx template. |
| `NGINX_HTTPS_PORT` | HTTPS port. | Usually `443`. | Used by Nginx template. |

## TLS and certificates

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `TLS_MODE` | `none`, `self_signed`, or `provided`. | Use `provided` for production; `self_signed` only for controlled test; `none` only when policy allows. | `SECURITY_REQUIRE_*` can block. |
| `TLS_COMMON_NAME` | Main certificate FQDN. | Use the public GLPI hostname, usually equal to `GLPI_DOMAIN`. | Must also be in certificate SAN. |
| `TLS_CERTIFICATE_PATH` | Final certificate path on APP host. | Use a protected path, e.g. `/etc/ssl/certs/glpi-example.crt`. | Destination on server, not local source. |
| `TLS_PRIVATE_KEY_PATH` | Final private key path on APP host. | Use a protected path, e.g. `/etc/ssl/private/glpi-example.key`. | Key must be restricted and outside webroot. |
| `TLS_PROVIDED_LOCAL_CERT_PATH` | Local source certificate/chain file. | Fill in `provided` flow with CA-provided fullchain PEM. | File must exist on executor. |
| `TLS_PROVIDED_LOCAL_KEY_PATH` | Local source private key file. | Fill in `provided` flow with matching private key. | File must exist and must not be a public key. |

For `provided` mode, request an HTTPS server certificate, not a client certificate. It must include `serverAuth`, FQDN in SAN, full PEM chain, and matching PEM private key. mTLS/client certificate is not automated by the current kit.

## Backup

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `BACKUP_BASE_DIR` | Backup root on target host. | Ask infrastructure for the approved path; default `/var/backups/glpi`. | Must have space and restricted permissions. |
| `BACKUP_RETENTION_DAYS` | Retention in days. | Use environment policy, e.g. `14` staging and `30` production. | Positive integer. |

## Monitoring and alerting

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `MONITORING_NODE_EXPORTER_ENABLED` | `true` or `false`. | Enable when host metrics are collected. | Boolean. |
| `MONITORING_MYSQLD_EXPORTER_ENABLED` | `true` or `false`. | Enable when MariaDB/MySQL metrics are collected. | Boolean. |
| `MONITORING_MYSQLD_EXPORTER_USER` | SQL user for exporter. | Use contextual name, e.g. `issachar_monitor`. | Avoid generic names. |
| `MONITORING_MYSQLD_EXPORTER_PASSWORD` | Exporter password. | Generate a strong random secret. | Required secret; do not commit. |
| `MONITORING_LABELS_JSON` | One-line JSON labels. | Define product, service, customer, environment. | Must be a valid JSON object. |
| `MONITORING_THRESHOLDS_JSON` | One-line JSON thresholds. | Ask observability/NOC. | Must contain coherent numbers. |
| `MONITORING_SCRAPE_PROFILES_JSON` | JSON scrape profiles. | Use approved interval and timeout. | Valid JSON object, e.g. `{"default":{"interval":"30s","timeout":"10s"}}`. |
| `MONITORING_DASHBOARD_PROFILE` | Dashboard profile name. | Use `glpi-standard` or agreed profile. | Plain text. |
| `MONITORING_ALERT_ROUTES_JSON` | JSON alert routing. | Ask NOC for receiver/escalation. | Valid JSON object. |
| `ALERTING_TLS_EXPIRY_WARNING_DAYS` | TLS expiry warning days. | Use security policy, default `30`. | Positive integer. |
| `ALERTING_BACKUP_FAILURE_ENABLED` | `true` or `false`. | Keep `true` unless formally excepted. | Boolean. |
| `ALERTING_SERVICE_DOWN_ENABLED` | `true` or `false`. | Keep `true` unless formally excepted. | Boolean. |

## Auth, SSO, LDAP, SAML, and OIDC

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `AUTH_MODE` | `local`, `ldap`, `saml`, or `oidc`. | Use `local` to preserve local login; use external only when IAM approves. | `local` does not change functional behavior. |
| `AUTH_EXTERNAL_ENABLED` | `true` if external provider is enabled. | Set according to IAM decision. | Must be coherent with `AUTH_MODE`. |
| `AUTH_LDAP_ENABLED` | `true` for LDAP preparation/validation. | Use if LDAP is part of the solution. | Kit prepares/validates; it does not invent secrets. |
| `AUTH_SAML_ENABLED` | `true` for SAML preparation/validation. | Use with Entra ID/SAML and manual plugin. | Requires public HTTPS URL when applicable. |
| `AUTH_OIDC_ENABLED` | `true` for OIDC preparation/validation. | Use only if OIDC implementation/plugin is approved outside the kit. | No SCIM and no paid plugin automation. |
| `SSO_PROVIDER` | Provider name. | Example `Azure Entra ID`. | Used in evidence/checklists. |
| `SSO_PROTOCOL` | `saml`, `oidc`, `ldap`, or free label. | Usually equal to external `AUTH_MODE`. | Used in evidence. |
| `SSO_PUBLIC_URL` | Public HTTPS GLPI URL. | Ask DNS/network, e.g. `https://glpi.company.com`. | SAML/OIDC require `https://`. |
| `SSO_REQUIRE_PUBLIC_URL` | `true` or `false`. | Keep `true` when external auth is enabled. | Blocks missing URL when required. |
| `AUTH_SAML_PLUGIN_EXPECTED` | `true` when SAML plugin should exist. | Keep `true` for SAML. | Kit detects only; it does not install. |
| `AUTH_SAML_PLUGIN_NAME` | Plugin directory/name. | Default `saml`, matching manually installed Marketplace plugin. | Must exist under plugin directory when SAML is active. |
| `AUTH_SAML_ENTITY_ID` | SP Entity ID. | Leave empty to derive from `SSO_PUBLIC_URL`, or set IAM-approved value. | Empty becomes `${SSO_PUBLIC_URL}`. |
| `AUTH_SAML_ACS_URL` | Reply/ACS URL. | Leave empty to derive. | Empty becomes `${SSO_PUBLIC_URL}/front/saml.php`. |
| `AUTH_SAML_LOGOUT_URL` | Logout URL. | Leave empty to derive. | Empty becomes `${SSO_PUBLIC_URL}/front/saml_logout.php`. |
| `AUTH_SAML_NAMEID_FORMAT` | NameID format. | Keep email format unless IAM requires otherwise. | Default is emailAddress URN. |
| `AUTH_SAML_IDP_ENTITY_ID` | IdP Entity ID. | Copy from Entra ID/IdP metadata. | Not a secret. |
| `AUTH_SAML_IDP_SSO_URL` | IdP login URL. | Copy from Entra ID/IdP metadata. | Must be HTTPS. |
| `AUTH_SAML_IDP_SLO_URL` | IdP logout URL. | Copy if provided by IdP. | May be empty if unused. |
| `AUTH_SAML_CLAIM_EMAIL` | Email claim name. | Define from IAM mapping. | Example `email`. |
| `AUTH_SAML_CLAIM_USERNAME` | Username claim name. | Define from IAM mapping. | Example `username`. |
| `AUTH_SAML_CLAIM_FIRSTNAME` | First name claim. | Define from IAM mapping. | Example `firstname`. |
| `AUTH_SAML_CLAIM_LASTNAME` | Last name claim. | Define from IAM mapping. | Example `lastname`. |
| `AUTH_SAML_CLAIM_GROUPS` | Groups claim. | Define from IAM mapping. | Example `groups`. |
| `AUTH_JIT_ENABLED` | `true` to indicate JIT provisioning in checklist. | Use according to GLPI/IAM policy. | Evidence only; does not remove local login. |
| `AUTH_DEFAULT_PROFILE` | Default GLPI profile. | Example `Self-Service`. | Must exist/be configured in GLPI if used. |
| `AUTH_GROUP_ADMIN` | IAM group for GLPI admins. | Ask IAM. | Example `GLPI-Admins`. |
| `AUTH_GROUP_TECHNICIAN` | IAM group for technicians. | Ask IAM. | Example `GLPI-Technicians`. |
| `AUTH_GROUP_USER` | IAM group for users. | Ask IAM. | Example `GLPI-Users`. |

## Policy and operational security

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `SECURITY_SSO_ENABLED` | Real current SSO state. | `true` only when SSO is actually ready. | Used by policy checks. |
| `SECURITY_ALLOW_INSECURE_NON_PRODUCTION` | Non-production exception flag. | Use according to internal policy. | Does not replace `SECURITY_MODE`. |
| `SECURITY_REQUIRE_TLS` | Require `TLS_MODE=provided`. | Enable when compliance requires valid certificate. | Can block in `secure`. |
| `SECURITY_REQUIRE_HTTPS` | Require HTTPS. | Enable when HTTP is unacceptable. | Accepts `self_signed` or `provided` depending on policy. |
| `SECURITY_REQUIRE_SSO` | Require SSO. | Enable when external login is mandatory. | Depends on `SECURITY_SSO_ENABLED=true`. |
| `SECURITY_REQUIRE_PROMOTION_GATE` | Require promotion gate. | Use in staging -> production flow. | Requires certification artifact. |
| `SECURITY_REQUIRE_ORDERED_EXECUTION` | Require deployment order. | Keep `true` unless excepted. | Blocks wrong order in `secure`. |
| `OPERATIONS_ASSUME_DB_APPLIED` | Confirm DB was applied on another host. | Use on APP host in local dual-server after DB was applied separately. | Affects ordered execution validation. |

## GLPI paths

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `PATH_GLPI_RELEASE_ROOT` | Release extraction root. | Default `/usr/share`. | Must exist/be creatable with proper permissions. |
| `PATH_GLPI_INSTALL_DIR` | GLPI install directory. | Default `/usr/share/glpi`. | Webroot must point to its `public` directory. |
| `PATH_GLPI_CONFIG_DIR` | Config directory outside webroot. | Default `/etc/glpi`. | Never expose by web server. |
| `PATH_GLPI_VAR_DIR` | Data/files directory outside webroot. | Default `/var/lib/glpi/files`. | Must be writable by web user. |
| `PATH_GLPI_PLUGIN_DIR` | Plugin directory. | Default `/var/lib/glpi/plugins`. | Manual SAML plugin must be detectable here when applicable. |
| `PATH_GLPI_LOG_DIR` | GLPI log directory. | Default `/var/log/glpi`. | Must stay outside webroot. |

## Operations

| Key | What to set | How to get or decide it | Common validation |
|---|---|---|---|
| `OPERATIONS_TIMEZONE` | IANA timezone. | Example `America/Sao_Paulo`. | Use `timedatectl list-timezones`. |
| `OPERATIONS_GLPI_CRON_SCHEDULE` | Operational cron schedule. | Usually same as `GLPI_CRON_SCHEDULE`. | Must be quoted. |
| `OPERATIONS_REQUIRED_OPS_GROUP` | Linux operator group. | Default `glpiops`. | Operator must belong to this group. |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | `secure` or `permissive`. | Use `secure` by default. | `permissive` requires justification. |
| `OPERATIONS_PERMISSIVE_JUSTIFICATION` | Justification for permissive. | Fill only when permissive is needed and approved. | Must explain accepted risk. |

## Resource profiles

`RESOURCE_PROFILE_ACTIVE` selects `small`, `medium`, or `large`. The following values tune PHP-FPM and MariaDB for each profile family. Change them only based on host capacity, user volume, DBA/infrastructure guidance, or load testing.

| Key | Controls | Format |
|---|---|---|
| `RESOURCE_PROFILE_ACTIVE` | Active profile rendered to runtime. | `small`, `medium`, `large` |
| `RESOURCE_PROFILE_SMALL_PHP_MAX_CHILDREN` | Max PHP workers in small profile. | integer |
| `RESOURCE_PROFILE_SMALL_PHP_START_SERVERS` | Initial PHP workers in small profile. | integer |
| `RESOURCE_PROFILE_SMALL_PHP_MIN_SPARE_SERVERS` | Minimum idle PHP workers in small profile. | integer |
| `RESOURCE_PROFILE_SMALL_PHP_MAX_SPARE_SERVERS` | Maximum idle PHP workers in small profile. | integer |
| `RESOURCE_PROFILE_SMALL_PHP_MAX_REQUESTS` | PHP worker recycle threshold in small profile. | integer |
| `RESOURCE_PROFILE_SMALL_MARIADB_INNODB_BUFFER_POOL_SIZE` | MariaDB buffer pool in small profile. | size, e.g. `2G` |
| `RESOURCE_PROFILE_SMALL_MARIADB_MAX_CONNECTIONS` | MariaDB connections in small profile. | integer |
| `RESOURCE_PROFILE_SMALL_MARIADB_TMP_TABLE_SIZE` | Temporary table size in small profile. | size |
| `RESOURCE_PROFILE_SMALL_MARIADB_MAX_HEAP_TABLE_SIZE` | Heap table size in small profile. | size |
| `RESOURCE_PROFILE_SMALL_MARIADB_SLOW_QUERY_LOG` | Slow query log in small profile. | `0` or `1` |
| `RESOURCE_PROFILE_SMALL_MARIADB_LONG_QUERY_TIME` | Slow query threshold in small profile. | seconds |
| `RESOURCE_PROFILE_MEDIUM_PHP_MAX_CHILDREN` | Max PHP workers in medium profile. | integer |
| `RESOURCE_PROFILE_MEDIUM_PHP_START_SERVERS` | Initial PHP workers in medium profile. | integer |
| `RESOURCE_PROFILE_MEDIUM_PHP_MIN_SPARE_SERVERS` | Minimum idle PHP workers in medium profile. | integer |
| `RESOURCE_PROFILE_MEDIUM_PHP_MAX_SPARE_SERVERS` | Maximum idle PHP workers in medium profile. | integer |
| `RESOURCE_PROFILE_MEDIUM_PHP_MAX_REQUESTS` | PHP worker recycle threshold in medium profile. | integer |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_INNODB_BUFFER_POOL_SIZE` | MariaDB buffer pool in medium profile. | size, e.g. `8G` |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_MAX_CONNECTIONS` | MariaDB connections in medium profile. | integer |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_TMP_TABLE_SIZE` | Temporary table size in medium profile. | size |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_MAX_HEAP_TABLE_SIZE` | Heap table size in medium profile. | size |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_SLOW_QUERY_LOG` | Slow query log in medium profile. | `0` or `1` |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_LONG_QUERY_TIME` | Slow query threshold in medium profile. | seconds |
| `RESOURCE_PROFILE_LARGE_PHP_MAX_CHILDREN` | Max PHP workers in large profile. | integer |
| `RESOURCE_PROFILE_LARGE_PHP_START_SERVERS` | Initial PHP workers in large profile. | integer |
| `RESOURCE_PROFILE_LARGE_PHP_MIN_SPARE_SERVERS` | Minimum idle PHP workers in large profile. | integer |
| `RESOURCE_PROFILE_LARGE_PHP_MAX_SPARE_SERVERS` | Maximum idle PHP workers in large profile. | integer |
| `RESOURCE_PROFILE_LARGE_PHP_MAX_REQUESTS` | PHP worker recycle threshold in large profile. | integer |
| `RESOURCE_PROFILE_LARGE_MARIADB_INNODB_BUFFER_POOL_SIZE` | MariaDB buffer pool in large profile. | size, e.g. `24G` |
| `RESOURCE_PROFILE_LARGE_MARIADB_MAX_CONNECTIONS` | MariaDB connections in large profile. | integer |
| `RESOURCE_PROFILE_LARGE_MARIADB_TMP_TABLE_SIZE` | Temporary table size in large profile. | size |
| `RESOURCE_PROFILE_LARGE_MARIADB_MAX_HEAP_TABLE_SIZE` | Heap table size in large profile. | size |
| `RESOURCE_PROFILE_LARGE_MARIADB_SLOW_QUERY_LOG` | Slow query log in large profile. | `0` or `1` |
| `RESOURCE_PROFILE_LARGE_MARIADB_LONG_QUERY_TIME` | Slow query threshold in large profile. | seconds |

## Pre-install validation

Run in this order:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging auth check
./scripts/glpictl.sh staging tls check
```

If any check fails, fix the reported value before running `apply`.
