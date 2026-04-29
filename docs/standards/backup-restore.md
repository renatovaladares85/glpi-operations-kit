# Backup and Restore Standard

## Minimum backup set

- database dump
- copy of `/etc/glpi`
- copy of `/var/lib/glpi/files`
- copy of `/var/lib/glpi/plugins`

## Initial retention

- `staging`: 14 days
- `production`: 30 days

## Restore

- Document the procedure
- Test restore regularly
- Do not restore a backup into a partially migrated database

## Rules for agents

- When changing backups, document operational impact
- When changing restore behavior, document risk and validation
