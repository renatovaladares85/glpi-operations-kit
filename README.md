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

- `scripts/bootstrap-host.sh`
- `scripts/deploy-app.sh`
- `scripts/deploy-db.sh`
- `scripts/deploy-monitoring.sh`
- `scripts/deploy-backup.sh`
- `scripts/deploy-staging.sh`

## Quick usage

```bash
./scripts/deploy-staging.sh check
./scripts/deploy-staging.sh apply db
./scripts/deploy-staging.sh apply app
./scripts/deploy-staging.sh apply monitoring
./scripts/deploy-staging.sh apply backup
```

## Expected validation

- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`
- `nginx -t`
- `php-fpm8.3 -t`
- database connectivity validation
- HTTP/HTTPS smoke tests

## Live documentation

- [implementation-plan.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/implementation-plan.md)
- [standards/index.md](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/standards/index.md)

## Contact

- Owner: Renato de Souza Valadares
- Email: `rsvaladares@stefanini.com`
