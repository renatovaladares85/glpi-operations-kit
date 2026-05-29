# 01 - Start and Prechecks

Before you install or change anything, make sure you are in the right place and the environment is ready.

Most failures at deployment time are caused by one of these issues:

- wrong execution host;
- missing environment file;
- missing local prerequisites.

Start by confirming you are on Linux shell and that your environment file already exists.

Where to check:

- `config/.env.example` (template)
- `config/<environment>.env` (your environment)

Run the baseline preparation:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
```

What success looks like:

- no mandatory precheck failure;
- runtime files generated under `.runtime/<environment>/`;
- inventory ready for deployment steps.

Common error and quick action:

- error: `config/<environment>.env` missing
- action: create it from template and run precheck again

```bash
cp config/.env.example config/staging.env
python3 scripts/env-sync.py --source config/.env.example --target config/staging.env --rules .env.sync.yml --mode report
./scripts/glpictl.sh staging deploy check all
```

Go next:

- [02 - Environment and Topology](02-environment-and-topology.md)
- [Command Reference](../appendices/command-reference.md)
- [Prerequisites Matrix](../../../product/prerequisites-matrix.md)
