# Implementation Plan

## Objective

This repository defines a reusable GLPI operations kit using Ansible, guided execution scripts, and operational documentation.

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
- Domain example: `glpi-staging.example.internal`

### Production

- App host: `4 vCPU / 12 GB RAM / 200 GB`
- DB host: `8 vCPU / 32 GB RAM / 500 GB`
- Domain example: `glpi.example.internal`

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
- Public configuration lives under `config/<environment>.yml`.
- Guided Bash scripts collect only missing secret values at runtime.
- Central execution CLI: `scripts/glpictl.sh <environment> <domain> <action> [target] [scope]`.
- Specific scripts are supported as wrappers and follow the same central execution path.
- Runtime secrets are stored locally under `.runtime/<environment>/secrets.yml` and are ignored by Git.
- Runtime inventory, rendered public variables, and mutable overrides are stored under `.runtime/<environment>/`.
- Runtime precedence is explicit: `public.runtime.yml -> overrides.runtime.yml -> secrets.yml`.
- Runtime state is split by purpose:
  - rendered config files under `.runtime/<environment>/`
  - operation state/log/evidence under `.runtime/<environment>/{state,logs,evidence}`
- Environment pre-flight checks must run before implementation starts.
- Pre-flight results must be labeled as `mandatory` or `optional`.
- Mandatory failures must block execution unless the user explicitly authorizes continuation.
- Missing critical information must stop execution with a clear explanation.
- Ansible applies the server state after the guided script prepares the context.
- Production execution is blocked by a formal promotion gate generated from staging certification evidence.
- Readiness declaration must run `bash scripts/release-readiness.sh <environment>` and pass all critical checks.

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

## Promotion model (checklist + evidence)

- `Phase 1 - Staging certification`
  - run full validation checks;
  - generate timestamped evidence package;
  - mark gate as approved only when all mandatory checks pass.
- `Phase 2 - Production rollout`
  - blocked by default without approved gate;
  - run production deployment with runtime values only;
  - execute post-check and collect evidence.

Gate artifacts:

- Staging evidence: `.runtime/staging/evidence/<certification-id>/`
- Promotion gate file: `.runtime/promotion/staging-certified.yml`

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

- real customer identity and branding values
- real IPs and hostnames for all servers
- final SSH user and key path
- final GLPI target version approval
- final TLS certificate strategy
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
- promotion gate approval before any production apply run

## Change log

- `2026-04-28`: initial implementation skeleton for staging and production baseline.
