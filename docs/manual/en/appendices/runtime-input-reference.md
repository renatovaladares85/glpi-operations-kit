# Appendix: Runtime Input and Runtime Files Reference

## 1. Public configuration source

Primary files:

- `config/product.example.yml`
- `config/<environment>.yml` (created from `product.example.yml`)

All non-secret operational values are read from these files.

## 2. Execution contract keys (public)

These keys control how scripts run:

- `execution.mode`: `local` or `ssh`
- `execution.host_role_default`: `app`, `db`, or `all`

Environment variable overrides:

- `GLPI_EXECUTION_MODE`
- `GLPI_HOST_ROLE`
- `GLPI_ENVIRONMENT`

## 3. Runtime artifact map

| File | Type | Producer | Consumer | Sensitivity | Operational purpose |
|---|---|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | generated | renderer via `glpictl` | Ansible inventory | restricted | host targeting and connection model (`local` or `ssh`) |
| `.runtime/<env>/public.runtime.yml` | generated | renderer via `glpictl` | Ansible vars | restricted | public operational data converted to role variables |
| `.runtime/<env>/overrides.runtime.yml` | mutable runtime | `glpictl` / operator | Ansible vars | restricted | mutable overrides without editing `config/<env>.yml` |
| `.runtime/<env>/secrets.yml` | runtime secret | operator prompts | Ansible vars | secret | non-versioned credentials and secret values |
| `.runtime/<env>/state/precheck-report-latest.yml` | generated state | precheck | operators/audit | restricted | machine-readable prerequisite and policy status |
| `.runtime/<env>/evidence/precheck-report-latest.md` | generated evidence | precheck | operators/audit | restricted | human-readable prerequisite report |
| `.runtime/<env>/state/deploy-sequence.yml` | generated state | `glpictl` | `glpictl` | restricted | ordered deployment state tracking |
| `.runtime/<env>/state/security-mode-last.yml` | generated state | `glpictl` | operators/audit | restricted | last accepted permissive-mode risk context |
| `.runtime/<env>/evidence/security-mode-*.yml` | generated evidence | `glpictl` | operators/audit | restricted | historical permissive-mode policy exceptions |
| `.runtime/<env>/logs/*.log` and `*.summary.yml` | generated log | operational scripts | operators/audit | restricted | execution trace and compact operation summary |

## 4. Runtime merge precedence

Values are merged in this order:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Practical meaning:

- baseline comes from `config/<env>.yml`
- mutable operations (for example TLS switching) are written to overrides
- secrets always come from secret runtime file

## 5. Mandatory secret keys

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

Behavior when missing:

- scripts prompt interactively
- mutable execution remains blocked until values are provided

## 6. Conditional requirements

- If `execution.mode=local`:
  - no remote SSH connectivity validation is required.
  - in dual-server topology, run DB and APP actions on their respective hosts.
- If `execution.mode=ssh`:
  - SSH key pair and remote connectivity checks are mandatory.
- If `tls.mode=provided`:
  - `tls.provided_local_cert_path` and `tls.provided_local_key_path` must point to existing local files.
- If security flags are enabled:
  - `security.require_tls=true` requires `tls.mode=provided`.
  - `security.require_https=true` requires TLS enabled (`self_signed` or `provided`).
  - `security.require_sso=true` requires `security.sso_enabled=true`.
  - `security.require_promotion_gate=true` requires `.runtime/promotion/staging-certified.yml`.

## 7. Security mode policy handling

- `SECURITY_MODE=secure`: policy violations block mutable operations.
- `SECURITY_MODE=permissive`: policy violations become warnings and are persisted with justification.
