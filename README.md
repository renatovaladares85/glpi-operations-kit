# GLPI-SoEnergy

![CI](https://img.shields.io/github/actions/workflow/status/SoEnergy/GLPI-SoEnergy/ci.yml?branch=main)
![Release](https://img.shields.io/github/v/tag/SoEnergy/GLPI-SoEnergy)
![License](https://img.shields.io/badge/license-private-red)
![IaC](https://img.shields.io/badge/IaC-Ansible-blue)
![Stack](https://img.shields.io/badge/stack-Nginx%20%7C%20PHP--FPM%20%7C%20MariaDB-green)

Private repository to standardize, automate, and operate the **GLPI** deployment for SoEnergy in corporate environments.

## Overview

- Automation with `Ansible`
- Guided execution with `bash` scripts
- Clear separation between `staging` and `production`
- GLPI with sensitive directories outside the web root
- Secrets collected at runtime and kept out of Git

## Target architecture

- `Ubuntu 24.04`
- `GLPI 11.x`
- `Nginx + PHP-FPM + MariaDB`
- initial deployment without containers
- 2 servers per environment:
  - app
  - db

Secure application layout:

- code: `/usr/share/glpi`
- config: `/etc/glpi`
- data: `/var/lib/glpi/files`
- plugins: `/var/lib/glpi/plugins`
- logs: `/var/log/glpi`

## Repository structure

```text
ansible/
  inventories/{staging,production}
  roles/{base,app,db,monitoring,backup}
scripts/
docs/
AGENTS.md
```

## Operational flow

- edit and review locally
- keep infrastructure as code in Git
- request secrets at runtime
- store runtime secrets only under `.runtime/`
- run `ansible-playbook` through guided scripts

Available scripts:

- `scripts/glpictl.sh` (official central CLI)
- `scripts/bootstrap-host.sh`
- `scripts/bootstrap-permissions.sh`
- `scripts/deploy-app.sh`
- `scripts/deploy-db.sh`
- `scripts/deploy-monitoring.sh`
- `scripts/deploy-backup.sh`
- `scripts/deploy-staging.sh`
- `scripts/certify-staging.sh`
- `scripts/deploy-production.sh`
- `scripts/manage-tls.sh`
- `scripts/ops-maintenance.sh`

## Quick usage

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging certify run
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging ops cert check
./scripts/glpictl.sh staging ops users add
```

Specific scripts still work and now delegate to the same central execution path.

## Promotion gate (staging -> production)

- Production deployment is blocked unless staging certification is approved.
- The certification process generates evidence under `.runtime/staging/evidence/<timestamp>/`.
- The promotion gate file is persisted at `.runtime/promotion/staging-certified.yml`.
- If any critical staging check fails, production remains blocked until resolved.

## TLS modes

Supported staging TLS modes:

- `none`
- `self_signed`
- `provided`

The first staging deployment may run over plain HTTP.
You can later switch to a self-signed certificate or a valid provided certificate with `scripts/manage-tls.sh`.

## Expected validation

- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`
- `nginx -t`
- `php-fpm8.3 -t`
- database connectivity validation
- HTTP/HTTPS smoke tests

## Live documentation

- [implementation-plan.md](docs/implementation-plan.md)
- [standards/index.md](docs/standards/index.md)
- [manual/README.md (EN + PT-BR)](docs/manual/README.md)

## Contact

- Owner: Renato de Souza Valadares
- Email: `rsvaladares@stefanini.com`
