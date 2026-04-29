# Appendix: Runtime Input Reference

## Overview

The staging orchestrator collects runtime values before `apply` or `post-check`.

Generated files:

- `.runtime/staging/inventory.runtime.yml`
- `.runtime/staging/app.runtime.yml`
- `.runtime/staging/db.secrets.yml`
- `.runtime/staging/monitoring.secrets.yml`

## Topology Guidance

- Single-server mode: set app host and db host to the same host.
- Dual-server mode: set app host and db host to distinct hosts.
- Script execution can start from app host or db host, as long as SSH key access exists to all targets.

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

## Manual File Models (No Script Path)

`inventory.runtime.yml`:

```yaml
---
all:
  vars:
    ansible_user: "YOUR_SSH_USER"
    ansible_ssh_private_key_file: "/path/to/your/key"
    environment_name: "staging"
  children:
    glpi_app:
      hosts:
        stg-app:
          ansible_host: "APP_HOST_OR_IP"
    glpi_db:
      hosts:
        stg-db:
          ansible_host: "DB_HOST_OR_IP"
```

`app.runtime.yml`:

```yaml
---
glpi_version: "11.0.0"
glpi_download_url: "https://github.com/glpi-project/glpi/releases/download/11.0.0/glpi-11.0.0.tgz"
glpi_release_dir: "/usr/share/glpi-11.0.0"
glpi_domain: "APP_HOST_OR_IP"
glpi_use_tls: false
glpi_tls_mode: "none"
glpi_tls_common_name: "APP_HOST_OR_IP"
glpi_tls_provided_local_cert_path: ""
glpi_tls_provided_local_key_path: ""
```

`db.secrets.yml`:

```yaml
---
glpi_db_name: "glpi_db_name"
glpi_db_user: "glpi_db_user"
glpi_db_password: "CHANGE_ME"
glpi_db_root_password: "CHANGE_ME"
glpi_db_app_access_host: "APP_HOST_OR_IP"
```

`monitoring.secrets.yml`:

```yaml
---
mysqld_exporter_user: "exporter_user"
mysqld_exporter_password: "CHANGE_ME"
glpi_db_root_password: "CHANGE_ME"
```
