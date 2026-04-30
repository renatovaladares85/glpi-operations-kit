# Appendix: Runtime Input and Runtime Files Reference

## 1. Public configuration source

Main files:

- `config/staging.yml`
- `config/production.yml`
- `config/product.example.yml`

Public values are read from config files and rendered into runtime artifacts automatically.

## 2. Runtime file map

| File | Type | Producer | Consumer | Sensitivity | Purpose |
|---|---|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | Generated | `glpictl` + renderer | Ansible inventory | restricted | Host targets and SSH access model |
| `.runtime/<env>/public.runtime.yml` | Generated | `glpictl` + renderer | Ansible vars | restricted | Public operational values converted to role variables |
| `.runtime/<env>/overrides.runtime.yml` | Mutable runtime | `glpictl` / operators | Ansible vars | restricted | Runtime overrides for mutable behavior (for example TLS transition) |
| `.runtime/<env>/secrets.yml` | Runtime secret | operator prompts | Ansible vars | secret | Secret-only values not versioned in Git |
| `.runtime/<env>/state/deploy-sequence.yml` | Generated state | `glpictl` | `glpictl` | restricted | Mandatory execution order control |
| `.runtime/<env>/state/precheck-report-latest.yml` | Generated state | precheck | operators/audit | restricted | Structured prerequisite status |
| `.runtime/<env>/evidence/precheck-report-latest.md` | Generated evidence | precheck | operators/audit | restricted | Human-readable prerequisite report |

## 3. Merge precedence

Values are merged in this order:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Operational impact:

- public baseline comes from `config/<env>.yml`
- mutable overrides change behavior without rewriting baseline
- secrets always win over public values for secret keys

## 4. Required runtime secrets

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

If missing:

- script prompts interactively
- script blocks until required secret is provided

## 5. Conditional runtime requirements

- When `tls.mode=provided`:
  - `tls.provided_local_cert_path` and `tls.provided_local_key_path` must be valid local files.
- When `topology.mode=dual-server`:
  - SSH key pair and target connectivity checks are mandatory.
- In production:
  - TLS/HTTPS and SSO policy gates are mandatory.
