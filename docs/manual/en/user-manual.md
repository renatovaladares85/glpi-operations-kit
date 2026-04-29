# GLPI SoEnergy User Manual

## 1. Overview

This manual is a full operator runbook for installing and validating GLPI in staging, with or without repository scripts.

It covers:

- automated guided flow (scripts + Ansible)
- manual fallback flow (command-by-command on Ubuntu)
- single-server mode (app + db on one host)
- dual-server mode (app host + db host)
- cross-host execution using SSH from app to db or db to app

Implemented behavior is documented as executable. Deferred capabilities are listed separately.

## 2. Architecture and Modes

Supported topology modes:

- single-server: one Ubuntu host running app and db roles
- dual-server: one Ubuntu app host and one Ubuntu db host

Supported TLS modes:

- `none` (HTTP only)
- `self_signed`
- `provided`

Secure GLPI layout:

- code: `/usr/share/glpi`
- config: `/etc/glpi`
- data: `/var/lib/glpi/files`
- plugins: `/var/lib/glpi/plugins`
- logs: `/var/log/glpi`

## 3. Prerequisites

Execution origin policy for this runbook:

- run from a target host only (app host or db host)
- no bastion host is required

Mandatory tools on execution host:

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`

Optional but recommended:

- `ssh`

Mandatory access:

- SSH reachability between execution host and remote target host in dual-server mode
- sudo privileges on target hosts
- local SSH private key path available on execution host
- operator user must belong to `glpiops` group

### 3.1 Operator security setup (mandatory)

```bash
sudo groupadd -f glpiops
sudo usermod -aG glpiops "$USER"
newgrp glpiops
```

Recommended sudo validation:

```bash
sudo -v
```

## 4. Automated Guided Flow (Track A)

Primary entrypoint:

- `scripts/glpictl.sh`

The script starts with pre-flight checks. If a mandatory command is missing, it prompts to install it on Ubuntu. If installation fails, it prints exact manual remediation commands and blocks execution.

### 4.1 Step-by-step

0. Run permission bootstrap (first mandatory command):

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
```

### 4.3 Staging certification and production gate (mandatory)

Before any production deployment, run staging certification:

```bash
./scripts/glpictl.sh staging certify run
```

Expected behavior:

- generates evidence in `.runtime/staging/evidence/<timestamp>/`
- writes promotion gate approval in `.runtime/promotion/staging-certified.yml`
- blocks production promotion if any mandatory check fails

### 4.2 Runtime prompts (mandatory)

The script requests and validates:

- app host IP/hostname
- db host IP/hostname
- SSH username
- SSH private key path
- GLPI version
- TLS mode
- certificate/key paths for `provided` mode
- DB name, DB username, DB password
- MariaDB root password
- monitoring exporter username/password

Runtime files are persisted under `.runtime/staging/`.

## 5. Manual Fallback Flow (Track B)

Use this flow when scripts are unavailable or when auto-install fails.

### 5.1 Install dependencies on Ubuntu (execution host)

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client ansible
```

Validate:

```bash
command -v bash
command -v git
command -v ansible-playbook
command -v ansible-inventory
command -v ssh
id -nG | tr ' ' '\n' | grep -Fx glpiops
sudo -v
```

### 5.2 Manual runtime data files

Create runtime directory:

```bash
mkdir -p .runtime/staging
chmod 700 .runtime/staging
```

Use file models from the appendices to create:

- `.runtime/staging/inventory.runtime.yml`
- `.runtime/staging/app.runtime.yml`
- `.runtime/staging/db.secrets.yml`
- `.runtime/staging/monitoring.secrets.yml`

Protect secret files:

```bash
chmod 600 .runtime/staging/*.secrets.yml
```

### 5.3 Apply roles manually with Ansible

```bash
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/app.runtime.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags monitoring --extra-vars @.runtime/staging/monitoring.secrets.yml --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags backup --extra-vars @.runtime/staging/app.runtime.yml
```

## 6. Single-Server and Dual-Server Operation

### 6.1 Single-server mode

Set both app and db host values to the same host in runtime inventory.

Run:

```bash
./scripts/glpictl.sh staging deploy apply all
```

### 6.2 Dual-server mode from app host

Run the script on app host and set:

- app host = current app host IP/FQDN
- db host = remote db host IP/FQDN
- SSH user/key = credentials with sudo access on both

### 6.3 Dual-server mode from db host

Run the script on db host and set:

- db host = current db host IP/FQDN
- app host = remote app host IP/FQDN
- SSH user/key = credentials with sudo access on both

In both directions, execution host only needs SSH + key access to the other host.

## 7. TLS Operations

Use:

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

`install-provided` asks for local cert/key file paths and applies app role safely.

## 8. Validation and Acceptance

Minimum acceptance checks:

- pre-flight completes with no unresolved mandatory failures
- runtime inventory parses
- app and db roles complete
- `nginx -t` is valid on app host
- `php-fpm8.3 -t` is valid on app host
- GLPI installer page opens
- DB access works with runtime credentials
- monitoring and backup artifacts exist

## 9. Day-2 Operations (Post-Implementation)

Use `scripts/glpictl.sh` for operational lifecycle actions:

- `./scripts/glpictl.sh staging ops users add`
- `./scripts/glpictl.sh staging ops users disable`
- `./scripts/glpictl.sh staging ops users remove`
- `./scripts/glpictl.sh staging ops cert check`
- `./scripts/glpictl.sh staging ops cert renew`
- `./scripts/glpictl.sh staging ops cert apply`
- `./scripts/glpictl.sh staging audit check`
- `./scripts/glpictl.sh staging ops resume`

Operational persistence:

- logs: `.runtime/<environment>/logs/`
- checkpoints/state: `.runtime/<environment>/state/`

Certificate policy:

- warning threshold: `<= 30` days to expiry.

## 10. Production rollout (after approved staging gate)

Run only after successful `certify-staging.sh`:

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

Production `apply` is blocked if `.runtime/promotion/staging-certified.yml` is missing or not approved.

## 11. Troubleshooting and Recovery

Use the troubleshooting appendix for:

- missing dependencies and install failures
- SSH connectivity/auth issues
- runtime input validation failures
- Nginx/PHP-FPM/MariaDB validation failures
- partial deployment rerun sequence

## 12. Related Documentation

- [Multilingual index](../README.md)
- [Appendices index](appendices/index.md)
