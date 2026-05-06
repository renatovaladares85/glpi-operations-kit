# GLPI Product Configuration Reference

## Purpose

This document defines the public configuration contract for the GLPI Operations Kit after migration to the single `key=value` model.

Canonical files:

- `config/product.env` (versioned template)
- `config/<environment>.env` (operator-created copy)
- `.runtime/<environment>/secrets.yml` (runtime secrets, never versioned)

`config/product.env` is the canonical field dictionary. Every key in that template already includes purpose, expected format, example, and operational impact.

## Configuration flow

1. Operator creates `config/<environment>.env` from `config/product.env`.
2. Scripts load `config/<environment>.env` automatically.
3. Scripts render `.runtime/<environment>/public.runtime.yml` and `.runtime/<environment>/inventory.runtime.yml`.
4. Secret keys are read from `config/<environment>.env` and materialized into `.runtime/<environment>/secrets.yml`.
5. If a required secret key is missing in `config/<environment>.env`, execution fails early with explicit remediation.
5. Ansible consumes `public.runtime.yml`, `overrides.runtime.yml`, and `secrets.yml`.

## Runtime precedence

Runtime values are merged in this order:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Operationally:

- public defaults and customer values stay in `config/<environment>.env`
- mutable runtime adjustments stay in `.runtime/<environment>/overrides.runtime.yml`
- secrets stay only in `.runtime/<environment>/secrets.yml`

## Contract groups

The configuration keys are grouped by operational domain:

- `PRODUCT_*`, `CUSTOMER_*`, `ENVIRONMENT_*`: product/customer metadata
- `EXECUTION_*`, `TOPOLOGY_*`: orchestration model and host scope
- `NETWORK_*`: SSH and DB source restrictions
- `GLPI_*`, `PHP_FPM_*`, `NGINX_*`: application stack settings
- `DATABASE_*`: database baseline and packages
- `TLS_*`: TLS mode and certificate paths
- `BACKUP_*`: backup base directory and retention
- `MONITORING_*`, `ALERTING_*`: exporter toggles, labels, thresholds, routes
- `SECURITY_*`: policy flags and controls
- `PATH_*`: secure filesystem layout
- `OPERATIONS_*`: timezone, cron, ops group, security mode default
- `RESOURCE_PROFILE_*`: size profile selection and tuning for `small|medium|large`

## High-impact keys

| Key | Why it matters | Typical values |
|---|---|---|
| `EXECUTION_MODE` | Defines whether orchestration runs locally on each host or remotely by SSH. | `local`, `ssh` |
| `EXECUTION_HOST_ROLE_DEFAULT` | Prevents wrong mutable actions on wrong hosts in local mode. | `app`, `db`, `all` |
| `TOPOLOGY_MODE` | Defines single-host or split-host behavior. | `single-server`, `dual-server` |
| `TLS_MODE` | Controls HTTP, self-signed TLS, or provided TLS flow. | `none`, `self_signed`, `provided` |
| `SECURITY_REQUIRE_*` | Enables policy checks for TLS, HTTPS, SSO, promotion gate, and ordered execution. | `true`, `false` |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | Defines default enforcement mode when `SECURITY_MODE` is not passed. | `secure`, `permissive` |
| `RESOURCE_PROFILE_ACTIVE` | Selects the active tuning profile used by runtime rendering. | `small`, `medium`, `large` |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | Restricts DB access surface. | CSV host list |
| `MONITORING_*_JSON` | Centralizes labels, thresholds, scrape profiles, alert routes. | one-line JSON objects |

## Secret keys (runtime only)

The minimum required secret keys in `config/<environment>.env` are:

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

Secrets are never versioned in Git. They are copied from the environment file into runtime secret artifacts and restricted on disk.

## Web engine and package resolution contract

`WEB_SERVER_TYPE` is mandatory and must be one of:

- `nginx`
- `apache`
- `lighttpd`

`GLPI_APP_PACKAGES` behavior:

- Empty (`GLPI_APP_PACKAGES=`): automatic package mapping from renderer.
- Filled: full manual override (operator owns coherence with selected engine).

Automatic source of truth is `scripts/lib/render_product_config.py`, which maps:

- `WEB_SERVER_PACKAGES[WEB_SERVER_TYPE]`
- plus `DEFAULT_GLPI_APP_PACKAGES` (including `php-bcmath` and `mariadb-client` in the baseline).
