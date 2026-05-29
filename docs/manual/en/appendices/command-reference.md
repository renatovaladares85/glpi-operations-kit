# Appendix - Command Reference (EN)

This appendix complements the main runbook with direct commands and richer operational intent. The command syntax is always the same; what changes is the environment name and the values in `config/<environment>.env`.

If your current task is `.env` synchronization, go directly to the sections `Generate or recover .env.sync.yml` and `Environment file sync (env-sync)` in this file.

## Prepare host tooling

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

Use this when the execution host is new or missing dependencies.

## Prepare script permissions

```bash
bash scripts/bootstrap-permissions.sh
```

Run this before the first deployment command in a new operator session.

## Create and edit environment configuration

```bash
cp config/.env.example config/staging.env
```

This creates your environment baseline. The scripts read this file automatically.

## Generate or recover `.env.sync.yml`

`scripts/env-sync.py` depends on `.env.sync.yml` at the repository root.

If the file was removed locally by mistake, recover the version tracked by Git:

```bash
git restore .env.sync.yml
```

If you are creating a rules file from zero, start with a minimal valid structure and then expand it:

```yaml
version: 1
defaults:
  add_missing: true
  remove_extra: false
  backup: true
  default_mode: report
  apply_managed_changes: false
  backup_dir: ".env-backups"

keys:
  GLPI_DOMAIN:
    description: "Public GLPI domain."
    required: true
    policy: protected
  DATABASE_NAME:
    description: "GLPI database schema."
    required: true
    policy: protected
```

Required fields for each key are `description`, `required`, and `policy`.
Supported policies are `protected`, `managed`, `review_required`, and `deprecated`.

Validate the file before running apply mode:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/.env.example \
  --rules .env.sync.yml \
  --mode report
```

When this check still reports `no rule in .env.sync.yml`, add missing key rules and rerun.

## Environment file sync (env-sync)

Use `scripts/env-sync.py` to compare the kit baseline template (`config/.env.example`) against an environment file (`config/<environment>.env`) using policy rules from `.env.sync.yml`.

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode report
```

Apply only allowed changes:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode apply \
  --allow-managed
```

Force one reviewed key (explicit/manual operation):

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode apply \
  --force-reviewed QUEUE_CONNECTION
```

Generate a report file:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode report \
  --write-report .runtime/reports/env-sync-production.txt
```

Operational notes:

- Default mode is `report` (no file changes).
- `apply` creates backup before any write (`.env-backups/` by default).
- `protected` keys are preserved.
- `review_required` keys are never changed unless explicitly listed in `--force-reviewed`.
- Secrets are masked in terminal and file reports.
- The tool does not rename or replace your current real environment file naming model.

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

## Optional SSH mode

```bash
GLPI_EXECUTION_MODE=ssh ./scripts/glpictl.sh staging deploy check all
```

Use this only when policy allows remote orchestration from one host.

## Web routing and install-flow validation

```bash
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy post-check app
```

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

## SSO operation note

SSO/SAML/OIDC setup is performed manually in GLPI and IdP. There is no `auth` domain in the current CLI contract.

## Unified GLPI backup and restore (app|db|all)

```bash
sudo ./scripts/backup-app.sh backup --target all --encrypt
sudo ./scripts/backup-app.sh backup --target app --exclude-app "var/_cache,var/_sessions"
sudo ./scripts/backup-app.sh backup --target db --exclude-db-tables-data "glpi_logs,glpi_sessions"

sudo ./scripts/backup-app.sh restore --target app --artifact /tmp/glpi-backups/<file>.tar.gz --force
sudo ./scripts/backup-app.sh restore --target db --artifact /tmp/glpi-backups/<file>.tar.gz --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
sudo ./scripts/backup-app.sh restore --target all --artifact /tmp/glpi-backups/<file>.tar.gz --force --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
```

## Manual Ansible fallback

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```
