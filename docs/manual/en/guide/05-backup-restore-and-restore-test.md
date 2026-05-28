# 05 - Backup, Restore, and Restore Test

This chapter explains backup and restore from an operational perspective without fixing customer-specific governance rules. Process rules must follow each project's local policy.

In this kit, there are two complementary flows.

## Flow 1: environment backup baseline (`glpictl`)

When you apply the backup baseline, the kit prepares recurring backup routines on Linux hosts.

```bash
./scripts/glpictl.sh <environment> deploy apply backup
```

In practice, this flow configures:

- backup directories under `BACKUP_BASE_DIR` (db, files, config, plugins);
- database dump script on DB host;
- file/config/plugin backup script on APP host;
- `cron` scheduling;
- retention driven by `BACKUP_RETENTION_DAYS`.

Where to tune it:

- `BACKUP_BASE_DIR`
- `BACKUP_RETENTION_DAYS`

These keys are set in `config/<environment>.env`. Field-level details are in [Environment Configuration Field Guide](../appendices/configuration-field-guide.md).

## Flow 2: transferable backup/restore (`backup-app.sh`)

This is a guided manual flow to produce a single migration/recovery artifact.

Base commands:

```bash
sudo ./scripts/backup-app.sh backup --target <app|db|all> [options]
sudo ./scripts/backup-app.sh restore --target <app|db|all> --artifact <file> [options]
```

`--target` defines scope:

- `app`: application files and configuration;
- `db`: database dump and restore;
- `all`: app + db.

### How database parameters behave

For `backup` with `db` or `all`, you can pass parameters explicitly (`--db-host`, `--db-port`, `--db-user`, `--db-password`, `--db-name`).

If host/user/name are omitted in backup mode, the script tries to resolve them from GLPI `config_db.php`. If required values are still missing, execution stops and tells you which parameter is missing.

For `restore` with `db` or `all`, `--db-host`, `--db-user`, and `--db-name` are required. Password can be provided with `--db-password` or entered through secure prompt during execution.

### Important controls

- `--artifact`: input/output artifact path.
- `--output-dir` and `--artifact-name`: control backup destination and file name.
- `--exclude-app`: excludes app areas as CSV (`core/`, `config/`, `var/`, `log/`, `plugins/`, `marketplace/`, or absolute path).
- `--exclude-db-tables-data`: excludes only data from selected tables in dump.
- `--encrypt` and `--passphrase-file`: encrypt final artifact.
- `--force`: in app restore, allows overwrite when destination is already populated.
- `--db-recreate`: in DB restore, recreates database before import.

Warning: `--db-recreate` removes current database content before import. Confirm target before running.

Warning: `--force` can overwrite existing content during app restore.

### Practical examples

Encrypted full backup:

```bash
sudo ./scripts/backup-app.sh backup --target all --output-dir /var/backups/glpi --encrypt
```

Database-only backup with explicit parameters:

```bash
sudo ./scripts/backup-app.sh backup --target db --db-host 127.0.0.1 --db-port 3306 --db-user glpi_backup --db-name glpi
```

Database restore with recreate:

```bash
sudo ./scripts/backup-app.sh restore --target db --artifact /var/backups/glpi/glpi-transfer.tar.gz --db-host 127.0.0.1 --db-port 3306 --db-user glpi_restore --db-name glpi --db-recreate
```

Full restore (app + db):

```bash
sudo ./scripts/backup-app.sh restore --target all --artifact /var/backups/glpi/glpi-transfer.tar.gz --force --db-host 127.0.0.1 --db-port 3306 --db-user glpi_restore --db-name glpi --db-recreate
```

## Post-restore validation

After restore, validate services, application, and connectivity:

```bash
./scripts/glpictl.sh <environment> deploy post-check all
./scripts/glpictl.sh <environment> audit check
```

If needed, validate directly on host:

```bash
nginx -t
systemctl status nginx
systemctl status php8.3-fpm
mysql --version
```

## Common errors and quick action

- error: invalid artifact or checksum mismatch
- action: generate a new artifact and validate integrity before restore

- error: DB restore without required parameters
- action: pass `--db-host`, `--db-user`, `--db-name` and rerun

- error: database already has tables
- action: use `--db-recreate` only when database replacement is intentional

## Go next

- [Backup and Restore Standard](../../../standards/backup-restore.md)
- [Command Reference](../appendices/command-reference.md)
- [Operational Checks](../appendices/operational-checks.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
