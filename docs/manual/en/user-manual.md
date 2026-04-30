# GLPI Operations Kit Operator Runbook

## 1. Purpose

This manual is the official runbook for installing, validating, promoting, and operating GLPI environments delivered by this product kit.

It is intended for:

- Linux server operators
- DevOps or infrastructure engineers
- technical approvers responsible for staging and production execution
- AI agents that must follow repository rules before suggesting or applying changes

This manual explains:

- what each command does
- where each command must be executed
- when each command must be executed
- what each command changes on target hosts
- which prerequisites are mandatory before execution continues

## 2. Required Operator Profile

Required operator skill:

- Ubuntu server administration
- `sudo` usage
- SSH key-based access
- Ansible execution and troubleshooting
- change-control awareness for corporate environments

Recommended AI execution profile:

- an agent that reads `README.md`, `AGENTS.md`, `docs/standards/index.md`, and this runbook before acting

## 2.1 Product Configuration Model

Public product configuration:

- `config/staging.yml`
- `config/production.yml`

Secret runtime configuration:

- `.runtime/<environment>/secrets.yml`

Generated runtime artifacts:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/overrides.runtime.yml`

Operational rule:

- public values must be edited in `config/<environment>.yml`
- scripts should prompt only for missing secrets

## 3. Supported Topologies

Primary topology:

- dual-server
- one `app` host
- one `db` host

Supported fallback topology:

- single-server
- one Ubuntu host running both application and database roles

How topology is decided:

- the runtime inventory defines the real hosts
- if `app host` and `db host` are the same value, the deployment behaves as single-server
- if `app host` and `db host` are different values, the deployment behaves as dual-server

## 4. Where To Run Commands

Supported execution origins:

- on the `app` host
- on the `db` host
- on the same host when running single-server mode

Operational rule:

- the execution host must have the Git clone, `bash`, `git`, `ansible-playbook`, `ansible-inventory`, SSH key access, and `sudo`

What happens in dual-server mode:

- `glpictl` runs locally on the execution host
- Ansible connects over SSH to the remote host defined in the runtime inventory
- `db` tasks run only on inventory group `glpi_db`
- `app` tasks run only on inventory group `glpi_app`

## 5. Mandatory Prerequisites

### 5.1 Platform and repository

- Ubuntu Linux on the execution host
- repository cloned locally
- enough local free disk for `.runtime`, logs, and evidence files

### 5.2 Mandatory tools

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`

Recommended tool:

- `ssh`

### 5.3 Mandatory access and permissions

- valid `sudo` capability on the execution host
- operator must belong to `glpiops`
- SSH private key file must exist
- SSH private key file must be restricted to mode `0600`
- remote target hosts must be reachable by SSH
- the SSH user must have privilege to execute the required system changes

### 5.4 Mandatory operator setup

```bash
sudo groupadd -f glpiops
sudo usermod -aG glpiops "$USER"
newgrp glpiops
sudo -v
```

### 5.5 First mandatory command

```bash
bash scripts/bootstrap-permissions.sh
```

What it is for:

- ensures scripts are executable
- prepares `.runtime/`
- validates operator baseline permissions
- writes the bootstrap marker

## 6. Official CLI

Official entrypoint:

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Supported environments:

- `staging`
- `production`

Supported domains:

- `deploy`
- `certify`
- `promote`
- `tls`
- `ops`
- `audit`

Compatibility note:

- specific scripts such as `deploy-staging.sh`, `deploy-db.sh`, and `manage-tls.sh` still work
- they are wrappers around `glpictl.sh`

## 7. Command Behavior Matrix

| Command shape | Purpose | Target hosts | When to use |
|---|---|---|---|
| `glpictl <env> deploy check all` | Validate precheck and runtime inventory | local checks + inventory parse | before any apply |
| `glpictl <env> deploy apply db` | Install and configure MariaDB | `glpi_db` | first apply step in new environments |
| `glpictl <env> deploy apply app` | Install and configure GLPI app stack | `glpi_app` | after DB is reachable |
| `glpictl <env> deploy apply monitoring` | Install exporters | app and db according to role | after app and db baseline are ready |
| `glpictl <env> deploy apply backup` | Install backup baseline | target hosts defined by role | after app and db baseline are ready |
| `glpictl <env> deploy apply all` | Apply base, app, db, monitoring, backup | both inventory groups | controlled full run |
| `glpictl <env> deploy post-check all` | Run validation playbook path | app and db | after deploy |
| `glpictl staging certify run` | Create staging evidence and promotion gate | local + app + db checks | before any production rollout |
| `glpictl <env> tls <action>` | Change or reload TLS mode | `glpi_app` | after app baseline exists |
| `glpictl <env> ops ...` | day-2 maintenance | depends on operation | after deployment |
| `glpictl <env> audit check` | run maintenance audit path | app and db | after deployment or after changes |
| `glpictl production promote apply <target>` | production deployment with gate enforcement | depends on target | after approved staging certification |

