# Appendix: Runtime Input Reference

## Overview

The staging orchestrator collects runtime values before `apply` or `post-check`.

Generated files:

- `.runtime/staging/inventory.runtime.yml`
- `.runtime/staging/app.runtime.yml`
- `.runtime/staging/db.secrets.yml`
- `.runtime/staging/monitoring.secrets.yml`

## Runtime Inputs

### Staging app server IP/hostname

- Why: target host for GLPI app deployment
- Validation: non-empty + hostname/IP format
- Stored in: `inventory.runtime.yml`

### Staging database server IP/hostname

- Why: target host for MariaDB deployment
- Validation: non-empty + hostname/IP format
- Stored in: `inventory.runtime.yml`

### SSH username

- Why: Ansible remote login
- Validation: non-empty
- Stored in: `inventory.runtime.yml`

### SSH private key path

- Why: Ansible SSH authentication
- Validation: non-empty + file exists
- Stored in: `inventory.runtime.yml`

### Final GLPI version

- Why: explicit release selection for archive and release dir
- Validation: non-empty
- Stored in: `app.runtime.yml`

### TLS mode (`none` / `self_signed` / `provided`)

- Why: controls Nginx and certificate behavior
- Validation: exact choice
- Stored in: `app.runtime.yml`

### Local TLS certificate path (provided mode only)

- Why: source certificate for deployment
- Validation: file exists
- Stored in: `app.runtime.yml`

### Local TLS private key path (provided mode only)

- Why: source key for deployment
- Validation: file exists
- Stored in: `app.runtime.yml`

### GLPI database name

- Why: database creation and app connectivity
- Validation: non-empty
- Stored in: `db.secrets.yml`

### GLPI database username

- Why: app database account
- Validation: non-empty
- Stored in: `db.secrets.yml`

### GLPI database password

- Why: app database authentication
- Validation: non-empty
- Stored in: `db.secrets.yml`

### MariaDB root password

- Why: hardening and schema/account provisioning
- Validation: non-empty
- Stored in: `db.secrets.yml` and `monitoring.secrets.yml`

### `mysqld_exporter` username

- Why: monitoring account creation
- Validation: non-empty
- Stored in: `monitoring.secrets.yml`

### `mysqld_exporter` password

- Why: monitoring account authentication
- Validation: non-empty
- Stored in: `monitoring.secrets.yml`
