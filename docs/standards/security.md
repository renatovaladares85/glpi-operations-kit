# Security Standard

## Base rules

- Never version secrets.
- Keep sensitive directories outside the web root.
- Use least privilege for SSH, database, and filesystem access.
- Restrict database access to authorized hosts only.
- Preserve TLS and restricted permissions.

## Sensitive GLPI layout

- code: `/usr/share/glpi`
- config: `/etc/glpi`
- data: `/var/lib/glpi/files`
- plugins: `/var/lib/glpi/plugins`
- logs: `/var/log/glpi`

## LGPD

- Avoid sensitive data in logs and examples.
- Restrict access to attachments and backups.
- Encrypt backups where applicable.

## Rules for agents

- When touching secrets, read this file first.
- If a new critical rule appears, promote it to `mandatory-rules.md`.
