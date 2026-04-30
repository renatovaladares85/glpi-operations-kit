# Environment Parameters Reference

## Purpose

This document explains each environment parameter used by scripts and Ansible, including:

- purpose
- consumer
- expected format
- example
- classification (`public`, `secret`, `mandatory`, `optional`, `conditional`)
- environment impact

## Public baseline files

- `config/staging.yml`
- `config/production.yml`
- `config/product.example.yml`

## Secret file

- `.runtime/<env>/secrets.yml`

## Key Groups

### `product.*`

- Purpose: product metadata and reusable kit identity.
- Consumer: documentation labels and runtime metadata.
- Classification: public, mandatory.

### `customer.*`

- Purpose: customer-facing labels without hardcoding real client names.
- Consumer: labels and reports.
- Classification: public, mandatory.

### `environment.*`

- Purpose: explicit environment selection (`staging`, `production`, or another configured environment).
- Consumer: runtime renderer, policy checks.
- Classification: public, mandatory.

### `execution.*`

- Purpose: defines whether execution is local per host or SSH remote.
- Consumer: scripts, precheck, runtime inventory renderer.
- Keys:
  - `execution.mode`: `local` or `ssh`
  - `execution.host_role_default`: `app`, `db`, or `all`
- Classification: public, mandatory.
- Override:
  - `GLPI_EXECUTION_MODE` and `GLPI_HOST_ROLE` can override config values per execution.

### `topology.*`

- Purpose: host model and targeting.
- Consumer: generated inventory (`glpi_app`, `glpi_db`).
- Classification:
  - `mode`: public, mandatory
  - hosts/aliases: public, mandatory
- Impact:
  - `dual-server` in `execution.mode=local` requires role-based per-host execution.
  - `dual-server` in `execution.mode=ssh` requires remote SSH connectivity checks.

### `network.ssh.*`

- Purpose: SSH execution path for Ansible.
- Consumer: generated inventory and precheck.
- Format:
  - `user`: Linux username
  - `private_key_path`: path to environment key
- Classification:
  - public, conditional-mandatory when `execution.mode=ssh`
- Impact:
  - in `ssh` mode, private key must be mode `0600`.

### `glpi.*`

- Purpose: GLPI version/domain/runtime limits.
- Consumer: app role templates and validation.
- Classification: public, mandatory.

### `database.*`

- Purpose: database schema/user/network values.
- Consumer: db role and app connectivity.
- Classification:
  - `name`, `user`, `port`: public, mandatory
  - tuning values: public, mandatory (with profile defaults)

### `tls.*`

- Purpose: TLS operating mode and certificate locations.
- Consumer: app role + TLS operations.
- Classification:
  - `mode`: public, mandatory
  - `provided_local_*`: conditional-mandatory when `mode=provided`
- Environment impact:
  - `security.require_tls=true` requires `mode=provided` in `secure` mode.

### `security.*`

- Purpose: environment security policy gates.
- Consumer: precheck + deploy policy enforcement.
- Keys:
  - `sso_enabled` (mandatory when `security.require_sso=true`)
  - `allow_insecure_non_production` (public policy flag)
  - `require_tls` (public policy flag)
  - `require_https` (public policy flag)
  - `require_sso` (public policy flag)
  - `require_promotion_gate` (public policy flag)
  - `require_ordered_execution` (public policy flag)
- Execution impact:
  - in `SECURITY_MODE=secure`, required policy violations block;
  - in `SECURITY_MODE=permissive`, required policy violations are warnings with evidence.

### `monitoring.*` and `alerting.*`

- Purpose: exporter defaults, thresholds, alert policy.
- Consumer: monitoring role and operational blueprint.
- Classification: public, mandatory for product baseline.

### `paths.*`

- Purpose: secure filesystem layout.
- Consumer: app role.
- Classification: public, mandatory.

### `operations.*`

- Purpose: timezone, cron schedule, ops group policy, and security mode default.
- Consumer: base/app role and scripts.
- Classification: public, mandatory.

### `resource_profiles.*`

- Purpose: capacity and tuning profile per environment.
- Consumer: renderer and runtime vars.
- Classification: public, mandatory.

## Detailed Key Table (Implementation-critical)

