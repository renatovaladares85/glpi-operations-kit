# 02 - Environment and Topology

This chapter helps you fill the environment file safely, so deployment commands run on the correct hosts.

Configuration happens in one main file:

- `config/<environment>.env`

Use `config/.env.example` only as your starting template.

Generic example:

```env
GLPI_DOMAIN=<your-domain>
DATABASE_NAME=<db-name>
DATABASE_USER=<db-user>
DATABASE_PASSWORD=<secret>
TLS_MODE=<none|self_signed|provided>
```

Filled fictitious example:

```env
GLPI_DOMAIN=glpi.empresa.example
DATABASE_NAME=glpi
DATABASE_USER=nehemiah_glpi
DATABASE_PASSWORD=change-this-secret
TLS_MODE=provided
```

Choose topology and execution mode carefully:

- `TOPOLOGY_MODE=single-server`: app and db on the same host
- `TOPOLOGY_MODE=dual-server`: app and db on different hosts
- `EXECUTION_MODE=local`: run commands from each target host
- `EXECUTION_MODE=ssh`: centralized remote execution (policy dependent)

Before running deployment checks, synchronize your environment file against the current baseline template using `env-sync.py`.
If `.env.sync.yml` is missing, first follow `Generate or recover .env.sync.yml` in [Command Reference](../appendices/command-reference.md).

Start with report mode (no file changes):

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.yml \
  --mode report
```

If the report confirms only allowed managed updates, apply those changes:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.yml \
  --mode apply \
  --allow-managed
```

Generate a file report when you need evidence or review history:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.yml \
  --mode report \
  --write-report .runtime/reports/env-sync-staging.txt
```

How to interpret result quickly:

- exit `0`: sync/check completed without actionable differences;
- exit `2`: differences found in report mode (review before apply);
- exit `3`: at least one key requires manual review (`review_required`);
- exit `4`: permission or backup issue while trying to apply.

Validate after edits:

```bash
./scripts/glpictl.sh staging deploy check all
```

Common error and quick action:

- error: wrong host role in dual-server local flow
- action: use DB role on DB host, APP role on APP host
- error: `ModuleNotFoundError: No module named 'yaml'` while running `env-sync.py`
- action: install local dependency with `sudo apt-get install -y python3-yaml` and rerun

Go next:

- [03 - Deploy on Linux](03-deploy-linux-traditional.md)
- [Environment Configuration Field Guide](../appendices/configuration-field-guide.md)
- [Runtime Inputs and Files](../appendices/runtime-input-reference.md)
