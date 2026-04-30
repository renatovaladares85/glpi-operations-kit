# GLPI Operations Kit Operator Runbook

## 1. Manual purpose

This runbook is the operational guide to deploy, validate, and operate GLPI with this repository.

Primary audience:

- Linux operators
- DevOps/infrastructure engineers
- change managers and auditors
- AI agents following `AGENTS.md`

Required operator skill:

- Ubuntu server administration
- `sudo` operations
- shell execution and troubleshooting
- Ansible execution (`ansible-playbook`, `ansible-inventory`)
- security/compliance awareness (LGPD, least privilege)

## 2. Execution model

This project supports two execution modes:

- `local` (default, recommended for corporate 2FA environments)
- `ssh` (optional, when remote SSH automation is allowed)

Execution contract shared by all scripts:

- `GLPI_ENVIRONMENT`: target environment name (for example `staging`, `production`)
- `GLPI_EXECUTION_MODE=local|ssh`
- `GLPI_HOST_ROLE=app|db|all`
- `SECURITY_MODE=secure|permissive`

Official CLI:

```bash
./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit> <action> [target] [scope]
```

Wrapper scripts (`deploy-*.sh`, `manage-tls.sh`, `ops-maintenance.sh`) delegate to the same CLI contract.

## 3. Topologies and where to run commands

Supported topologies:

- `single-server`: app and db on the same host
- `dual-server`: app host + db host

### 3.1 Dual-server with no cross-host SSH (corporate 2FA model)

If your company does not allow direct SSH between servers, use `GLPI_EXECUTION_MODE=local` and run commands locally on each host after interactive login (username/password/2FA).

DB host flow:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=db
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

APP host flow:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=app
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Important:

- In local dual-server mode, `deploy apply db` is valid only with `GLPI_HOST_ROLE=db|all`.
- In local dual-server mode, `deploy apply app|monitoring|backup` is valid only with `GLPI_HOST_ROLE=app|all`.
- Running `deploy apply all` on `dual-server` with `GLPI_HOST_ROLE=app` or `db` is blocked.

### 3.2 Single-server

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=all
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 3.3 Optional SSH automation mode

Use only when remote automation is allowed by policy:

- `GLPI_EXECUTION_MODE=ssh`
- SSH key pair per environment
- key mode `0600`
- remote connectivity to app/db targets

## 4. Prerequisites (mandatory, optional, conditional)

Mandatory in all environments:

- Ubuntu 24.04
- `bash`, `git`, `python3`, `ansible-playbook`, `ansible-inventory`
- valid `sudo` capability (or root)
- operator in `glpiops` group
- secure `.runtime` permissions

Conditional mandatory:

- SSH key material and connectivity only when `GLPI_EXECUTION_MODE=ssh`
- local cert/key files when `tls.mode=provided`

Optional:

- `ssh` diagnostic client in pure local mode

Canonical source: [Prerequisites Matrix](../../product/prerequisites-matrix.md)

Precheck behavior:

- when mandatory tooling is missing (for example `ansible-playbook`), scripts prompt to install automatically on Ubuntu;
- if installation is declined or fails, mutable execution is blocked with manual remediation commands.

## 5. Step 0 (mandatory): permissions bootstrap

Run this before any deploy command:

```bash
bash scripts/bootstrap-permissions.sh
```

What it does:

- ensures execute permission on `scripts/*.sh`
- validates `sudo`
- validates `glpiops` group model
- ensures `.runtime/` exists with secure mode
- writes bootstrap marker

If you see `permission denied` when calling `./scripts/...`, run the bootstrap again and retry.

## 6. Configuration model

Public config files:

- `config/product.example.yml`
- `config/<environment>.yml` (operator-created from `product.example.yml`)

Create environment file before running deploy:

```bash
cp config/product.example.yml config/staging.yml
cp config/product.example.yml config/production.yml
```

Secret runtime file:

- `.runtime/<environment>/secrets.yml`

Runtime precedence:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Detailed parameter reference:

- [Configuration Reference](../../product/configuration-reference.md)
- [Environment Parameters](../../product/environment-parameters.md)

## 7. Ordered execution and behavior

Recommended order:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Behavior:

- if `security.require_ordered_execution=true` and `SECURITY_MODE=secure`, out-of-order mutable calls are blocked;
- in `SECURITY_MODE=permissive`, policy violations become warnings and are persisted as evidence.

## 8. What each main command does

| Command | Run where | What it changes | When to run |
|---|---|---|---|
| `deploy check all` | current host | runs precheck, config rendering, inventory validation, policy checks | before any mutable action |
| `deploy apply db` | DB host (`GLPI_HOST_ROLE=db`) | MariaDB install/hardening, GLPI schema/user grants, DB baseline | first mutable stage |
| `deploy apply app` | APP host (`GLPI_HOST_ROLE=app`) | Nginx/PHP-FPM/GLPI layout, app runtime config, TLS template | after DB is ready |
| `deploy apply monitoring` | APP host (and/or DB host by design) | exporter baseline and monitoring config | after DB + APP |
| `deploy apply backup` | APP host (and/or DB host by design) | backup baseline and retention tasks | after DB + APP |
| `deploy post-check all` | current host | post-deploy validation and service checks | after apply stages |

Notes:

- In local dual-server mode, run role-scoped commands on each host.
- In SSH mode, automation targets remote hosts from the execution host.

## 9. TLS and certificates

Supported actions:

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

Use cases:

- `disable`: HTTP-only flow (allowed only when policy permits)
- `self-signed`: test encryption in non-public trust scenarios
- `install-provided`: deploy real certificate and key

## 10. Validation and evidence

Readiness and certification:

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Evidence locations:

- `.runtime/<env>/state/precheck-report-latest.yml`
- `.runtime/<env>/evidence/precheck-report-latest.md`
- `.runtime/<env>/evidence/readiness-report.md`
- `.runtime/<env>/evidence/readiness-report.json`
- `.runtime/<env>/logs/`

## 11. Related appendices

- [Command Reference](appendices/command-reference.md)
- [Runtime Input Reference](appendices/runtime-input-reference.md)
- [TLS Modes](appendices/tls-modes.md)
- [Troubleshooting Matrix](appendices/troubleshooting-matrix.md)
