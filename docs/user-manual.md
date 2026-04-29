# GLPI SoEnergy User Manual

## 1. Overview

This manual is for installers and operators who need to deploy and operate GLPI using this repository.

It documents only behavior that is currently implemented and executable from this codebase.

This repository currently provides:

- automated deployment for GLPI on Ubuntu hosts using Ansible
- guided staging runtime input collection via bash scripts
- app/db host separation
- TLS mode switching (`none`, `self_signed`, `provided`)
- baseline backup and monitoring setup

Not all corporate target capabilities are fully implemented yet. Deferred items are listed in the dedicated appendix.

## 2. Architecture

Current deployment model:

- `staging`: 1 app host + 1 db host
- `production`: 1 app host + 1 db host baseline

Main stack:

- `Ubuntu 24.04`
- `Nginx`
- `PHP-FPM`
- `MariaDB`
- `Ansible`

GLPI secure layout:

- code: `/usr/share/glpi`
- config: `/etc/glpi`
- data: `/var/lib/glpi/files`
- plugins: `/var/lib/glpi/plugins`
- logs: `/var/log/glpi`

## 3. Prerequisites

Run scripts from an operator machine with repository access.

Required local tools:

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`

Optional but recommended:

- `ssh`

Required access and files:

- network reachability to target app and db hosts
- valid SSH username for both hosts
- valid SSH private key file available locally

## 4. Installation Workflow (Staging)

Primary entrypoint:

- `scripts/deploy-staging.sh`

The script always starts with pre-flight checks, then asks for runtime values, writes runtime files under `.runtime/staging/`, and executes Ansible targets.

### 4.1 Runtime values requested

The staging workflow prompts for:

- app server IP/hostname
- db server IP/hostname
- SSH username
- SSH private key path
- GLPI final version
- TLS mode (`none`, `self_signed`, `provided`)
- certificate and key local paths (when TLS mode is `provided`)
- GLPI database name
- GLPI database username
- GLPI database password
- MariaDB root password
- `mysqld_exporter` username
- `mysqld_exporter` password

### 4.2 Runtime files generated

Files are generated under `.runtime/staging/`:

- `inventory.runtime.yml`
- `app.runtime.yml`
- `db.secrets.yml`
- `monitoring.secrets.yml`

### 4.3 Main command sequence

```bash
./scripts/deploy-staging.sh check
./scripts/deploy-staging.sh apply db
./scripts/deploy-staging.sh apply app
./scripts/deploy-staging.sh apply monitoring
./scripts/deploy-staging.sh apply backup
```

Optional combined run:

```bash
./scripts/deploy-staging.sh apply all
```

### 4.4 Target behavior

Available targets in `deploy-staging.sh`:

- `base`
- `app`
- `db`
- `monitoring`
- `backup`
- `all`

Available modes:

- `check`
- `apply`
- `post-check`

## 5. TLS Operation

Use `scripts/manage-tls.sh` to switch TLS behavior without manual Nginx editing.

Supported actions:

- `disable`
- `self-signed`
- `install-provided`
- `reload`

Examples:

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```

Mode behavior:

- `none`: HTTP only
- `self_signed`: HTTPS using generated self-signed certificate
- `provided`: HTTPS using provided cert/key copied from local paths

## 6. Validation

Minimum operational checks:

- pre-flight completes without mandatory failures
- inventory generation succeeds
- app/db services are configured and started
- `nginx -t` succeeds on app host
- `php-fpm8.3 -t` succeeds on app host
- GLPI installer page is reachable
- DB connectivity works with runtime credentials
- monitoring and backup tasks are present

## 7. Operations

Rerun guidance:

- rerun `check` first when environment or access changed
- rerun specific `apply <target>` for isolated corrections
- use `manage-tls.sh` for TLS mode updates

Secrets handling:

- runtime secrets stay in `.runtime/`
- secrets must not be committed

## 8. Troubleshooting

Use the troubleshooting matrix appendix for common failures and fix paths:

- missing Ansible commands
- invalid SSH key path
- invalid app/db host input
- invalid TLS provided certificate paths
- Nginx config failure
- PHP-FPM config failure
- DB credential mismatch
- app not loading after deployment

## 9. Related Documentation

- [README.md](/D:/Stefanini/SoEnergy/glpi-soenergy/README.md)
- [implementation-plan.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/implementation-plan.md)
- [standards index](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/index.md)
- [command reference appendix](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual-appendices/command-reference.md)
- [runtime input appendix](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual-appendices/runtime-input-reference.md)
- [tls appendix](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual-appendices/tls-modes.md)
- [troubleshooting appendix](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual-appendices/troubleshooting-matrix.md)
- [operational checks appendix](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual-appendices/operational-checks.md)
- [deferred features appendix](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual-appendices/deferred-features.md)
