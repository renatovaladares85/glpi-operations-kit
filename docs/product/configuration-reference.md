# GLPI Product Configuration Reference

## Purpose

This document defines the public configuration contract for the GLPI Operations Kit after migration to the single `key=value` model.

Canonical files:

- `config/.env.example` (versioned template)
- `config/<environment>.env` (operator-created environment copy; do not commit real copies)
- `.runtime/<environment>/secrets.yml` (runtime secrets, never versioned)

Template contract:

- `config/.env.example` keeps only mandatory baseline keys uncommented.
- Optional or scenario-specific keys stay commented by default and are activated only when explicitly uncommented.
- Commented keys are treated as not configured.

For operator-oriented field-by-field guidance, use:

- PT-BR: [Guia de Preenchimento do Ambiente](../manual/pt-br/appendices/configuration-field-guide.md)
- EN: [Environment Configuration Field Guide](../manual/en/appendices/configuration-field-guide.md)

## Configuration flow

1. Operator creates `config/<environment>.env` from `config/.env.example`.
2. Scripts load `config/<environment>.env` automatically.
3. Scripts render `.runtime/<environment>/public.runtime.yml` and `.runtime/<environment>/inventory.runtime.yml`.
4. Deployment secrets read from the environment file are materialized into `.runtime/<environment>/secrets.yml` with restricted permissions.
5. Ansible consumes `public.runtime.yml`, `overrides.runtime.yml`, and `secrets.yml`.

## Runtime precedence

Runtime values are merged in this order:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

## Contract groups

- `PRODUCT_*`, `CUSTOMER_*`, `ENVIRONMENT_*`: product/customer metadata
- `EXECUTION_*`, `TOPOLOGY_*`: orchestration model and host scope
- `NETWORK_*`: SSH and DB access policy/source restrictions
- `GLPI_*`, `PHP_FPM_*`, `WEB_*`: application stack settings
- `GLPI_REDIS_*`: Redis cache/session integration options
- `DATABASE_*`: database baseline and packages
- `TLS_*`: TLS mode and certificate paths
- `BACKUP_*`: backup base directory and retention
- `MONITORING_*`, `ALERTING_*`: exporter toggles, labels, thresholds, routes
- `SECURITY_*`: policy flags and controls
- `EMAIL_MAILPIT_*`: optional post-deploy Mailpit service controls
- `PATH_*`: secure filesystem layout
- `OPERATIONS_*`: timezone, cron, ops group, security mode default
- `GLPI_TIMEZONE_*`: optional GLPI timezone support controls (PHP + DB readiness workflow)
- `RESOURCE_PROFILE_*`: size profile selection and tuning for `small|medium|large`

Legacy `AUTH_*` and `SSO_*` keys may exist in older environment files and are ignored by execution flows.

## High-impact keys

| Key | Why it matters | Typical values |
|---|---|---|
| `EXECUTION_MODE` | Defines local or SSH orchestration model. | `local`, `ssh` |
| `EXECUTION_HOST_ROLE_DEFAULT` | Prevents wrong mutable actions on wrong hosts in local mode. | `app`, `db`, `all` |
| `TOPOLOGY_MODE` | Defines single-host or split-host behavior. | `single-server`, `dual-server` |
| `DATABASE_DEPLOYMENT_MODE` | Defines self-hosted DB vs external managed DB flow. | `self_hosted`, `managed` |
| `WEB_SERVER_TYPE` | Selects the Linux web engine automated by this kit. | `nginx`, `apache`, `lighttpd` |
| `TLS_MODE` | Controls HTTP, self-signed TLS, or provided TLS flow. | `none`, `self_signed`, `provided` |
| `SECURITY_REQUIRE_*` | Enables policy checks for TLS/HTTPS/promotion/ordered execution. | `true`, `false` |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | Defines default enforcement mode when `SECURITY_MODE` is not passed. | `secure`, `permissive` |
| `RESOURCE_PROFILE_ACTIVE` | Selects the active tuning profile. | `small`, `medium`, `large` |
| `NETWORK_DATABASE_ACCESS_MODE` | Selects restricted or open DB access behavior. | `restricted`, `open` |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | Stores DB source hosts for restricted mode. | CSV host list or empty |
| `GLPI_TIMEZONE_SUPPORT_ENABLED` | Enables timezone readiness workflow. | `true`, `false` |
| `GLPI_TIMEZONE_DB_MODE` | Defines DB timezone behavior. | `disabled`, `validate`, `apply` |
| `GLPI_TIMEZONE_DB_LEGACY_GRANT` | Enables optional legacy grant on `mysql.time_zone_name`. | `true`, `false` |
| `GLPI_REDIS_SESSION_LOCKING` | Controls phpredis session locking. Default keeps locking disabled for concurrent GLPI AJAX requests. | `0`, `1` |
| `GLPI_REDIS_CACHE_PREFIX` | Optional GLPI Redis cache namespace prefix. Empty uses `glpi_cache_<hostname>:`. | string |
| `EMAIL_MAILPIT_ENABLED` | Enables the post-deploy Mailpit install workflow. | `true`, `false` |
| `EMAIL_MAILPIT_UI_PATH` | Publishes Mailpit UI through the GLPI web protocol/port. | `/mailpit` |

