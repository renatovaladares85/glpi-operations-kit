# GLPI Operations Kit Manuals

This folder is the single central documentation hub for operators.

## Start Here

- Canonical guide (EN): [Operator Manual](en/user-manual.md)
- PT-BR mirror: [Manual do Operador](pt-br/user-manual.md)

## How This Manual Is Organized

1. Guided operational track (task-oriented, step-by-step): `docs/manual/en/guide/`
2. Technical references (deep details and field catalogs): `docs/manual/en/appendices/`
3. PT-BR mirrors the EN structure and intent.

## Quick Task Routing

- Install GLPI on Ubuntu (traditional Linux stack): [Deploy on Linux](en/guide/03-deploy-linux-traditional.md)
- Fill environment and topology settings: [Environment and Topology](en/guide/02-environment-and-topology.md)
- Configure TLS/HTTPS: [TLS and Certificates](en/guide/04-tls-and-certificates.md)
- Backup and restore: [Backup, Restore, and Restore Test](en/guide/05-backup-restore-and-restore-test.md)
- Upgrade GLPI in place: [Upgrade In Place](en/guide/06-glpi-upgrade-in-place.md)
- Validate and troubleshoot: [Validation and Troubleshooting](en/guide/08-validation-and-troubleshooting.md)
- Understand what automation already does: [Automation Coverage](en/guide/10-automation-coverage.md)
- Use Docker/Compose reference track: [Docker/Compose Reference](en/guide/09-docker-compose-reference.md)

## Technical and Contribution References

- [Architecture manuals](../architecture/README.md)
- [Open source contribution guide](../../CONTRIBUTING.md)
- [Product configuration reference](../product/configuration-reference.md)
- [Standards catalog](../standards/index.md)

## Runtime and Secrets Rule

<<<<<<< HEAD
1. User Manual.
2. Configuration Field Guide.
3. TLS Modes and Certificate Operations.
4. SSO manual configuration guide in GLPI, if external authentication is required.
5. Environment Examples.
6. Command Reference.
7. Troubleshooting Matrix.

## Runtime and secrets rule

- Public values: `config/<environment>.env`.
- Deployment secrets read from environment config: `DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD`.
- Runtime secrets file: `.runtime/<environment>/secrets.yml` only.
=======
- Public values: `config/<environment>.env`
- Runtime secrets: `.runtime/<environment>/secrets.yml`
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)
- Never commit `.runtime/`, private keys, tokens, real passwords, or customer-sensitive evidence.
