# Appendix - Runtime Input and Runtime Files (EN)

This appendix explains how configuration and runtime data flow through the project, so you can quickly understand where each value comes from and where each generated file is used.

## Public vs secret input

All deployment values live in `config/<environment>.env`, created from `config/product.env`. This includes host endpoints, topology mode, TLS mode, package/tuning values, policy flags, and required secrets. Scripts materialize `.runtime/<environment>/secrets.yml` from this file for Ansible consumption.

In practice, you edit public values once in `config/<environment>.env`, run `deploy check`, and let the scripts render the runtime files used by Ansible.

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

## Conditional runtime rules

When execution mode is `local`, SSH reachability checks are not required, and role-scoped commands must run on the correct host in dual-server topology. When execution mode is `ssh`, key material and remote reachability become mandatory checks. When `TLS_MODE=provided`, local certificate and key paths must point to real files. Security policy flags (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_SSO`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`) are always evaluated, and their blocking behavior depends on effective `SECURITY_MODE`.