| Key | Purpose | Consumer | Example | Classification | Environment impact |
|---|---|---|---|---|---|
| `product.name` | product display name | docs/runtime metadata | `GLPI Operations Kit` | public, mandatory | all |
| `customer.display_name` | customer label | docs/monitoring labels | `Example Customer` | public, mandatory | all |
| `environment.name` | runtime selector | scripts/renderer | `staging` | public, mandatory | all |
| `execution.mode` | execution model selector | scripts/renderer/precheck | `local` | public, mandatory | local vs ssh orchestration |
| `execution.host_role_default` | default host role selector | scripts/precheck | `app` | public, mandatory | local action scoping |
| `topology.mode` | topology behavior | precheck/deploy | `dual-server` | public, mandatory | drives SSH checks |
| `topology.app.host` | app endpoint | inventory | `192.0.2.10` | public, mandatory | host targeting |
| `topology.db.host` | db endpoint | inventory | `192.0.2.20` | public, mandatory | host targeting |
| `network.ssh.user` | SSH login user | inventory | `ubuntu` | public, conditional-mandatory | remote execution (`execution.mode=ssh`) |
| `network.ssh.private_key_path` | SSH private key path | inventory/precheck | `~/.ssh/glpi_staging_ed25519` | public, conditional-mandatory | key policy (`0600`) in `ssh` mode |
| `network.database.app_access_host` | DB grant source | db role | `192.0.2.10` | public, mandatory | connectivity restriction |
| `glpi.version` | GLPI version | app role | `11.0.0` | public, mandatory | release and package flow |
| `glpi.domain` | app domain | nginx/smoke tests | `glpi.example.internal` | public, mandatory | endpoint behavior |
| `database.name` | schema name | db role | `glpi_operational` | public, mandatory | data location |
| `database.user` | DB login name | db/app roles | `nehemiah_glpi` | public, mandatory | DB auth |
| `database.port` | DB listener port | db role | `3306` | public, mandatory | network/firewall |
| `tls.mode` | TLS operation mode | app role/policy gate | `none`/`self_signed`/`provided` | public, mandatory | policy-dependent block/warn |
| `tls.certificate_path` | cert path on target host | nginx template | `/etc/ssl/certs/glpi-production.crt` | public, conditional | required when TLS enabled |
| `tls.private_key_path` | key path on target host | nginx template | `/etc/ssl/private/glpi-production.key` | public-sensitive, conditional | required when TLS enabled |
| `tls.provided_local_cert_path` | local cert source path | TLS install flow | `/home/operator/certs/fullchain.crt` | public-sensitive, conditional | required when `mode=provided` |
| `tls.provided_local_key_path` | local key source path | TLS install flow | `/home/operator/certs/private.key` | public-sensitive, conditional | required when `mode=provided` |
| `security.sso_enabled` | SSO gate status | policy check | `true` | public, conditional | required when `security.require_sso=true` |
| `security.require_tls` | enforce provided TLS mode | policy check | `true` | public policy flag | blocks in `secure`, warns in `permissive` |
| `security.require_https` | enforce HTTPS/TLS | policy check | `true` | public policy flag | blocks in `secure`, warns in `permissive` |
| `security.require_sso` | enforce SSO policy | policy check | `true` | public policy flag | blocks in `secure`, warns in `permissive` |
| `security.require_promotion_gate` | enforce certification gate file | policy check | `true` | public policy flag | blocks in `secure`, warns in `permissive` |
| `security.require_ordered_execution` | enforce deploy ordering | deploy workflow | `true` | public policy flag | blocks in `secure`, warns in `permissive` |
| `backup.retention_days` | retention | backup role | `30` | public, mandatory | restore/recovery policy |
| `monitoring.exporters.node.enabled` | node exporter toggle | monitoring role | `true` | public, mandatory | observability |
| `monitoring.exporters.mysqld.user` | mysqld exporter user | monitoring role | `issachar_monitor` | public, mandatory | observability |
| `operations.required_ops_group` | required operator group | scripts/precheck | `glpiops` | public, mandatory | access control |
| `operations.security_mode_default` | default security mode | scripts/precheck | `secure` | public, mandatory | fallback for policy behavior |
| `resource_profiles.active` | tuning profile | renderer | `small` | public, mandatory | sizing behavior |

## Secret Key Table

| Secret key | Purpose | Consumer | Classification | Environment impact |
|---|---|---|---|---|
| `glpi_db_password` | GLPI DB user password | db/app roles | secret, mandatory | all |
| `glpi_db_root_password` | DB admin password for provisioning | db/ops roles | secret, mandatory | all |
| `mysqld_exporter_password` | mysqld exporter credential | monitoring role | secret, mandatory | all |

## Runtime secret keys (mandatory)

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

Classification:

- secret, mandatory, runtime-only

## Policy summary by execution mode

- `SECURITY_MODE=secure`:
  - policy violations block mutable operations.
- `SECURITY_MODE=permissive`:
  - policy violations become warnings and require persisted justification/evidence.
