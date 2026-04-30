# Security Standard

## Base rules

- Never version secrets.
- Keep sensitive directories outside the web root.
- Use least privilege for SSH, database, and filesystem access.
- Restrict database access to authorized hosts only.
- Preserve TLS and restricted permissions.
- Security policy is environment-agnostic and controlled per execution by `SECURITY_MODE`.
- In `secure` mode, policy rules block execution.
- In `permissive` mode, policy rules become warnings and require explicit risk justification with persisted evidence.
- Never use common, obvious, or easily guessable usernames, passwords, or identifiers.
- When generating or suggesting names for users, service accounts, aliases, or internal labels, use biblical-context naming by default.
- Biblical context must not reduce secret strength: passwords, tokens, and keys must remain high-entropy and non-predictable.
- Never hardcode real customer names in reusable product code or documentation. Keep customer identity configurable and generic.

## Naming and credential generation

- Allowed for names and identifiers:
  - biblical person references
  - biblical place references
  - biblical-theme aliases that are not generic defaults
- Not allowed for secrets:
  - plain biblical words such as `david`, `genesis`, or `jerusalem`
  - predictable combinations such as `Moses123`, `Psalm2026`, or `Solomon!`
  - reused naming patterns that reveal role and secret theme together
- Required for secrets:
  - strong randomness
  - sufficient length
  - no recognizable default pattern
  - no direct reuse of the visible account name

## Examples

- Good account names:
  - `nehemiah_ops`
  - `bezalel_backup`
  - `issachar_monitor`
- Bad account names:
  - `admin`
  - `glpi`
  - `mysqluser`
- Good secret strategy:
  - biblical-context account name plus a randomly generated secret
- Bad secret strategy:
  - a biblical word with a year or symbol appended

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