## Conditional activation and validation contract

- `EXECUTION_MODE=ssh`: requires `NETWORK_SSH_USER` and `NETWORK_SSH_PRIVATE_KEY_PATH` with an existing private key file.
- `DATABASE_DEPLOYMENT_MODE=managed`: DB Linux-host actions are not applicable; DB checks use direct MySQL TCP connectivity.
- `GLPI_TIMEZONE_SUPPORT_ENABLED=true`: timezone workflow validates OS/PHP and can validate/apply DB timezone tables according to `GLPI_TIMEZONE_DB_MODE`.
- Redis is installed and configured on GLPI app hosts by default for GLPI cache (DB 0) and PHP-FPM sessions (DB 1).
- `TLS_MODE=provided`: requires `TLS_PROVIDED_LOCAL_CERT_PATH` and `TLS_PROVIDED_LOCAL_KEY_PATH` pointing to existing local files.
- `EMAIL_MAILPIT_ENABLED=true`: enables `glpictl email prepare/install mailpit`; Docker/Compose must already exist on the app host.

## Secret contract

Deployment secrets required by renderer/precheck from `config/<environment>.env` are:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD` when `DATABASE_DEPLOYMENT_MODE=self_hosted`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD` when `DATABASE_DEPLOYMENT_MODE=self_hosted`
- `DATABASE_MANAGED_ADMIN_PASSWORD` (optional, managed-mode fallback for connectivity checks)

Do not commit real environment files, `.runtime/`, private keys, tokens, passwords, certificates with private material, or customer-sensitive evidence.

Mailpit UI/SMTP auth is prompted by `glpictl email prepare mailpit` and stored as protected htpasswd files under `.runtime/<environment>/email/auth/`, not in `config/<environment>.env`.

## Web engine and package resolution contract

`WEB_SERVER_TYPE` must be one of:

- `nginx`
- `apache`
- `lighttpd`

`GLPI_APP_PACKAGES` behavior:

- Empty (`GLPI_APP_PACKAGES=`): automatic package mapping from renderer.
- Filled: full manual override; operator owns coherence with selected engine.

Automatic source of truth is `scripts/lib/render_product_config.py`, which detects the local platform family from `/etc/os-release` and maps:

- `WEB_SERVER_PACKAGES[WEB_SERVER_TYPE]` for Ubuntu/Debian or Rocky/RHEL-like
- plus `DEFAULT_GLPI_APP_PACKAGES` including PHP extensions, Redis, and a MySQL-compatible client for APP -> DB checks

Platform-sensitive defaults:

| Setting | Ubuntu/Debian | Rocky/RHEL-like |
|---|---|---|
| GLPI filesystem owner/group | `www-data:www-data` | `apache:apache` |
| PHP-FPM service | `php8.3-fpm` | `php-fpm` |
| PHP-FPM socket | `/run/php/php8.3-fpm.sock` | `/run/php-fpm/glpi.sock` |
| MySQL-compatible client package | `mariadb-client` | `mysql` |
| Python YAML package | `python3-yaml` | `python3-PyYAML` |

Redis memory sizing is not forced by default. `GLPI_REDIS_MAXMEMORY` and `GLPI_REDIS_MAXMEMORY_POLICY` are optional overrides and should be set only after host capacity is known.