## 8. Runtime Files and What They Mean

Runtime root:

- `.runtime/<environment>/`

Configuration files:

- `inventory.runtime.yml`
- `public.runtime.yml`
- `overrides.runtime.yml`
- `secrets.yml`

Operational state:

- `.runtime/<environment>/logs/`
- `.runtime/<environment>/state/`
- `.runtime/<environment>/evidence/`

Promotion gate:

- `.runtime/promotion/staging-certified.yml`

Important behavior:

- if runtime files are missing, `glpictl` renders them from `config/<environment>.yml`
- only missing secrets should be requested at runtime
- public values should not be entered interactively when already present in the product config
- values are merged in this order: `public.runtime.yml -> overrides.runtime.yml -> secrets.yml`

## 9. What `apply db` Does

Command:

```bash
./scripts/glpictl.sh staging deploy apply db
```

Where to run:

- on the app host, db host, or same host in single-server mode

When to run:

- first infrastructure apply step for a new environment
- before `apply app`

What it changes:

- installs MariaDB packages if not already managed by the role
- applies MariaDB baseline tuning and hardening
- creates or updates the GLPI database
- creates or updates the GLPI database user
- uses the `glpi_db` inventory group only

What it needs:

- `config/<environment>.yml`
- rendered runtime inventory
- DB secret values in `.runtime/<environment>/secrets.yml`
- SSH access to the DB host

What to validate after it finishes:

- MariaDB service is running on the DB host
- GLPI schema exists
- GLPI DB user exists
- app host is allowed to connect according to configured access host

## 10. What `apply app` Does

Command:

```bash
./scripts/glpictl.sh staging deploy apply app
```

Where to run:

- on the app host, db host, or same host in single-server mode

When to run:

- after `apply db` completes successfully
- after the DB host is reachable and credentials are known

What it changes:

- installs and configures Nginx
- installs and configures PHP-FPM
- downloads or prepares GLPI files
- applies secure GLPI filesystem layout
- configures app-side GLPI files and runtime definitions
- applies app-side TLS mode configuration
- uses the `glpi_app` inventory group only

What it needs:

- `config/<environment>.yml`
- rendered runtime inventory
- TLS settings from config
- DB secrets from `.runtime/<environment>/secrets.yml`

What to validate after it finishes:

- `nginx -t`
- `php-fpm8.3 -t`
- GLPI installer page loads
- application can reach the database

## 11. Single-Server Runbook

### 11.1 When to use

- lab or constrained environment
- temporary validation scenario
- small non-production test environment

### 11.2 How to provide runtime values

- enter the same host value for both `app host` and `db host`

### 11.3 Execution order

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 11.4 Validation

- DB and app services run on the same server
- GLPI page opens from the app endpoint
- backup and monitoring artifacts exist

## 12. Dual-Server Runbook From App Host

### 12.1 When to use

- standard corporate deployment
- recommended for staging and production

### 12.2 How to provide runtime values

- `app host` = current app host
- `db host` = remote database host
- SSH user and key must work against both hosts

### 12.3 Execution order

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 12.4 What happens behind the scenes

- the command runs locally on the app host
- Ansible connects from app host to db host for `db` role execution
- Ansible stays on app host or reconnects to app host for `app` role execution

## 13. Dual-Server Runbook From DB Host

### 13.1 When to use

- when the db host is the approved execution point
- when app host is reachable over SSH from db host

### 13.2 How to provide runtime values

- `db host` = current db host
- `app host` = remote app host
- SSH user and key must work against both hosts

### 13.3 Execution order

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 13.4 What happens behind the scenes

- the command runs locally on the db host
- Ansible connects from db host to app host when app tasks are required

## 14. Staging Certification and Production

Staging certification:

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

What it does:

- runs validation checks
- writes evidence under `.runtime/staging/evidence/`
- writes the promotion gate file

Production rollout:

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

Stop condition:

- production apply remains blocked without `.runtime/promotion/staging-certified.yml`

## 15. Stop Conditions

Execution must stop when any mandatory prerequisite is not resolved:

- no `sudo`
- operator not in `glpiops`
- missing `ansible-playbook`
- missing `ansible-inventory`
- SSH key path does not exist
- SSH key mode is not secure and cannot be fixed
- target hosts are wrong or unreachable
- production gate file is missing for production apply

## 16. Project Improvement Recommendations

### 16.1 Highest-value improvement

Expand override coverage beyond TLS to additional mutable operational domains, while keeping `config/<environment>.yml` as the public baseline source.

### 16.2 Additional improvement areas

- add a generated command reference appendix from the real CLI contract
- add a machine-readable operator profile document for agents
- add explicit restore drill steps and expected evidence examples

## 17. Related Documentation

- [Multilingual index](../README.md)
- [Appendices index](appendices/index.md)
- [Implementation plan](../../implementation-plan.md)
- [Configuration reference](../../product/configuration-reference.md)
