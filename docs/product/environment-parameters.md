# Environment Parameters Reference

This reference explains how to fill `config/<environment>.env`. The template `config/product.env` is the canonical source and includes inline comments for every key.

## How to use this file

Create your environment file:

```bash
cp config/product.env config/staging.env
```

Edit key values and keep secrets out of this file. Runtime secrets stay in `.runtime/<environment>/secrets.yml`.

## Metadata and environment identity

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `PRODUCT_NAME` | yes | Product display name for reports and runtime metadata | string; `GLPI Operations Kit` | scripts, docs metadata |
| `PRODUCT_SLUG` | optional | Stable identifier for labels and automation | slug; `glpi-operations-kit` | runtime labels |
| `PRODUCT_DEPLOYMENT_LABEL` | optional | Deployment tag for this package instance | string; `reference-kit` | metadata |
| `CUSTOMER_DISPLAY_NAME` | yes | Customer-facing label | string; `Example Customer` | dashboards, reports |
| `CUSTOMER_SHORT_NAME` | optional | Compact customer identifier | slug; `example-customer` | labels |
| `ENVIRONMENT_NAME` | yes | Effective environment identity | string; `staging` | runtime metadata |
| `ENVIRONMENT_STAGE` | optional | Lifecycle stage label | string; `staging` | labels, reports |

## Execution and topology

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `EXECUTION_MODE` | yes | Selects local or SSH orchestration | `local` or `ssh` | precheck, inventory renderer |
| `EXECUTION_HOST_ROLE_DEFAULT` | yes | Default role scope in local mode | `app`, `db`, or `all` | deploy role consistency checks |
| `TOPOLOGY_MODE` | yes | Defines single or dual host model | `single-server` or `dual-server` | deploy safety checks |
| `TOPOLOGY_APP_ALIAS` | yes | Inventory alias for app host | short string; `app-node` | generated inventory |
| `TOPOLOGY_APP_HOST` | yes | App host endpoint | IP or FQDN; `192.0.2.10` | inventory, DB grants |
| `TOPOLOGY_DB_ALIAS` | yes | Inventory alias for DB host | short string; `db-node` | generated inventory |
| `TOPOLOGY_DB_HOST` | yes | DB host endpoint | IP or FQDN; `192.0.2.20` | inventory, policy checks |

## Network and SSH

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `NETWORK_SSH_USER` | conditional (`EXECUTION_MODE=ssh`) | SSH login user for remote orchestration | Linux user; `ubuntu` | generated inventory |
| `NETWORK_SSH_PRIVATE_KEY_PATH` | conditional (`EXECUTION_MODE=ssh`) | SSH private key path | path; `~/.ssh/glpi_staging_ed25519` | generated inventory, precheck |
| `NETWORK_DATABASE_APP_ACCESS_HOST` | yes | Host granted DB access from app side | IP/FQDN; `192.0.2.10` | DB grants |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | yes | DB source allowlist | CSV; `192.0.2.10,192.0.2.11` | firewall/grants |

## GLPI application parameters

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `GLPI_VERSION` | yes | GLPI release version | semantic version; `11.0.0` | download and deploy logic |
| `GLPI_DOMAIN` | yes | GLPI endpoint domain | FQDN; `glpi.example.internal` | Nginx and smoke checks |
| `GLPI_UPLOAD_MAX_FILESIZE` | optional | Upload limit | PHP size; `32M` | PHP runtime template |
| `GLPI_POST_MAX_SIZE` | optional | POST body limit | PHP size; `32M` | PHP runtime template |
| `GLPI_MEMORY_LIMIT` | optional | PHP memory ceiling | PHP size; `512M` | PHP runtime template |
| `GLPI_MAX_EXECUTION_TIME` | optional | PHP max execution time | integer; `120` | PHP runtime template |
| `GLPI_OPCACHE_MEMORY_CONSUMPTION` | optional | OPcache memory in MB | integer; `192` | PHP runtime template |
| `GLPI_CRON_SCHEDULE` | optional | GLPI cron cadence | quoted cron; `"*/5 * * * *"` | app role cron task |
| `GLPI_FILESYSTEM_OWNER` | optional | Owner for writable paths | Linux user; `www-data` | permissions |
| `GLPI_FILESYSTEM_GROUP` | optional | Group for writable paths | Linux group; `www-data` | permissions |
| `GLPI_APP_PACKAGES` | optional | App package baseline | CSV package list | package install tasks |

