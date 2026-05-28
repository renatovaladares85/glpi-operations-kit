# Appendix - Command Reference (EN)

This appendix complements the main runbook with direct commands and richer operational intent. The command syntax is always the same; what changes is the environment name and the values in `config/<environment>.env`.

## Prepare host tooling

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

Use this when the execution host is new or missing dependencies. It installs the minimum toolchain required by scripts, runtime rendering, and Ansible execution.

## Prepare script permissions

```bash
bash scripts/bootstrap-permissions.sh
```

Run this before the first deployment command in a new operator session. It fixes executable bits, validates `sudo`, validates `glpiops` membership, and secures `.runtime` baseline permissions.

## Create and edit environment configuration

```bash
cp config/product.env config/staging.env
```

This creates your environment baseline. The scripts read this file automatically, so manual `export` is not required for normal operation.

## Core deployment commands

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy prepare all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
./scripts/glpictl.sh <env> deploy rollback all
```

Example with filled values:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy prepare all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging deploy rollback all
```

`deploy check all` is the operational gate before mutation. It validates tools, permissions, policy flags, inventory rendering, host role consistency, and runtime baseline materialization. In app-host local flow, it also validates `mariadb-client` and can auto-fix `php-bcmath` for GLPI 11. `deploy apply db` handles MariaDB packages, hardening, schema, user grants, and DB-access restrictions. `deploy apply app` configures GLPI application layout, selected web engine (`nginx`, `apache`, or `lighttpd`), PHP-FPM, mandatory PHP extension checks, and APP->DB connectivity validation (`SELECT 1`). `deploy apply monitoring` applies exporter baseline and monitoring wiring. `deploy apply backup` applies backup baseline and retention-related settings. `deploy post-check all` confirms service validity after mutable stages and prints explicit web-engine summary.

## Dual-server local flow (no direct SSH between servers)

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

This flow is designed for corporate networks that require interactive login with password and 2FA per host.

## Optional SSH mode

```bash
GLPI_EXECUTION_MODE=ssh ./scripts/glpictl.sh staging deploy check all
```

Use this only when policy allows remote orchestration from one host. In ssh mode, private key policy (`0600`) and target reachability become mandatory checks.

## Web routing and install-flow validation

```bash
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy post-check app
```

Example with filled values:

```bash
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy post-check app
```

These commands now validate the selected web engine routing contract end-to-end: root access, installer compatibility route (`/install/install.php` when installer is expected), representative `.js/.css` assets discovered from the page, blocked sensitive paths (`/config`, `/files`, `/vendor`), and safe router handling for unknown PHP-like paths.

## TLS lifecycle commands

```bash
./scripts/glpictl.sh <env> tls check
./scripts/glpictl.sh <env> tls prepare self-signed
./scripts/glpictl.sh <env> tls apply self-signed
./scripts/glpictl.sh <env> tls post-check
./scripts/glpictl.sh <env> tls rollback
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

Example with filled values:

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging tls prepare self-signed
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh staging tls post-check
./scripts/glpictl.sh staging tls rollback
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

`disable` enforces HTTP-only mode, `self-signed` creates and applies local test certificates, `install-provided` installs real cert/key material, and `reload` validates and reloads effective Nginx TLS configuration.

## Certification, readiness, and evidence

```bash
./scripts/glpictl.sh staging certify check
./scripts/glpictl.sh staging certify prepare
./scripts/glpictl.sh staging certify run
./scripts/glpictl.sh staging certify apply
./scripts/glpictl.sh staging certify post-check
./scripts/glpictl.sh staging certify rollback
bash scripts/release-readiness.sh staging
```

These commands generate certification and readiness evidence under `.runtime/<env>/evidence` and `.runtime/<env>/state`.

## Day-2 operations

```bash
./scripts/glpictl.sh <env> ops check
./scripts/glpictl.sh <env> ops prepare
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit check
./scripts/glpictl.sh <env> ops timezone check
./scripts/glpictl.sh <env> ops timezone apply
./scripts/glpictl.sh <env> ops resume
./scripts/glpictl.sh <env> ops rollback
./scripts/glpictl.sh <env> audit check
./scripts/glpictl.sh <env> audit prepare
./scripts/glpictl.sh <env> audit rollback
```

Example with filled values:

```bash
./scripts/glpictl.sh staging ops check
./scripts/glpictl.sh staging ops prepare
./scripts/glpictl.sh staging ops users add os
./scripts/glpictl.sh staging ops users disable db
./scripts/glpictl.sh staging ops users remove os
./scripts/glpictl.sh staging ops cert check
./scripts/glpictl.sh staging ops cert renew
./scripts/glpictl.sh staging ops audit check
./scripts/glpictl.sh staging ops timezone check
./scripts/glpictl.sh staging ops timezone apply
./scripts/glpictl.sh staging ops resume
./scripts/glpictl.sh staging ops rollback
./scripts/glpictl.sh staging audit check
./scripts/glpictl.sh staging audit prepare
./scripts/glpictl.sh staging audit rollback
```

These commands support controlled user lifecycle, certificate lifecycle, timezone readiness/apply workflow (OS/PHP/DB), operational audits, and resumable maintenance.

## Optional authentication workflow

```bash
./scripts/glpictl.sh <env> auth check
./scripts/glpictl.sh <env> auth prepare
./scripts/glpictl.sh <env> auth apply
./scripts/glpictl.sh <env> auth post-check
./scripts/glpictl.sh <env> auth rollback
```

Example with filled values:

```bash
./scripts/glpictl.sh staging auth check
./scripts/glpictl.sh staging auth prepare
./scripts/glpictl.sh staging auth apply
./scripts/glpictl.sh staging auth post-check
./scripts/glpictl.sh staging auth rollback
```

The auth domain validates and prepares local/LDAP/SAML/OIDC configuration safely, preserves local admin access, and provides evidence + rollback metadata without auto-installing plugins.

## Unified GLPI backup and restore (app|db|all)

```bash
sudo ./scripts/backup-app.sh backup --target all --encrypt
sudo ./scripts/backup-app.sh backup --target app --exclude-app "var/_cache,var/_sessions"
sudo ./scripts/backup-app.sh backup --target db --exclude-db-tables-data "glpi_logs,glpi_sessions"

sudo ./scripts/backup-app.sh restore --target app --artifact /var/backups/glpi/<file>.tar.gz --force
sudo ./scripts/backup-app.sh restore --target db --artifact /var/backups/glpi/<file>.tar.gz --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
sudo ./scripts/backup-app.sh restore --target all --artifact /var/backups/glpi/<file>.tar.gz --force --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
```

`backup-app.sh` now uses a single `backup|restore` contract with `--target app|db|all`. The `app` scope preserves GLPI core, config, and external GLPI paths in one package. The `db` scope creates a dump with table-data exclusions (`--exclude-db-tables-data`) while preserving schema. Restore is safe-by-default: app restore refuses populated destinations without `--force`, and DB restore refuses non-empty databases without `--db-recreate`.

## Manual Ansible fallback

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

Use fallback Ansible commands only when central CLI orchestration is temporarily unavailable.
