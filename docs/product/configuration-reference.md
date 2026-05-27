# GLPI Product Configuration Reference

## Purpose

This document defines the public configuration contract for the GLPI Operations Kit after migration to the single `key=value` model.

Canonical files:

- `config/product.env` (versioned template)
- `config/<environment>.env` (operator-created environment copy; do not commit real copies)
- `.runtime/<environment>/secrets.yml` (runtime secrets, never versioned)

Template contract:

- `config/product.env` keeps only mandatory baseline keys uncommented.
- Optional or scenario-specific keys stay commented by default and are activated only when explicitly uncommented.
- Commented keys are treated as not configured.

For operator-oriented field-by-field guidance, use:

- PT-BR: [Guia de Preenchimento do Ambiente](../manual/pt-br/appendices/configuration-field-guide.md)
- EN: [Environment Configuration Field Guide](../manual/en/appendices/configuration-field-guide.md)

## Configuration flow

1. Operator creates `config/<environment>.env` from `config/product.env`.
2. Scripts load `config/<environment>.env` automatically.
3. Scripts render `.runtime/<environment>/public.runtime.yml` and `.runtime/<environment>/inventory.runtime.yml`.
4. Deployment secrets currently read from the environment file are materialized into `.runtime/<environment>/secrets.yml` with restricted permissions.
5. External-auth secrets must be provided only in `.runtime/<environment>/secrets.yml`.
6. Ansible consumes `public.runtime.yml`, `overrides.runtime.yml`, and `secrets.yml`.

## Runtime precedence

Runtime values are merged in this order:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Operationally:

- public defaults and customer values stay in `config/<environment>.env`;
- mutable runtime adjustments stay in `.runtime/<environment>/overrides.runtime.yml`;
- secrets stay in `.runtime/<environment>/secrets.yml` at execution time;
- `.runtime/` is never versioned.

## Contract groups

The configuration keys are grouped by operational domain:

- `PRODUCT_*`, `CUSTOMER_*`, `ENVIRONMENT_*`: product/customer metadata
- `EXECUTION_*`, `TOPOLOGY_*`: orchestration model and host scope
- `NETWORK_*`: SSH and DB access policy/source restrictions
- `GLPI_*`, `PHP_FPM_*`, `WEB_*`: application stack settings
- `DATABASE_*`: database baseline and packages
- `TLS_*`: TLS mode and certificate paths
- `BACKUP_*`: backup base directory and retention
- `MONITORING_*`, `ALERTING_*`: exporter toggles, labels, thresholds, routes
- `AUTH_*`, `SSO_*`: optional authentication and SSO preparation/validation
- `SECURITY_*`: policy flags and controls
- `PATH_*`: secure filesystem layout
- `OPERATIONS_*`: timezone, cron, ops group, security mode default
- `GLPI_TIMEZONE_*`: optional GLPI timezone support controls (PHP + DB readiness workflow)
- `RESOURCE_PROFILE_*`: size profile selection and tuning for `small|medium|large`

## High-impact keys

| Key | Why it matters | Typical values |
|---|---|---|
| `EXECUTION_MODE` | Defines whether orchestration runs locally on each host or remotely by SSH. | `local`, `ssh` |
| `EXECUTION_HOST_ROLE_DEFAULT` | Prevents wrong mutable actions on wrong hosts in local mode. | `app`, `db`, `all` |
| `TOPOLOGY_MODE` | Defines single-host or split-host behavior. | `single-server`, `dual-server` |
| `DATABASE_DEPLOYMENT_MODE` | Defines if DB host is managed by this kit or external managed DB (for example AWS RDS). | `self_hosted`, `managed` |
| `WEB_SERVER_TYPE` | Selects the single Linux web engine automated by this kit. | `nginx`, `apache`, `lighttpd` |
| `TLS_MODE` | Controls HTTP, self-signed TLS, or provided TLS flow. | `none`, `self_signed`, `provided` |
| `AUTH_MODE` | Controls optional authentication preparation/validation. | `local`, `ldap`, `saml`, `oidc` |
| `SECURITY_REQUIRE_*` | Enables policy checks for TLS, HTTPS, SSO, promotion gate, and ordered execution. | `true`, `false` |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | Defines default enforcement mode when `SECURITY_MODE` is not passed. | `secure`, `permissive` |
| `RESOURCE_PROFILE_ACTIVE` | Selects the active tuning profile used by runtime rendering. | `small`, `medium`, `large` |
| `NETWORK_DATABASE_ACCESS_MODE` | Selects restricted or open DB access behavior. | `restricted`, `open` |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | Stores DB source hosts for restricted mode. | CSV host list or empty |
| `GLPI_TIMEZONE_SUPPORT_ENABLED` | Enables timezone readiness workflow (PHP + DB checks). | `true`, `false` |
| `GLPI_TIMEZONE_DB_MODE` | Defines DB timezone behavior for GLPI timezone support. | `disabled`, `validate`, `apply` |
| `GLPI_TIMEZONE_DB_LEGACY_GRANT` | Enables optional legacy grant on `mysql.time_zone_name`. | `true`, `false` |
| `MONITORING_*_JSON` | Centralizes labels, thresholds, scrape profiles, alert routes. | one-line JSON objects |

