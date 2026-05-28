# GLPI Operations Kit - Operator Manual (EN, Canonical)

This is the canonical operator entrypoint.
It guides a complete GLPI Operations Kit installation from Linux shell and covers preparation, `.env` filling, TLS, database, application, monitoring, backup, validation, and rollback.

Use this page as a router:

1. start from the guided track;
2. run operational steps;
3. validate results;
4. open technical appendices only when you need deeper details.

## Operational Track (Guided)

1. [Start and Prechecks](guide/01-start-and-prechecks.md)
2. [Environment and Topology](guide/02-environment-and-topology.md)
3. [Deploy on Linux (Ubuntu + Nginx + PHP-FPM + MariaDB)](guide/03-deploy-linux-traditional.md)
4. [TLS and Certificates](guide/04-tls-and-certificates.md)
5. [Backup, Restore, and Restore Test](guide/05-backup-restore-and-restore-test.md)
6. [GLPI Upgrade In Place](guide/06-glpi-upgrade-in-place.md)
7. [Plugins and Marketplace (Manual Flow)](guide/07-plugins-and-marketplace.md)
8. [Validation and Troubleshooting](guide/08-validation-and-troubleshooting.md)
9. [Docker/Compose Reference Track (Separated)](guide/09-docker-compose-reference.md)
10. [Automation Coverage](guide/10-automation-coverage.md)

## Fast Routing by Intent

- I want to install GLPI: [Deploy on Linux](guide/03-deploy-linux-traditional.md)
- I want to configure environment values: [Environment and Topology](guide/02-environment-and-topology.md)
- I want TLS/HTTPS: [TLS and Certificates](guide/04-tls-and-certificates.md)
- I want backup: [Backup, Restore, and Restore Test](guide/05-backup-restore-and-restore-test.md)
- I want restore: [Backup, Restore, and Restore Test](guide/05-backup-restore-and-restore-test.md)
- I want to upgrade GLPI: [GLPI Upgrade In Place](guide/06-glpi-upgrade-in-place.md)
- I want to validate services and health: [Validation and Troubleshooting](guide/08-validation-and-troubleshooting.md)
- I have an error: [Validation and Troubleshooting](guide/08-validation-and-troubleshooting.md)
- I want to understand automation behavior: [Automation Coverage](guide/10-automation-coverage.md)
- I need command details: [Command Reference](appendices/command-reference.md)

## Technical References (Deep Detail)

Use these when you need detailed field-level or protocol-level explanations:

- [Appendices Index](appendices/index.md)
- [Environment Configuration Field Guide](appendices/configuration-field-guide.md)
- [TLS Modes and Certificate Operations](appendices/tls-modes.md)
- [Authentication, SSO, and Azure/Entra ID Guide](appendices/auth-sso-guide.md)
- [Runtime Inputs and Files](appendices/runtime-input-reference.md)
- [Command Reference](appendices/command-reference.md)
- [Operational Checks](appendices/operational-checks.md)
- [Troubleshooting Matrix](appendices/troubleshooting-matrix.md)

## Scope Notes

- EN is canonical.
- PT-BR mirrors EN after canonical updates.
- Docker/Compose is documented as a separated reference track in this phase.
