# 05 - Backup, Restore, and Restore Test

A backup is only trustworthy when restore has been tested.

Current automation baseline covers backup routines for:

- database dump;
- GLPI files;
- GLPI configuration;
- plugins.

Apply backup baseline:

```bash
./scripts/glpictl.sh staging deploy apply backup
```

Also protect manually (outside Git):

- environment file copies for recovery;
- runtime secrets;
- TLS certificate and key materials;
- infrastructure-specific dependencies required for rebuild.

Restore in this phase is manual guided operation, with repository rollback support focused on runtime metadata/domain snapshots.

Before running restore in production:

1. open maintenance window;
2. confirm fresh backup exists;
3. test restore path in staging or isolated environment;
4. validate application access after restore.

Validate after restore:

```bash
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging audit check
```

Common error and quick action:

- error: restore executed without tested backup set
- action: stop, rebuild backup set, run restore test in staging first

Go next:

- [Backup and Restore Standard](../../../standards/backup-restore.md)
- [Operational Checks](../appendices/operational-checks.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