Notes for DB access controls:

- `NETWORK_DATABASE_ACCESS_MODE` defaults to `restricted` when omitted.
- `restricted` uses a comma-separated allowlist such as `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=192.0.2.10,192.0.2.11`.
- `open` uses `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=` (active and empty).
- Commented keys are considered not used; uncommented keys are active configuration.

## Conditional activation and validation contract

Configuration validation is scenario-aware and fails early when a feature is enabled without its required keys.

- `EXECUTION_MODE=ssh`: requires `NETWORK_SSH_USER` and `NETWORK_SSH_PRIVATE_KEY_PATH` with an existing private key file.
- `DATABASE_DEPLOYMENT_MODE=managed`: DB Linux-host actions are not applicable; DB checks use direct MySQL TCP connectivity.
- `GLPI_TIMEZONE_SUPPORT_ENABLED=true`: timezone workflow validates OS/PHP and can validate/apply DB timezone tables according to `GLPI_TIMEZONE_DB_MODE`.
- `TLS_MODE=provided`: requires `TLS_PROVIDED_LOCAL_CERT_PATH` and `TLS_PROVIDED_LOCAL_KEY_PATH` pointing to existing local files.
- External auth enabled (`AUTH_MODE!=local` or `AUTH_*_ENABLED=true`): requires coherent auth mode and `SSO_PUBLIC_URL` when URL enforcement is enabled.
- SAML/OIDC enabled: requires `SSO_PUBLIC_URL` with `https://` and blocks `TLS_MODE=none`.
- `SECURITY_REQUIRE_SSO=true`: requires `SECURITY_SSO_ENABLED=true`.

## Secret contract

Deployment secrets currently required by renderer/precheck from `config/<environment>.env` are:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD` when `DATABASE_DEPLOYMENT_MODE=self_hosted`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD` when `DATABASE_DEPLOYMENT_MODE=self_hosted`
- `DATABASE_MANAGED_ADMIN_PASSWORD` (optional, only for managed-mode fallback connectivity attempts with `root`/`admin`)

External-auth sensitive values are runtime-only and must stay in `.runtime/<environment>/secrets.yml`:

- `auth_saml_x509_certificate`
- `ldap_bind_password`
- `oidc_client_secret`

Do not commit real environment files, `.runtime/`, private keys, tokens, passwords, certificates with private material, or customer-sensitive evidence.

## Web engine and package resolution contract

`WEB_SERVER_TYPE` must be one of:

- `nginx`
- `apache`
- `lighttpd`

IIS is supported by upstream GLPI as a possible web server technology, but this Linux automation kit does not automate IIS.

`GLPI_APP_PACKAGES` behavior:

- Empty (`GLPI_APP_PACKAGES=`): automatic package mapping from renderer.
- Filled: full manual override; operator owns coherence with selected engine.

Automatic source of truth is `scripts/lib/render_product_config.py`, which maps:

- `WEB_SERVER_PACKAGES[WEB_SERVER_TYPE]`
- plus `DEFAULT_GLPI_APP_PACKAGES` including PHP extensions and `mariadb-client` for APP -> DB checks.
