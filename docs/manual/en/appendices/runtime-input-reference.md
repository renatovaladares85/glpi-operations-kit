# Appendix - Runtime Input and Runtime Files (EN)

This appendix explains how configuration and runtime data flow through the project, so you can quickly understand where each value comes from and where each generated file is used.

## Public vs secret input

Public deployment values live in `config/<environment>.env`, created from `config/product.env`. This includes host endpoints, topology mode, TLS mode, package/tuning values, and policy flags. The 3 deployment secrets read from that file (`DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD`) are materialized into `.runtime/<environment>/secrets.yml`; external-auth secrets are runtime-only and must stay only in `.runtime/<environment>/secrets.yml`.

Template baseline behavior:

- `config/product.env` keeps only mandatory baseline keys uncommented.
- Optional and scenario-specific keys stay commented until the scenario is explicitly enabled.

In practice, you edit public values once in `config/<environment>.env`, run `deploy check`, and let the scripts render the runtime files used by Ansible.

## How automatic `GLPI_APP_PACKAGES` works

`GLPI_APP_PACKAGES` follows two modes:

- Automatic mode: keep `GLPI_APP_PACKAGES=` empty in `config/<environment>.env`.
- Manual override mode: set `GLPI_APP_PACKAGES` with a full comma-separated package list.

When automatic mode is used, package resolution is done by the renderer in `scripts/lib/render_product_config.py`, using:

- `WEB_SERVER_PACKAGES` (web-server-specific packages)
- `DEFAULT_GLPI_APP_PACKAGES` (common PHP and utility packages)

Effective logic:

1. Read `WEB_SERVER_TYPE`.
2. Build packages as `WEB_SERVER_PACKAGES[WEB_SERVER_TYPE] + DEFAULT_GLPI_APP_PACKAGES`.
3. If `GLPI_APP_PACKAGES` is explicitly set, use it as a full override.

Examples in `config/<environment>.env`:

- Nginx automatic:
  - `WEB_SERVER_TYPE=nginx`
  - `GLPI_APP_PACKAGES=`
- Apache automatic:
  - `WEB_SERVER_TYPE=apache`
  - `GLPI_APP_PACKAGES=`
- lighttpd automatic:
  - `WEB_SERVER_TYPE=lighttpd`
  - `GLPI_APP_PACKAGES=`
- Linux-supported web server values:
  - `WEB_SERVER_TYPE=nginx`
  - `WEB_SERVER_TYPE=apache`
  - `WEB_SERVER_TYPE=lighttpd`

Manual override examples:

- Nginx:
  - `WEB_SERVER_TYPE=nginx`
  - `GLPI_APP_PACKAGES=nginx,php-fpm,php-cli,php-curl,php-gd,php-intl,php-mbstring,php-bcmath,php-mysql,php-xml,php-zip,php-bz2,php-apcu,php-ldap,php-imap,php-opcache,php-redis,tar,xz-utils,curl,openssl,mariadb-client`
- Apache:
  - `WEB_SERVER_TYPE=apache`
  - `GLPI_APP_PACKAGES=apache2,libapache2-mod-fcgid,libapache2-mod-php8.3,php-fpm,php-cli,php-curl,php-gd,php-intl,php-mbstring,php-bcmath,php-mysql,php-xml,php-zip,php-bz2,php-apcu,php-ldap,php-imap,php-opcache,php-redis,tar,xz-utils,curl,openssl,mariadb-client`
- lighttpd:
  - `WEB_SERVER_TYPE=lighttpd`
  - `GLPI_APP_PACKAGES=lighttpd,php-fpm,php-cli,php-curl,php-gd,php-intl,php-mbstring,php-bcmath,php-mysql,php-xml,php-zip,php-bz2,php-apcu,php-ldap,php-imap,php-opcache,php-redis,tar,xz-utils,curl,openssl,mariadb-client`

## Runtime file map

| File | Who creates it | Why it exists | Who consumes it |
|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | config renderer via `glpictl` | Encodes the effective host targeting model (`local` or `ssh`) for this execution | `ansible-inventory`, `ansible-playbook` |
| `.runtime/<env>/public.runtime.yml` | config renderer via `glpictl` | Converts public `key=value` settings into role-ready variables | `ansible-playbook` |
| `.runtime/<env>/overrides.runtime.yml` | scripts and operator actions | Stores mutable runtime overrides (for example TLS changes) without editing baseline config | `ansible-playbook` |
| `.runtime/<env>/secrets.yml` | renderer from `config/<env>.env` | Stores secret values outside Git with restricted permissions | `ansible-playbook` |
| `.runtime/<env>/state/precheck-report-latest.yml` | precheck | Machine-readable precheck and policy status | operators, audit flow |
| `.runtime/<env>/evidence/precheck-report-latest.md` | precheck | Human-readable precheck summary | operators, audit flow |
| `.runtime/<env>/state/deploy-sequence.yml` | deploy workflow | Tracks ordered execution state for gated stages | `glpictl` |
| `.runtime/<env>/state/security-mode-last.yml` | permissive-mode policy handler | Records latest risk acceptance context | operators, audit flow |
| `.runtime/<env>/evidence/security-mode-*.yml` | permissive-mode policy handler | Keeps historical policy exceptions and justifications | operators, audit flow |
| `.runtime/<env>/logs/*.log` and `*.summary.yml` | operational scripts | Maintains execution trace and compact run summaries | operators, troubleshooting, audit |

## Merge precedence at execution time

When Ansible runs, variable precedence is explicit:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

The operational meaning is straightforward: baseline settings come from `config/<environment>.env`, mutable operational changes are layered in overrides, and sensitive values are injected last from secrets.

## Execution contract values

`GLPI_EXECUTION_MODE`, `GLPI_HOST_ROLE`, and `SECURITY_MODE` can be passed as temporary overrides, but default behavior comes from the environment file keys `EXECUTION_MODE`, `EXECUTION_HOST_ROLE_DEFAULT`, and `OPERATIONS_SECURITY_MODE_DEFAULT`.

## Mandatory secret keys

The minimum required keys in `config/<environment>.env` for secret materialization are:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD`

If any of them are missing in `config/<environment>.env`, scripts fail early and block mutable operations until the environment file is complete.

External-auth secrets must not be committed and must remain only in `.runtime/<environment>/secrets.yml`:

- `auth_saml_x509_certificate`
- `ldap_bind_password`
- `oidc_client_secret`

## Conditional runtime rules

When execution mode is `local`, SSH reachability checks are not required, and role-scoped commands must run on the correct host in dual-server topology.

When execution mode is `ssh`, key material and remote reachability become mandatory checks:

- `NETWORK_SSH_USER` must be active.
- `NETWORK_SSH_PRIVATE_KEY_PATH` must be active and point to a real file.

When `TLS_MODE=provided`, local certificate and key paths must be active and point to real files:

- `TLS_PROVIDED_LOCAL_CERT_PATH`
- `TLS_PROVIDED_LOCAL_KEY_PATH`

When external auth is enabled (`AUTH_MODE!=local` or `AUTH_*_ENABLED=true`), URL contract checks become active:

- `SSO_PUBLIC_URL` becomes required when URL enforcement is enabled.
- For SAML/OIDC scenarios, `SSO_PUBLIC_URL` must be `https://` and `TLS_MODE` cannot be `none`.

Policy flags (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_SSO`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`) are always evaluated, and their blocking behavior depends on effective `SECURITY_MODE`.
