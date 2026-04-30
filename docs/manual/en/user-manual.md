# GLPI Operations Kit Operator Runbook

## 1. Manual Purpose

This runbook is the operational guide for installing, validating, and operating the GLPI Operations Kit in corporate environments.

It is for:

- Linux operators
- DevOps/infrastructure engineers
- staging/production approvers
- AI agents that must follow repository standards

## 2. Required Operator Skill

Minimum skill profile:

- Ubuntu server administration
- SSH key management
- `sudo` operations
- Ansible execution and troubleshooting
- change-control and evidence mindset

## 3. Supported Topologies

- Dual-server (recommended): one app host + one db host
- Single-server (supported): app and db on the same host

Execution origin:

- app host, db host, or single host
- host must contain repository clone and required tools

## 4. Configuration and Runtime Model

Public configuration:

- `config/staging.yml`
- `config/production.yml`

Secret runtime:

- `.runtime/<env>/secrets.yml` (never versioned)

Runtime precedence:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Detailed references:

- [Prerequisites Matrix](../../product/prerequisites-matrix.md)
- [Configuration Reference](../../product/configuration-reference.md)
- [Environment Parameters](../../product/environment-parameters.md)

## 5. Prerequisites (Mandatory, Optional, Conditional)

Mandatory in all environments:

- Ubuntu 24.04
- `bash`, `git`, `python3`, `ansible-playbook`, `ansible-inventory`
- `sudo` ready or root
- operator in `glpiops`
- secure `.runtime` permissions

Conditional mandatory:

- SSH key pair per environment + connectivity to targets when remote execution is used
- local TLS cert/key files when `tls.mode=provided`

Optional:

- `ssh` diagnostic client checks (recommended)

Precheck behavior:

- for missing mandatory packages, scripts prompt to install automatically on Ubuntu;
- if auto-install fails (or is declined), execution stops with actionable remediation commands.

## 6. SSH Key Generation and Distribution (Required for Remote Execution)

Staging key:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_staging_ed25519 -C "glpi-staging-ops"
chmod 600 ~/.ssh/glpi_staging_ed25519
chmod 644 ~/.ssh/glpi_staging_ed25519.pub
```

Production key:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_production_ed25519 -C "glpi-production-ops"
chmod 600 ~/.ssh/glpi_production_ed25519
chmod 644 ~/.ssh/glpi_production_ed25519.pub
```

Install key to app and db targets:

```bash
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@APP_HOST
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@DB_HOST
```

Connectivity validation:

```bash
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@APP_HOST "echo ok"
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@DB_HOST "echo ok"
```

## 7. Official CLI

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Supported environments:

- `staging`
- `production`

Supported domains:

- `deploy`, `certify`, `promote`, `tls`, `ops`, `audit`

## 8. Command Behavior Matrix (Detailed)

| Command | Detailed purpose | Affected targets | Use when |
|---|---|---|---|
| `deploy check all` | Runs precheck, validates mandatory/optional/conditional prerequisites, validates runtime inventory, writes structured and human-readable precheck reports | execution host | before any mutation |
| `deploy apply db` | Installs and hardens MariaDB, configures GLPI schema/user/grants, enforces DB-side operational baseline | `glpi_db` | first apply stage |
| `deploy apply app` | Installs Nginx/PHP-FPM/GLPI layout, applies TLS mode, validates app service config and secure filesystem model | `glpi_app` | after DB apply succeeds |
| `deploy apply monitoring` | Applies exporter baseline and monitoring role configuration | app/db based on role | after DB + app |
| `deploy apply backup` | Applies backup baseline and retention schedule | app/db based on role | after DB + app |
| `deploy post-check all` | Executes post-deploy validation path for app and db readiness | `glpi_app`, `glpi_db` | after apply stages |
| `staging certify run` | Produces staging evidence bundle and promotion gate artifact | local + remote validation checks | before any production rollout |
| `tls <action>` | Switches TLS mode (`none`, `self-signed`, `provided`) and safely reapplies app configuration | `glpi_app` | certificate operations |
| `ops ...` | Day-2 operations: users, certificates, audit, resume | depends on operation | post-implementation lifecycle |
| `audit check` | Runs compliance and operational audit path | app + db | after day-2 changes |

## 9. Mandatory Execution Order

The project enforces this order and blocks out-of-order execution:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

State file:

- `.runtime/<env>/state/deploy-sequence.yml`

## 10. Production Block Conditions (Hard Gate)

Production apply is blocked unless:

- staging certification gate exists:
  - `.runtime/promotion/staging-certified.yml`
- `tls.mode=provided`
- HTTPS/TLS is enabled
- `security.sso_enabled=true` when production SSO policy is required

Staging/dev may run insecure modes only when policy allows.

## 11. Runtime Files and Their Meaning

| Runtime artifact | Meaning | Producer | Consumer |
|---|---|---|---|
| `inventory.runtime.yml` | environment-specific inventory targets and SSH model | renderer | Ansible |
| `public.runtime.yml` | rendered public vars from config | renderer | Ansible |
| `overrides.runtime.yml` | mutable overrides without changing baseline config | operator/CLI | Ansible |
| `secrets.yml` | secret-only runtime values | operator prompts | Ansible |
| `state/precheck-report-latest.yml` | structured prerequisite report | precheck | audit/troubleshooting |
| `evidence/precheck-report-latest.md` | human-readable prerequisite report | precheck | operators |
| `state/deploy-sequence.yml` | mandatory sequence status | CLI | CLI |
| `logs/*.log` + `*.summary.yml` | execution and summary traces | operations scripts | audit/investigation |

## 12. Step-by-Step Deployment Flows

Single-server:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Dual-server (from app or db host):

- same commands
- host mapping comes from `config/<env>.yml`
- Ansible reaches remote target through SSH key defined in config

## 13. TLS and Certificate Operations

Staging/dev self-signed:

```bash
./scripts/glpictl.sh staging tls self-signed
```

Production valid cert:

```bash
./scripts/glpictl.sh production tls install-provided
```

Post-change checks:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I https://GLPI_DOMAIN
```

## 14. Validation and Evidence

Mandatory staging validation:

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Evidence to review:

- `.runtime/staging/evidence/readiness-report.md`
- `.runtime/staging/evidence/readiness-report.json`
- `.runtime/promotion/staging-certified.yml`

## 15. Related Documents

- [Multilingual manual index](../README.md)
- [EN appendices index](appendices/index.md)
- [Implementation Plan](../../implementation-plan.md)
- [Prerequisites Matrix](../../product/prerequisites-matrix.md)
