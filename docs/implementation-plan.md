# Implementation Plan

## Objective

This repository defines the desired state for GLPI SoEnergy using Ansible, guided execution scripts, and operational documentation.

The current implementation targets:

- `staging` as a reduced mirror of production
- separate `application` and `database` servers
- `Ubuntu 24.04`
- `GLPI 11.x`
- `Nginx + PHP-FPM + MariaDB`
- no containers in the first phase

## Environment topology

### Staging

- App host: `2 vCPU / 4 GB RAM / 80 GB`
- DB host: `2 vCPU / 4 GB RAM / 120 GB`
- Domain: `servicedesk-hml.soenergy.com`

### Production

- App host: `4 vCPU / 12 GB RAM / 200 GB`
- DB host: `8 vCPU / 32 GB RAM / 500 GB`
- Domain: `servicedesk.soenergy.com`

## Directory layout

- GLPI code: `/usr/share/glpi`
- GLPI config: `/etc/glpi`
- GLPI variable data: `/var/lib/glpi/files`
- GLPI plugins: `/var/lib/glpi/plugins`
- GLPI logs: `/var/log/glpi`
- Backups: `/var/backups/glpi`

## Execution model

- All declarative state lives in Git.
- Secrets do not live in Git.
- Guided Bash scripts collect sensitive values at runtime.
- Runtime secrets are stored locally under `.runtime/<environment>/` and are ignored by Git.
- Runtime inventory and non-sensitive staging overrides are stored under `.runtime/<environment>/`.
- Environment pre-flight checks must run before implementation starts.
- Pre-flight results must be labeled as `mandatory` or `optional`.
- Mandatory failures must block execution unless the user explicitly authorizes continuation.
- Missing critical information must stop execution with a clear explanation.
- Ansible applies the server state after the guided script prepares the context.

## Current repository structure

```text
ansible/
  inventories/
  roles/
  site.yml
scripts/
  lib/
docs/
```

## Roles implemented

### base

- baseline packages
- timezone and NTP
- SSH hardening
- firewall bootstrap

### app

- GLPI package dependencies
- GLPI download and filesystem layout
- PHP-FPM pool
- Nginx vhost
- GLPI downstream and local_define files
- cron wrapper

### db

- MariaDB installation
- MariaDB tuning
- DB creation
- user creation
- root hardening

### monitoring

- node exporter
- mysqld exporter

### backup

- DB backup script
- file/config/plugin backup script
- retention jobs

## Security decisions

- Only `/public` should be exposed by the web server.
- Sensitive directories are stored outside the document root.
- SSH password login is disabled by default.
- Firewall is enabled locally.
- PHP session cookies are hardened.
- Database access is intended only from application hosts.
- Staging supports `none`, `self_signed`, and `provided` TLS modes.
- Valid certificate replacement must be handled by a script-driven workflow.

## Operational gaps that still need real environment data

- real IPs and hostnames for all servers
- final SSH user and key path
- GLPI target version approval
- TLS certificate strategy
- SMTP settings
- LDAP/AD settings
- backup encryption mechanism
- Prometheus/Grafana/Alertmanager central deployment details
- exact firewall source networks

## Validation checklist

- environment pre-flight checks
- runtime inventory generation
- TLS mode selection and certificate path validation
- `ansible-inventory --list`
- `ansible-playbook --syntax-check site.yml`
- `nginx -t`
- `php-fpm8.3 -t`
- MariaDB connectivity checks
- guided secret prompt flow
- smoke test after deployment

## Change log

- `2026-04-28`: initial implementation skeleton for staging and production baseline.
