# GLPI Product Configuration Reference

## Purpose

This document defines the single public configuration model for the reusable GLPI deployment product.

Primary files:

- `config/product.example.yml`
- `config/staging.yml`
- `config/production.yml`

Secret file:

- `.runtime/<environment>/secrets.yml`

## Configuration Flow

1. Public values are defined in `config/<environment>.yml`.
2. Scripts render runtime files from that public config.
3. Missing secrets are requested at runtime and stored in `.runtime/<environment>/secrets.yml`.
4. Ansible consumes:
   - `.runtime/<environment>/public.runtime.yml`
   - `.runtime/<environment>/overrides.runtime.yml`
   - `.runtime/<environment>/secrets.yml`

## Precedence

Runtime values are merged in this order:

1. public base config rendered to `public.runtime.yml`
2. mutable runtime overrides from `overrides.runtime.yml`
3. runtime secrets from `secrets.yml`

Operational rule:

- public defaults and customer values must remain in `config/<environment>.yml`
- mutable operator changes (for example TLS mode transitions) must be written in `overrides.runtime.yml`
- secrets must remain only in `secrets.yml`

## Sections

### `product`

- `product.name`
  - Purpose: product display name.
  - Used by: documentation and runtime metadata.
  - Example: `GLPI Operations Kit`
  - Type: public.
- `product.slug`
  - Purpose: stable product identifier.
  - Used by: labels, automation, packaging.
  - Example: `glpi-operations-kit`
  - Type: public.
- `product.deployment_label`
  - Purpose: deployment-level label for this customer/environment set.
  - Used by: metadata and product packaging.
  - Example: `staging-reference`
  - Type: public.

### `customer`

- `customer.display_name`
  - Purpose: customer-facing display name.
  - Used by: monitoring labels and customer-facing docs.
  - Example: `Example Customer`
  - Type: public.
- `customer.short_name`
  - Purpose: compact customer identifier.
  - Used by: labels and conventions.
  - Example: `example-customer`
  - Type: public.

### `environment`

- `environment.name`
  - Purpose: exact environment selector.
  - Used by: scripts and runtime metadata.
  - Example: `staging`
  - Type: public.
- `environment.stage`
  - Purpose: descriptive lifecycle stage.
  - Used by: docs, labels, dashboards.
  - Example: `production`
  - Type: public.

### `topology`

- `topology.mode`
  - Purpose: target topology shape.
  - Used by: operator guidance and validation.
  - Example: `dual-server`
  - Type: public.
- `topology.app.alias`
  - Purpose: inventory alias for the app host.
  - Used by: generated inventory.
  - Example: `stg-app`
  - Type: public.
- `topology.app.host`
  - Purpose: real app host IP or FQDN.
  - Used by: generated inventory.
  - Example: `192.0.2.10`
  - Type: public.
- `topology.db.alias`
  - Purpose: inventory alias for the db host.
  - Used by: generated inventory.
  - Example: `stg-db`
  - Type: public.
- `topology.db.host`
  - Purpose: real db host IP or FQDN.
  - Used by: generated inventory.
  - Example: `192.0.2.20`
  - Type: public.

### `network`

- `network.ssh.user`
  - Purpose: SSH user for Ansible.
  - Used by: generated inventory.
  - Example: `ubuntu`
  - Type: public.
- `network.ssh.private_key_path`
  - Purpose: path to SSH private key on the execution host.
  - Used by: generated inventory and prechecks.
  - Example: `~/.ssh/id_rsa`
  - Type: public-sensitive path.
- `network.database.app_access_host`
  - Purpose: app-side host allowed to connect to MariaDB.
  - Used by: db role grants and firewall.
  - Example: `192.0.2.10`
  - Type: public.
- `network.database.allowed_source_hosts`
  - Purpose: explicit firewall allowlist for MariaDB.
  - Used by: db role UFW rules.
  - Example: `["192.0.2.10"]`
  - Type: public.

### `glpi`

- `glpi.version`
  - Purpose: exact GLPI version.
  - Used by: app role and download URL rendering.
  - Example: `11.0.0`
  - Type: public.
- `glpi.domain`
  - Purpose: public GLPI endpoint.
  - Used by: Nginx config and smoke tests.
  - Example: `glpi.example.internal`
  - Type: public.
- `glpi.upload_max_filesize`
  - Purpose: upload size limit.
  - Used by: PHP config template.
  - Example: `32M`
  - Type: public.
- `glpi.post_max_size`
  - Purpose: POST size limit.
  - Used by: PHP config template.
  - Example: `32M`
  - Type: public.
- `glpi.memory_limit`
  - Purpose: PHP memory limit.
  - Used by: PHP config template.
  - Example: `512M`
  - Type: public.
- `glpi.max_execution_time`
  - Purpose: PHP execution timeout.
  - Used by: PHP config template.
  - Example: `120`
  - Type: public.
- `glpi.opcache_memory_consumption`
  - Purpose: OPcache memory allocation.
  - Used by: PHP config template.
  - Example: `192`
  - Type: public.
- `glpi.filesystem.owner`
  - Purpose: owner for writable GLPI paths.
  - Used by: app role permissions.
  - Example: `www-data`
  - Type: public.
- `glpi.filesystem.group`
  - Purpose: group for writable GLPI paths.
  - Used by: app role permissions.
  - Example: `www-data`
  - Type: public.

### `database`

- `database.name`
  - Purpose: GLPI schema name.
  - Used by: db role.
  - Example: `glpi_operational`
  - Type: public.
- `database.user`
  - Purpose: GLPI DB username.
  - Used by: db role and app connectivity.
  - Example: `nehemiah_glpi`
  - Type: public.
