# GLPI Operations Kit - Operator Manual (EN)

This manual guides a complete GLPI Operations Kit installation from Linux shell. It covers preparation, `.env` filling, TLS, database, application, monitoring, backup, validation, and rollback.

You may edit files from Windows, but operational commands must run from Linux shell on the target host or a Linux execution host.

## Index

1. [Prerequisites](#prerequisites)
2. [Files you need to fill](#files-you-need-to-fill)
3. [Recommended flow from zero](#recommended-flow-from-zero)
4. [Topology choice](#topology-choice)
5. [TLS and certificates](#tls-and-certificates)
6. [SSO manual configuration in GLPI](#sso-manual-configuration-in-glpi)
7. [Database, application, monitoring, and backup](#database-application-monitoring-and-backup)
8. [Validation, evidence, and rollback](#validation-evidence-and-rollback)
9. [Appendices](#appendices)

## Prerequisites

Before changing the environment, confirm:

- Linux access with `sudo` when required.
- Repository available on the execution host.
- `config/<environment>.env` created from `config/product.env`.
- Strong secrets available for database and monitoring.
- GLPI FQDN defined, especially when TLS is used.
- Topology decision: `single-server` or `dual-server`.
- Execution decision: `local` or `ssh`.

Prepare permissions and local baseline:

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

- [Environment Configuration Field Guide](appendices/configuration-field-guide.md)
- [Environment Examples](appendices/environment-examples.md)
- [TLS Modes and Certificate Operations](appendices/tls-modes.md)
- [Authentication, SSO, and Azure/Entra ID Guide](appendices/auth-sso-guide.md)
- [Runtime Inputs and Files](appendices/runtime-input-reference.md)
- [Command Reference](appendices/command-reference.md)
- [Operational Checks](appendices/operational-checks.md)
- [Troubleshooting Matrix](appendices/troubleshooting-matrix.md)
