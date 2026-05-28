# Backup and Restore Standard

This standard defines product-scope technical expectations only. Local governance rules must be defined by each project.

## Minimum backup set

- database dump
- copy of GLPI configuration directory (default `/etc/glpi`)
- copy of GLPI files/data directory (default `/var/lib/glpi/files`)
- copy of GLPI plugins directory (default `/var/lib/glpi/plugins`)

## Retention rule

- Retention days must be defined per environment/project through `BACKUP_RETENTION_DAYS`.
- This repository does not enforce fixed retention values for all installations.

## Restore rule

- Restore procedure must be documented for the local environment.
- Restore must be tested in a controlled target before considering backups reliable.
- Do not restore over partially migrated or unknown DB state.

## Rules for agents

- When changing backup behavior, document operational impact.
- When changing restore behavior, document risk and validation path.