## Database parameters

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `DATABASE_NAME` | yes | GLPI schema name | SQL identifier; `glpi_operational` | DB/app roles |
| `DATABASE_USER` | yes | GLPI DB username | SQL identifier; `nehemiah_glpi` | DB/app roles |
| `DATABASE_PORT` | optional | MariaDB listener port | integer; `3306` | DB role |
| `DATABASE_BIND_ADDRESS` | optional | MariaDB bind address | IP; `0.0.0.0` | DB role |
| `DATABASE_PACKAGES` | optional | DB package baseline | CSV; `mariadb-server,mariadb-client,python3-pymysql` | DB install |

## PHP-FPM and Nginx base

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `PHP_FPM_SERVICE_NAME` | optional | Service identifier | string; `php8.3-fpm` | handlers/tests |
| `PHP_FPM_SOCKET` | optional | PHP-FPM socket path | absolute path | Nginx/PHP templates |
| `PHP_FPM_PM` | optional | Process manager mode | `dynamic`, `static`, `ondemand` | PHP-FPM pool |
| `NGINX_HTTP_PORT` | optional | HTTP port | integer; `80` | Nginx template |
| `NGINX_HTTPS_PORT` | optional | HTTPS port | integer; `443` | Nginx template |

## TLS parameters

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `TLS_MODE` | yes | TLS behavior selector | `none`, `self_signed`, `provided` | app role, policy checks |
| `TLS_COMMON_NAME` | optional | Certificate common name | FQDN; `glpi.example.internal` | certificate workflows |
| `TLS_CERTIFICATE_PATH` | conditional when TLS enabled | Target cert path on host | absolute path | Nginx template |
| `TLS_PRIVATE_KEY_PATH` | conditional when TLS enabled | Target key path on host | absolute path | Nginx template |
| `TLS_PROVIDED_LOCAL_CERT_PATH` | conditional (`TLS_MODE=provided`) | Local cert source path | path | tls install-provided flow |
| `TLS_PROVIDED_LOCAL_KEY_PATH` | conditional (`TLS_MODE=provided`) | Local key source path | path | tls install-provided flow |

## Backup and monitoring

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `BACKUP_BASE_DIR` | optional | Backup root path | absolute path | backup role |
| `BACKUP_RETENTION_DAYS` | optional | Retention period | integer; `14` | backup role |
| `MONITORING_NODE_EXPORTER_ENABLED` | optional | Node exporter toggle | boolean | monitoring role |
| `MONITORING_MYSQLD_EXPORTER_ENABLED` | optional | mysqld exporter toggle | boolean | monitoring role |
| `MONITORING_MYSQLD_EXPORTER_USER` | yes | mysqld exporter user | SQL identifier | monitoring role |
| `MONITORING_LABELS_JSON` | optional | Label map | JSON object | runtime labels |
| `MONITORING_THRESHOLDS_JSON` | optional | Threshold map | JSON object | alert baselines |
| `MONITORING_SCRAPE_PROFILES_JSON` | optional | Scrape profile map | JSON object | monitoring blueprint |
| `MONITORING_DASHBOARD_PROFILE` | optional | Dashboard profile label | string | monitoring metadata |
| `MONITORING_ALERT_ROUTES_JSON` | optional | Alert routing map | JSON object | monitoring metadata |
| `ALERTING_TLS_EXPIRY_WARNING_DAYS` | optional | TLS warning threshold | integer; `30` | cert checks |
| `ALERTING_BACKUP_FAILURE_ENABLED` | optional | Backup failure alert toggle | boolean | alerting policy |
| `ALERTING_SERVICE_DOWN_ENABLED` | optional | Service down alert toggle | boolean | alerting policy |

