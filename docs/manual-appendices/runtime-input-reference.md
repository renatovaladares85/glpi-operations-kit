# Appendix: Product Configuration and Runtime Secrets

## Overview

The product now uses:

- public configuration in `config/<environment>.yml`
- runtime secrets in `.runtime/<environment>/secrets.yml`

Generated runtime files:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/overrides.runtime.yml`

Merge precedence:

- `public.runtime.yml -> overrides.runtime.yml -> secrets.yml`

## What belongs in public config

Examples:

- customer display name
- app/db hostnames or IPs
- SSH username and key path
- GLPI version
- domain
- TLS mode
- database name and username
- monitoring exporter username
- backup and monitoring defaults
- tuning profile selection

## What belongs in runtime secrets

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

## Manual no-script path

If scripts cannot be used, create:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/overrides.runtime.yml`
- `.runtime/<environment>/secrets.yml`

The recommended source for manual public values is still `config/<environment>.yml`.
