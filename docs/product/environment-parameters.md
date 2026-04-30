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

- Purpose: explicit environment selection (`staging` or `production`).
- Consumer: runtime renderer, policy checks.
- Classification: public, mandatory.

### `topology.*`

- Purpose: host model and targeting.
- Consumer: generated inventory (`glpi_app`, `glpi_db`).
- Classification:
  - `mode`: public, mandatory
  - hosts/aliases: public, mandatory
- Impact:
  - `dual-server` requires remote SSH connectivity checks.

### `network.ssh.*`

- Purpose: SSH execution path for Ansible.
- Consumer: generated inventory and precheck.
- Format:
  - `user`: Linux username
  - `private_key_path`: path to environment key
- Classification:
  - public, mandatory
  - conditional security requirement for remote execution
- Impact:
  - private key must be mode `0600`.

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
  - production requires `mode=provided`.

### `security.*`

- Purpose: environment security policy gates.
- Consumer: precheck + deploy policy enforcement.
- Keys:
  - `sso_enabled` (mandatory; must be `true` in production when required)
  - `allow_insecure_non_production` (public policy flag)
  - `require_tls_in_production` (public policy flag)
  - `require_https_in_production` (public policy flag)
  - `require_sso_in_production` (public policy flag)
- Environment impact:
  - production blocks when required policy flags are violated.

### `monitoring.*` and `alerting.*`

- Purpose: exporter defaults, thresholds, alert policy.
- Consumer: monitoring role and operational blueprint.
- Classification: public, mandatory for product baseline.

### `paths.*`

- Purpose: secure filesystem layout.
- Consumer: app role.
- Classification: public, mandatory.

### `operations.*`

- Purpose: timezone, cron schedule, ops group policy.
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
| `topology.mode` | topology behavior | precheck/deploy | `dual-server` | public, mandatory | drives SSH checks |
| `topology.app.host` | app endpoint | inventory | `192.0.2.10` | public, mandatory | host targeting |
| `topology.db.host` | db endpoint | inventory | `192.0.2.20` | public, mandatory | host targeting |
| `network.ssh.user` | SSH login user | inventory | `ubuntu` | public, mandatory | remote execution |
| `network.ssh.private_key_path` | SSH private key path | inventory/precheck | `~/.ssh/glpi_staging_ed25519` | public, mandatory | key policy (`0600`) |
| `network.database.app_access_host` | DB grant source | db role | `192.0.2.10` | public, mandatory | connectivity restriction |
| `glpi.version` | GLPI version | app role | `11.0.0` | public, mandatory | release and package flow |
| `glpi.domain` | app domain | nginx/smoke tests | `glpi.example.internal` | public, mandatory | endpoint behavior |
| `database.name` | schema name | db role | `glpi_operational` | public, mandatory | data location |
| `database.user` | DB login name | db/app roles | `nehemiah_glpi` | public, mandatory | DB auth |
| `database.port` | DB listener port | db role | `3306` | public, mandatory | network/firewall |
| `tls.mode` | TLS operation mode | app role/policy gate | `none`/`self_signed`/`provided` | public, mandatory | production block logic |
| `tls.certificate_path` | cert path on target host | nginx template | `/etc/ssl/certs/glpi-production.crt` | public, conditional | required when TLS enabled |
| `tls.private_key_path` | key path on target host | nginx template | `/etc/ssl/private/glpi-production.key` | public-sensitive, conditional | required when TLS enabled |
| `tls.provided_local_cert_path` | local cert source path | TLS install flow | `/home/operator/certs/fullchain.crt` | public-sensitive, conditional | required when `mode=provided` |
| `tls.provided_local_key_path` | local key source path | TLS install flow | `/home/operator/certs/private.key` | public-sensitive, conditional | required when `mode=provided` |
| `security.sso_enabled` | SSO gate status | production policy check | `true` | public, mandatory | can block production |
| `security.require_tls_in_production` | enforce secure TLS | production policy check | `true` | public policy flag | can block production |
| `security.require_https_in_production` | enforce HTTPS | production policy check | `true` | public policy flag | can block production |
| `security.require_sso_in_production` | enforce SSO policy | production policy check | `true` | public policy flag | can block production |
| `backup.retention_days` | retention | backup role | `30` | public, mandatory | restore/recovery policy |
| `monitoring.exporters.node.enabled` | node exporter toggle | monitoring role | `true` | public, mandatory | observability |
| `monitoring.exporters.mysqld.user` | mysqld exporter user | monitoring role | `issachar_monitor` | public, mandatory | observability |
| `operations.required_ops_group` | required operator group | scripts/precheck | `glpiops` | public, mandatory | access control |
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

## Policy summary by environment

- Staging/dev:
  - may allow insecure TLS modes if policy permits.
- Production:
  - requires promotion gate
  - requires secure TLS/HTTPS policy
  - requires SSO policy gate when configured