## Security policy parameters

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `SECURITY_SSO_ENABLED` | yes | Current SSO state | boolean | policy checks |
| `SECURITY_ALLOW_INSECURE_NON_PRODUCTION` | optional | Insecure policy exception flag | boolean | policy metadata |
| `SECURITY_REQUIRE_TLS` | optional | Require provided TLS mode | boolean | precheck and deploy policy |
| `SECURITY_REQUIRE_HTTPS` | optional | Require TLS enabled | boolean | precheck and deploy policy |
| `SECURITY_REQUIRE_SSO` | optional | Require SSO enabled | boolean | precheck and deploy policy |
| `SECURITY_REQUIRE_PROMOTION_GATE` | optional | Require staging gate artifact | boolean | precheck and deploy policy |
| `SECURITY_REQUIRE_ORDERED_EXECUTION` | optional | Require ordered deployment sequence | boolean | precheck and deploy policy |

## Filesystem and operations

| Key | Required | Purpose | Format and example | Consumed by |
|---|---|---|---|---|
| `PATH_GLPI_RELEASE_ROOT` | optional | release extraction root | absolute path | app role |
| `PATH_GLPI_INSTALL_DIR` | optional | GLPI install directory | absolute path | app role |
| `PATH_GLPI_CONFIG_DIR` | optional | GLPI config directory | absolute path | app role |
| `PATH_GLPI_VAR_DIR` | optional | GLPI data directory | absolute path | app role |
| `PATH_GLPI_PLUGIN_DIR` | optional | GLPI plugin directory | absolute path | app role |
| `PATH_GLPI_LOG_DIR` | optional | GLPI log directory | absolute path | app role |
| `OPERATIONS_TIMEZONE` | yes | Host timezone | tz name; `America/Sao_Paulo` | base role |
| `OPERATIONS_GLPI_CRON_SCHEDULE` | optional | GLPI cron cadence | quoted cron | app role |
| `OPERATIONS_REQUIRED_OPS_GROUP` | optional | Required operator group | string; `glpiops` | precheck |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | yes | Default policy behavior | `secure` or `permissive` | precheck and deploy policy |

## Size profiles

`RESOURCE_PROFILE_ACTIVE` selects one of three predefined profile families: `small`, `medium`, `large`.

Each family has these tunables:

- `RESOURCE_PROFILE_<SIZE>_PHP_MAX_CHILDREN`
- `RESOURCE_PROFILE_<SIZE>_PHP_START_SERVERS`
- `RESOURCE_PROFILE_<SIZE>_PHP_MIN_SPARE_SERVERS`
- `RESOURCE_PROFILE_<SIZE>_PHP_MAX_SPARE_SERVERS`
- `RESOURCE_PROFILE_<SIZE>_PHP_MAX_REQUESTS`
- `RESOURCE_PROFILE_<SIZE>_MARIADB_INNODB_BUFFER_POOL_SIZE`
- `RESOURCE_PROFILE_<SIZE>_MARIADB_MAX_CONNECTIONS`
- `RESOURCE_PROFILE_<SIZE>_MARIADB_TMP_TABLE_SIZE`
- `RESOURCE_PROFILE_<SIZE>_MARIADB_MAX_HEAP_TABLE_SIZE`
- `RESOURCE_PROFILE_<SIZE>_MARIADB_SLOW_QUERY_LOG`
- `RESOURCE_PROFILE_<SIZE>_MARIADB_LONG_QUERY_TIME`

These values are rendered into `public.runtime.yml` and applied by Ansible roles.
