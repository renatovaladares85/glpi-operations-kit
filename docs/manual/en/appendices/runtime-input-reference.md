# Appendix - Runtime Input and Runtime Files (EN)

This appendix explains how configuration and runtime data flow through the project, so you can quickly understand where each value comes from and where each generated file is used.

## Public vs secret input

Public deployment values live in `config/<environment>.env`, created from `config/product.env`. This includes host endpoints, topology mode, TLS mode, package/tuning values, and policy flags. Deployment DB secrets read from that file (`DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD`, and optional `DATABASE_MANAGED_ADMIN_PASSWORD`) are materialized into `.runtime/<environment>/secrets.yml`.

Template baseline behavior:

- `config/product.env` keeps only mandatory baseline keys uncommented.
- Optional and scenario-specific keys stay commented until the scenario is explicitly enabled.

## How automatic `GLPI_APP_PACKAGES` works

`GLPI_APP_PACKAGES` follows two modes:

- Automatic mode: keep `GLPI_APP_PACKAGES=` empty in `config/<environment>.env`.
- Manual override mode: set `GLPI_APP_PACKAGES` with a full comma-separated package list.

When automatic mode is used, package resolution is done by `scripts/lib/render_product_config.py` with `WEB_SERVER_PACKAGES[WEB_SERVER_TYPE] + DEFAULT_GLPI_APP_PACKAGES`.

## Runtime file map

| File | Who creates it | Why it exists | Who consumes it |
|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | config renderer via `glpictl` | Encodes the effective host targeting model (`local` or `ssh`) | `ansible-inventory`, `ansible-playbook` |
| `.runtime/<env>/public.runtime.yml` | config renderer via `glpictl` | Converts public `key=value` settings into role-ready variables | `ansible-playbook` |
| `.runtime/<env>/overrides.runtime.yml` | scripts and operator actions | Stores mutable runtime overrides (for example TLS changes) | `ansible-playbook` |
| `.runtime/<env>/secrets.yml` | renderer from `config/<env>.env` | Stores secret values outside Git with restricted permissions | `ansible-playbook` |
| `.runtime/<env>/state/precheck-report-latest.yml` | precheck | Machine-readable precheck and policy status | operators, audit flow |
| `.runtime/<env>/evidence/precheck-report-latest.md` | precheck | Human-readable precheck summary | operators, audit flow |
| `.runtime/<env>/state/deploy-sequence.yml` | deploy workflow | Tracks ordered execution state | `glpictl` |
| `.runtime/<env>/state/security-mode-last.yml` | permissive-mode policy handler | Records latest risk acceptance context | operators, audit flow |
| `.runtime/<env>/evidence/security-mode-*.yml` | permissive-mode policy handler | Keeps historical policy exceptions and justifications | operators, audit flow |
| `.runtime/<env>/logs/*.log` and `*.summary.yml` | operational scripts | Maintains execution trace and compact run summaries | operators, troubleshooting, audit |

## Merge precedence at execution time

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

## Execution contract values

`GLPI_EXECUTION_MODE`, `GLPI_HOST_ROLE`, and `SECURITY_MODE` can be passed as temporary overrides, but default behavior comes from `EXECUTION_MODE`, `EXECUTION_HOST_ROLE_DEFAULT`, and `OPERATIONS_SECURITY_MODE_DEFAULT`.

## Mandatory secret keys

The minimum required keys in `config/<environment>.env` for secret materialization are:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD` when `DATABASE_DEPLOYMENT_MODE=self_hosted`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD` when `DATABASE_DEPLOYMENT_MODE=self_hosted`

Optional managed-mode fallback key:

- `DATABASE_MANAGED_ADMIN_PASSWORD`

If any required key is missing, scripts fail early and block mutable operations.

## Conditional runtime rules

When execution mode is `local`, SSH reachability checks are not required, and role-scoped commands must run on the correct host in dual-server topology.

When execution mode is `ssh`, key material and remote reachability become mandatory checks:

- `NETWORK_SSH_USER` must be active.
- `NETWORK_SSH_PRIVATE_KEY_PATH` must be active and point to a real file.

When `TLS_MODE=provided`, local certificate and key paths must be active and point to real files:

- `TLS_PROVIDED_LOCAL_CERT_PATH`
- `TLS_PROVIDED_LOCAL_KEY_PATH`

Policy flags (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`) are always evaluated, and their blocking behavior depends on effective `SECURITY_MODE`.

Legacy `AUTH_*` / `SSO_*` keys may exist in older environment files and are ignored by execution flows.
