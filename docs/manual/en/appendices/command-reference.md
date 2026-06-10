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

`scripts/env-sync.py` supports contract generation mode with automatic environment discovery.

Default generation command (review-first output, no overwrite of `.env.sync.yml`):

```bash
python3 scripts/env-sync.py --generate-contract
```

What it does:

- Uses `config/.env.example` as official key source.
- Discovers real environments only from `config/*.env` (excluding `config/.env.example`).
- Generates `.env.sync.generated.yml`.
- Writes audit report to `docs/env-sync-contract-report.md`.
- Runs post-check reports (self-check + discovered environments).

Publish the generated contract to `.env.sync.yml` only when explicit:

```bash
python3 scripts/env-sync.py --generate-contract --publish
```

Useful options:

```bash
python3 scripts/env-sync.py \
  --generate-contract \
  --output .env.sync.generated.yml \
  --report-output docs/env-sync-contract-report.md \
  --strict-post-checks
```

Option notes:

- `--output`: output contract path (default `.env.sync.generated.yml`)
- `--publish`: copy generated output to `.env.sync.yml`
- `--report-output`: report path (default `docs/env-sync-contract-report.md`)
- `--no-report`: disable report file generation
- `--strict-post-checks`: fail when discovered real environment files (`config/<environment>.env`) have pending differences/review items
- In strict failure, terminal output lists offending keys (`missing`, `review_required`, `extra`, `ambiguous`) for faster remediation.
- `--reconcile-interactive`: interactive conflict resolution during `--mode apply`
- `--extra-action comment|remove`: how to handle keys existing only in target during interactive reconcile

If `.env.sync.yml` was removed locally by mistake and you want the Git-tracked version:

```bash
git restore .env.sync.yml
```

## Mandatory workflow after changing `config/.env.example`

Whenever you add, remove, or change any key in `config/.env.example`, run this flow:

1. Regenerate contract and run strict checks for discovered environment files:

```bash
python3 scripts/env-sync.py \
  --generate-contract \
  --output .env.sync.generated.yml \
  --report-output docs/env-sync-contract-report.md \
  --strict-post-checks
```

2. Review the report:
   - missing required keys in each environment file;
   - `review_required` divergences that require operational decision;
   - extra keys not present in template.

3. For each environment, run explicit sync report/apply until clean:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.generated.yml \
  --mode report
```

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.generated.yml \
  --mode apply \
  --allow-managed
```

Notes:

- `add_missing` is enabled by default in generated contract.
- Extra keys are reported for cleanup; they are not auto-removed by default (`remove_extra: false`).
- Template self-check still appears in report, but strict blocking is evaluated against discovered real environment files.

## Environment file sync (env-sync)

Use `scripts/env-sync.py` to compare the kit baseline template (`config/.env.example`) against an environment file (`config/<environment>.env`) using policy rules from `.env.sync.yml`.

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode report
```

Apply contract corrections to the environment:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode apply
```

Interactive reconcile (recommended after template changes):

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.generated.yml \
  --mode apply \
  --reconcile-interactive \
  --extra-action comment
```

Behavior in interactive reconcile:

- Missing keys from source are added to target.
- For each divergent key, the script asks whether to keep source or target value.
- Keys that exist only in target are commented (or removed with `--extra-action remove`).

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
- `apply` adds missing keys, fills empty required keys, and removes real extras absent from the contract.
- `apply` creates backup before any write (`.env-backups/` by default).
- Values already active in the environment take precedence over `.env.example` and appear under `KEPT TARGET VALUES`.
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

## Post-deploy email with Mailpit

Use this after the GLPI environment is installed and validated. The UI access follows the environment `TLS_MODE`, `WEB_HTTP_PORT`, `WEB_HTTPS_PORT`, and `GLPI_DOMAIN`.

```bash
./scripts/glpictl.sh <env> email check mailpit
./scripts/glpictl.sh <env> email prepare mailpit
./scripts/glpictl.sh <env> email install mailpit
./scripts/glpictl.sh <env> email post-check mailpit
./scripts/glpictl.sh <env> email rollback mailpit
```

Operational notes:

- `EMAIL_MAILPIT_ENABLED=true` must be active in `config/<env>.env` before `prepare` and `install`.
- `prepare` prompts for UI and SMTP credentials and writes only protected files under `.runtime/<env>/email`.
- `install` requires Docker and Docker Compose to already be available; the kit validates and blocks on port conflicts.
- GLPI SMTP is not configured automatically; the final summary prints host, port, and STARTTLS details.

## SSO operation note

SSO/SAML/OIDC setup is performed manually in GLPI and IdP. There is no `auth` domain in the current CLI contract.

## Unified GLPI backup and restore (app|db|all)

```bash
sudo ./scripts/backup-app.sh backup --target all --encrypt
sudo ./scripts/backup-app.sh backup --target app --exclude-app "var/_cache,var/_sessions"
sudo ./scripts/backup-app.sh backup --target db --exclude-db-tables-data "glpi_logs,glpi_sessions"
sudo ./scripts/backup-app.sh backup --target db --db-host 10.0.0.10 --db-port 3306 --db-user nehemiah --db-name glpi --db-password '<password>'
sudo ./scripts/backup-app.sh backup --target all --encrypt --passphrase-file /root/.secrets/glpi-backup-passphrase.txt

sudo ./scripts/backup-app.sh restore --target app --artifact /tmp/glpi-backups/<file>.tar.gz --force
sudo ./scripts/backup-app.sh restore --target db --artifact /tmp/glpi-backups/<file>.tar.gz --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
sudo ./scripts/backup-app.sh restore --target all --artifact /tmp/glpi-backups/<file>.tar.gz --force --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
```

Operational notes:

- If `--db-password` is omitted on DB `backup` or `restore`, the script prompts for the password interactively.
- If `--encrypt` is used without `--passphrase-file`, the script prompts for encryption passphrase at runtime.
- For `.enc` restore, passphrase is also prompted (or read from `--passphrase-file`).

## Manual Ansible fallback

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```