- `database.port`
  - Purpose: MariaDB TCP port.
  - Used by: db role.
  - Example: `3306`
  - Type: public.
- `database.bind_address`
  - Purpose: MariaDB bind address.
  - Used by: db tuning template.
  - Example: `0.0.0.0`
  - Type: public.

### `php_fpm`

- `php_fpm.service_name`
  - Purpose: PHP-FPM service name.
  - Used by: handlers and templates.
  - Example: `php8.3-fpm`
  - Type: public.
- `php_fpm.socket`
  - Purpose: PHP-FPM socket path.
  - Used by: Nginx and pool config.
  - Example: `/run/php/php8.3-fpm.sock`
  - Type: public.
- `php_fpm.pm`
  - Purpose: PHP-FPM process manager mode.
  - Used by: pool template.
  - Example: `dynamic`
  - Type: public.

### `tls`

- `tls.mode`
  - Purpose: TLS mode selection.
  - Used by: app role and TLS operations.
  - Allowed: `none`, `self_signed`, `provided`
  - Type: public.
- `tls.common_name`
  - Purpose: TLS common name.
  - Used by: self-signed generation and validation.
  - Example: `glpi.example.internal`
  - Type: public.
- `tls.certificate_path`
  - Purpose: installed certificate path on target host.
  - Used by: Nginx template and checks.
  - Example: `/etc/ssl/certs/glpi-production.crt`
  - Type: public.
- `tls.private_key_path`
  - Purpose: installed private key path on target host.
  - Used by: Nginx template and checks.
  - Example: `/etc/ssl/private/glpi-production.key`
  - Type: public-sensitive path.
- `tls.provided_local_cert_path`
  - Purpose: local operator-side cert path for provided mode.
  - Used by: TLS management flow.
  - Type: public-sensitive path.
- `tls.provided_local_key_path`
  - Purpose: local operator-side private key path for provided mode.
  - Used by: TLS management flow.
  - Type: public-sensitive path.

### `backup`

- `backup.base_dir`
  - Purpose: target backup directory.
  - Used by: backup role.
  - Example: `/var/backups/glpi`
  - Type: public.
- `backup.retention_days`
  - Purpose: retention period.
  - Used by: backup scripts and cleanup jobs.
  - Example: `30`
  - Type: public.

### `monitoring`

- `monitoring.exporters.node.enabled`
  - Purpose: enable node exporter.
  - Used by: monitoring role.
  - Type: public.
- `monitoring.exporters.mysqld.enabled`
  - Purpose: enable mysqld exporter.
  - Used by: monitoring role.
  - Type: public.
- `monitoring.exporters.mysqld.user`
  - Purpose: exporter username.
  - Used by: monitoring role.
  - Example: `issachar_monitor`
  - Type: public.
- `monitoring.labels`
  - Purpose: standard labels for future monitoring stack integration.
  - Used by: blueprint and future dashboards/alerts.
  - Type: public.
- `monitoring.thresholds`
  - Purpose: warning/critical thresholds.
  - Used by: monitoring blueprint.
  - Type: public.
- `monitoring.scrape_profiles`
  - Purpose: Prometheus scrape defaults.
  - Used by: monitoring blueprint.
  - Type: public.
- `monitoring.dashboard_profile`
  - Purpose: dashboard selection profile.
  - Used by: monitoring blueprint.
  - Type: public.
- `monitoring.alert_routes`
  - Purpose: alert route metadata.
  - Used by: future Alertmanager integration.
  - Type: public.

### `alerting`

- `alerting.tls_expiry_warning_days`
  - Purpose: days-to-expiry warning threshold.
  - Used by: certificate operations and future alerts.
  - Type: public.
- `alerting.backup_failure_enabled`
  - Purpose: enable backup failure alerting.
  - Used by: monitoring blueprint.
  - Type: public.
- `alerting.service_down_enabled`
  - Purpose: enable service-down alerts.
  - Used by: monitoring blueprint.
  - Type: public.

### `paths`

- `paths.glpi_release_root`
- `paths.glpi_install_dir`
- `paths.glpi_config_dir`
- `paths.glpi_var_dir`
- `paths.glpi_plugin_dir`
- `paths.glpi_log_dir`
  - Purpose: filesystem layout.
  - Used by: app role.
  - Type: public.

### `operations`

- `operations.timezone`
  - Purpose: host timezone.
  - Used by: base role.
  - Example: `America/Sao_Paulo`
  - Type: public.
- `operations.glpi_cron_schedule`
  - Purpose: GLPI cron cadence.
  - Used by: app role cron wrapper.
  - Example: `*/5 * * * *`
  - Type: public.
- `operations.required_ops_group`
  - Purpose: required operator group.
  - Used by: scripts and docs.
  - Example: `glpiops`
  - Type: public.

### `resource_profiles`

- `resource_profiles.active`
  - Purpose: selected performance profile.
  - Used by: rendered public runtime file.
  - Example: `small`
  - Type: public.
- `resource_profiles.profiles.<name>.php_fpm.*`
  - Purpose: PHP-FPM sizing defaults.
  - Used by: rendered public runtime file.
  - Type: public.
- `resource_profiles.profiles.<name>.mariadb.*`
  - Purpose: MariaDB sizing defaults.
  - Used by: rendered public runtime file.
  - Type: public.

## Runtime Secrets

Stored only in `.runtime/<environment>/secrets.yml`.

Required keys:

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

Future secret keys:

- SMTP credentials
- LDAP bind credentials
- private TLS distribution material if automation is expanded
