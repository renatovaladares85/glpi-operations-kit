# GLPI Operations Kit - Operator Manual (EN, Canonical)

<<<<<<< HEAD
This manual guides a complete GLPI Operations Kit installation from Linux shell. It covers preparation, `.env` filling, TLS, database, application, monitoring, backup, validation, and rollback.
=======
This is the canonical operator entrypoint.
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

Use this page as a router:

1. start from the guided track;
2. run operational steps;
3. validate results;
4. open technical appendices only when you need deeper details.

<<<<<<< HEAD
1. [Prerequisites](#prerequisites)
2. [Files you need to fill](#files-you-need-to-fill)
3. [Recommended flow from zero](#recommended-flow-from-zero)
4. [Topology choice](#topology-choice)
5. [TLS and certificates](#tls-and-certificates)
6. [SSO manual configuration in GLPI](#sso-manual-configuration-in-glpi)
7. [Database, application, monitoring, and backup](#database-application-monitoring-and-backup)
8. [Validation, evidence, and rollback](#validation-evidence-and-rollback)
9. [Appendices](#appendices)
=======
## Operational Track (Guided)
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

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

<<<<<<< HEAD
- Linux access with `sudo` when required.
- Repository available on the execution host.
- `config/<environment>.env` created from `config/product.env`.
- Strong secrets available for database and monitoring.
- GLPI FQDN defined, especially when TLS is used.
- Topology decision: `single-server` or `dual-server`.
- Execution decision: `local` or `ssh`.
=======
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
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

## Technical References (Deep Detail)

<<<<<<< HEAD
```bash
bash scripts/bootstrap-permissions.sh
```

## Files you need to fill

| File | Purpose | Commit to Git? |
|---|---|---|
| `config/product.env` | Versioned product template. | Yes. Do not put real sensitive values. |
| `config/<environment>.env` | Environment public config plus 3 deployment secrets (`DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD`). | Do not commit real environment copies. |
| `.runtime/<environment>/secrets.yml` | Runtime secrets used by execution flows. | Never. |
| `.runtime/<environment>/public.runtime.yml` | Public runtime rendered by scripts. | Never. |
| `.runtime/<environment>/evidence/` | Execution evidence. | Never, except sanitized audit packages outside Git. |
| `.runtime/<environment>/backups/` | Domain snapshots/backups. | Never. |

Secret flow note:

- The 3 deployment secrets stored in `config/<environment>.env` are materialized by automation into `.runtime/<environment>/secrets.yml`.
- SSO/IdP credentials are configured manually in GLPI and in the IdP, outside kit orchestration.

To fill each `.env` key, use [Environment Configuration Field Guide](appendices/configuration-field-guide.md).

## Recommended flow from zero

1. Create environment config.

```bash
cp config/product.env config/staging.env
```

2. Fill `config/staging.env` using the field guide.

3. Run precheck.

```bash
./scripts/glpictl.sh staging deploy check all
```

4. Apply database, application, monitoring, and backup in the correct order.

```bash
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

5. Validate TLS when applicable.

```bash
./scripts/glpictl.sh staging tls check
```

6. Generate final evidence.

```bash
./scripts/glpictl.sh staging audit check
bash scripts/release-readiness.sh staging
```

## Topology choice

Use `TOPOLOGY_MODE=single-server` when app and DB are on the same host. Use `EXECUTION_HOST_ROLE_DEFAULT=all`.

Use `TOPOLOGY_MODE=dual-server` when app and DB are on separate hosts. In local execution without direct SSH between servers:

On DB host:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

On APP host:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Use `EXECUTION_MODE=ssh` only when policy allows remote orchestration and the private key is available with restricted permissions.

## TLS and certificates

The kit supports `TLS_MODE=none`, `TLS_MODE=self_signed`, and `TLS_MODE=provided`.

For production, the expected path is `provided`: HTTPS server certificate, full PEM chain, and matching PEM private key. It is not a client certificate. mTLS/client certificate is not automated by the current kit.

Read [TLS Modes and Certificate Operations](appendices/tls-modes.md) before requesting a certificate from CA/security.

## SSO manual configuration in GLPI

SSO/SAML/OIDC is configured directly in the GLPI application and in the identity provider (for example Entra ID). The kit does not automate IdP integration and does not apply SSO settings through scripts.

Recommended operational sequence:

1. Keep a tested local admin fallback in GLPI.
2. Install/enable the SSO plugin manually in GLPI when required.
3. Configure IdP metadata, claims, and JIT mapping directly in GLPI.
4. Run pilot login tests before enabling production users.

Use [Authentication, SSO, and Azure/Entra ID Guide](appendices/auth-sso-guide.md) as an app-level checklist.

## Database, application, monitoring, and backup

Main deploy syntax:

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Filled example:

```bash
./scripts/glpictl.sh staging deploy apply app
```

Core commands:

| Command | Purpose |
|---|---|
| `deploy check all` | Validates tools, permissions, config, runtime, policy, and inventory. |
| `deploy apply db` | Installs/configures MariaDB, schema, user, and grants. |
| `deploy apply app` | Installs GLPI, web engine, PHP-FPM, secure paths, and APP -> DB connectivity. |
| `deploy apply monitoring` | Applies exporters and observability baseline. |
| `deploy apply backup` | Applies backup/retention baseline. |
| `deploy post-check all` | Validates final state. |

Use [Command Reference](appendices/command-reference.md) for the complete list.

## Validation, evidence, and rollback

Runtime, evidence, and backup files live under `.runtime/<environment>/`.

Important structures:

| Structure | Use |
|---|---|
| `.runtime/<env>/state/` | Checkpoints and state pointers. |
| `.runtime/<env>/evidence/` | Domain evidence. |
| `.runtime/<env>/backups/<domain>/<timestamp>/` | Domain snapshots with manifest and rollback instructions. |

Standardized commands where available:

```bash
./scripts/glpictl.sh staging tls rollback
./scripts/glpictl.sh staging ops rollback
./scripts/glpictl.sh staging audit rollback
./scripts/glpictl.sh staging deploy rollback all
```

Local metadata rollback restores runtime/evidence/state for the domain. Rollback for manual changes in GLPI, IAM, external certificates, or remote infrastructure must follow the responsible team's operational checklist.

## Appendices
=======
Use these when you need detailed field-level or protocol-level explanations:
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

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
