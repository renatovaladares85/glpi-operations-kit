# 02 - Environment and Topology

This chapter helps you fill the environment file safely, so deployment commands run on the correct hosts.

Configuration happens in one main file:

- `config/<environment>.env`

Use `config/product.env` only as your starting template.

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

Validate after edits:

```bash
./scripts/glpictl.sh staging deploy check all
```

Common error and quick action:

- error: wrong host role in dual-server local flow
- action: use DB role on DB host, APP role on APP host

Go next:

- [03 - Deploy on Linux](03-deploy-linux-traditional.md)
- [Environment Configuration Field Guide](../appendices/configuration-field-guide.md)
- [Runtime Inputs and Files](../appendices/runtime-input-reference.md)
