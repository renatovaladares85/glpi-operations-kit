# Environment Parameters Reference

This is the compact product-level reference for `config/<environment>.env`. The complete operator field guide is maintained in the manual appendices:

- PT-BR: [Guia de Preenchimento do Ambiente](../manual/pt-br/appendices/configuration-field-guide.md)
- EN: [Environment Configuration Field Guide](../manual/en/appendices/configuration-field-guide.md)

## How to create an environment file

```bash
cp config/product.env config/staging.env
```

Edit public values in the environment copy. Real environment copies should not be committed.

Activation rule:

- Commented key: not used in the current scenario.
- Uncommented key: active and used in runtime rendering.
- Conditional key guidance can keep a commented default line as an example for later activation.
- In `config/product.env`, only mandatory baseline keys stay uncommented by default.

## Conditional checks by enabled feature

Validation does not check only global mandatory keys. It also checks required keys for enabled features:

- `EXECUTION_MODE=ssh`: `NETWORK_SSH_USER` and `NETWORK_SSH_PRIVATE_KEY_PATH` must be active and valid.
- `TLS_MODE=provided`: `TLS_PROVIDED_LOCAL_CERT_PATH` and `TLS_PROVIDED_LOCAL_KEY_PATH` must be active and point to real local files.
- `DATABASE_DEPLOYMENT_MODE=managed`: DB host Linux operations are disabled; DB validation uses direct MySQL TCP connectivity.
- External auth enabled (`AUTH_MODE!=local` or `AUTH_*_ENABLED=true`): `SSO_PUBLIC_URL` becomes mandatory when URL enforcement is active.
- SAML/OIDC enabled: `SSO_PUBLIC_URL` must be `https://` and `TLS_MODE` cannot be `none`.
- `SECURITY_REQUIRE_SSO=true`: requires `SECURITY_SSO_ENABLED=true`.

## Secret handling

Deployment secrets currently read from `config/<environment>.env` and materialized into `.runtime/<environment>/secrets.yml` are:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD` (`DATABASE_DEPLOYMENT_MODE=self_hosted`)
- `MONITORING_MYSQLD_EXPORTER_PASSWORD` (`DATABASE_DEPLOYMENT_MODE=self_hosted`)
- `DATABASE_MANAGED_ADMIN_PASSWORD` (optional, used as managed-mode fallback credential for `root`/`admin` connectivity checks)

External-auth secrets are runtime-only and must stay in `.runtime/<environment>/secrets.yml`:

- `auth_saml_x509_certificate`
- `ldap_bind_password`
- `oidc_client_secret`

Never commit `.runtime/`, private keys, tokens, real passwords, or customer-sensitive evidence.

## Parameter groups

| Group | Purpose | Detailed guide |
|---|---|---|
| `PRODUCT_*`, `CUSTOMER_*`, `ENVIRONMENT_*` | Product, customer, and environment identity. | Manual field guide. |
| `EXECUTION_*`, `TOPOLOGY_*` | Local/SSH execution and single/dual-server topology. | Manual field guide. |
| `NETWORK_*` | SSH identity and DB source allowlist. | Manual field guide. |
| `GLPI_*`, `PHP_FPM_*`, `WEB_*` | GLPI version, web engine, PHP runtime, ports, app packages. | Manual field guide. |
| `DATABASE_*` | MariaDB/MySQL schema, users, bind, port, packages. | Manual field guide. |
| `TLS_*` | TLS mode, certificate target paths, provided source files. | Manual field guide and TLS appendix. |
| `BACKUP_*` | Backup base directory and retention. | Manual field guide. |
| `MONITORING_*`, `ALERTING_*` | Exporters, labels, thresholds, scrape profiles, alert routes. | Manual field guide. |
| `AUTH_*`, `SSO_*` | Optional local/LDAP/SAML/OIDC preparation and SSO evidence. | Manual field guide and auth/SSO appendix. |
| `SECURITY_*` | Secure/permissive policy gates. | Manual field guide. |
| `PATH_*` | Secure GLPI filesystem layout outside webroot. | Manual field guide. |
| `OPERATIONS_*` | Timezone, cron, operator group, default security mode. | Manual field guide. |
| `RESOURCE_PROFILE_*` | PHP-FPM and MariaDB tuning profiles for `small`, `medium`, `large`. | Manual field guide. |

## High-risk decisions

| Decision | Recommended default | Why it matters |
|---|---|---|
| `EXECUTION_MODE` | `local` unless remote SSH orchestration is approved. | Prevents implicit cross-host assumptions. |
| `TOPOLOGY_MODE` | Match the real host layout. | Wrong topology can apply DB/app actions to the wrong host. |
| `DATABASE_DEPLOYMENT_MODE` | `self_hosted` for VM-managed DB, `managed` for AWS RDS/external DB. | Controls whether scripts expect Linux DB host operations or direct DB TCP validation. |
| `WEB_SERVER_TYPE` | One of `nginx`, `apache`, `lighttpd`. | The Linux kit automates these engines only. |
| `TLS_MODE` | `provided` for production. | SSO and compliance usually require HTTPS. |
| `AUTH_MODE` | `local` unless external auth is explicitly approved. | Preserves existing login behavior. |
| `SECURITY_REQUIRE_ORDERED_EXECUTION` | `true`. | Protects deployment order and rollback reasoning. |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | `secure`. | Prevents silent risk acceptance. |
| `RESOURCE_PROFILE_ACTIVE` | `small` until sized by real workload. | Avoids overcommitting small hosts. |

## DB access mode examples

Restricted mode example:

```env
NETWORK_DATABASE_ACCESS_MODE=restricted
NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=192.0.2.10,192.0.2.11
```

Open mode example:

```env
NETWORK_DATABASE_ACCESS_MODE=open
NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=
#NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=192.0.2.10,192.0.2.11
```

In open mode, `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` stays active and empty.

## Runtime rendering

`config/<environment>.env` is rendered into:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/secrets.yml`

Mutable overrides are stored separately in `.runtime/<environment>/overrides.runtime.yml`. Effective runtime precedence is:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`
