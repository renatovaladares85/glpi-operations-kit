# GLPI Operations Kit

Private infrastructure-as-code product for deploying and operating GLPI in reusable corporate environments.

## What this product is

- a reusable GLPI deployment kit
- based on `Ubuntu`, `Ansible`, `Nginx`, `PHP-FPM`, and `MariaDB`
- designed for `staging` and `production`
- adaptable to different customers through one public configuration file per environment

## Product configuration model

Primary public configuration:

- `config/staging.yml`
- `config/production.yml`
- `config/product.example.yml`

Runtime secrets:

- `.runtime/<environment>/secrets.yml`

Generated runtime artifacts:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/overrides.runtime.yml`
- `.runtime/<environment>/logs/`
- `.runtime/<environment>/state/`
- `.runtime/<environment>/evidence/`

## Supported topologies

- dual-server
  - one app host
  - one db host
- single-server
  - one host running both roles

## Official CLI

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Examples:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging ops cert check
```

Specific scripts remain available as wrappers over the same central flow.

## Product capabilities

- guided preflight and permission bootstrap
- central public environment configuration
- runtime secret isolation outside Git
- app/db role separation
- backup baseline
- exporter baseline for monitoring
- staging certification with production promotion gate
- selectable policy mode per execution (`SECURITY_MODE=secure|permissive`)
- day-2 operational scripts

## Core directories

- product config: `config/`
- automation: `ansible/`
- operational scripts: `scripts/`
- manuals and product docs: `docs/`

## Documentation

- [Implementation plan](docs/implementation-plan.md)
- [Operator manual](docs/manual/README.md)
- [Configuration reference](docs/product/configuration-reference.md)
- [Prerequisites matrix](docs/product/prerequisites-matrix.md)
- [Environment parameters](docs/product/environment-parameters.md)
- [Monitoring blueprint](docs/product/monitoring-blueprint.md)
- [Product audit](docs/product/product-audit.md)
- [Standards catalog](docs/standards/index.md)
