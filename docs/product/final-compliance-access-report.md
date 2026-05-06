# Final Compliance and Access Report - GLPI Install Baseline (Linux)

This report uses the GLPI install documentation baseline (`glpi-install-readthedocs-io-en-latest.pdf`) as the normative reference for Linux deployment behavior.

Scope:
- Linux engines: `nginx`, `apache`, `lighttpd`
- GLPI 11 baseline
- `public` web root model
- install flow, assets, routing, and hardening checks

## Canonical compliance matrix

| Requirement | Current Implementation | Gap | Fix | Severity | Evidence |
|---|---|---|---|---|---|
| Web root must be `.../public` | All engine templates set document root to `{{ glpi_install_dir }}/public` | None | Keep enforced in templates and post-check | Critical | `ansible/roles/app/templates/*-glpi.conf.j2` |
| Linux engines accepted by this project: `nginx`, `apache`, `lighttpd` | Renderer and app role validate only these values | None | Keep one-engine validation in precheck and apply | High | `scripts/lib/render_product_config.py`, `ansible/roles/app/tasks/main.yml` |
| One host must not be configured with multiple active web engines in the same run | `single-web-server` policy validates active services vs `WEB_SERVER_TYPE` | None | Keep secure/permissive behavior with evidence trail | High | `scripts/glpictl.sh` policy checks and post-check summary |
| Rewrite/router model must send non-file requests to `index.php` | Nginx `try_files ... /index.php`; Apache rewrite; lighttpd `url.rewrite-if-not-file` | None | Keep as canonical templates | Critical | web templates under `ansible/roles/app/templates/` |
| Installer compatibility route `/install/install.php` must resolve when installer is expected | Nginx compatibility route rewrite added; runtime checks validate installer route status | None | Keep route check in app apply/post-check | Critical | `nginx-glpi.conf.j2`, app tasks (`glpi_install_route_check`) |
| JS/CSS assets required by install page must be accessible | App role extracts representative assets from root content and validates HTTP response | Partial sample only (top 3 assets) | Keep current check and optionally increase sample size for strict QA | Medium | app tasks (`glpi_asset_paths`, `Check representative static assets`) |
| Sensitive paths (`config`, `files`, `vendor`) must remain blocked | App role validates blocked responses (`403/404`) | None | Keep blocked-path checks in apply/post-check | Critical | app tasks (`Ensure sensitive paths stay blocked`) |
| Direct arbitrary PHP execution outside approved routes must be blocked | Nginx denies generic `\.php`; app role checks `/should-not-exist.php` blocked | None | Keep allowlist + deny default pattern | Critical | `nginx-glpi.conf.j2`, app tasks (`Ensure arbitrary PHP outside router is blocked`) |
| GLPI 11 requires PHP `bcmath` | Precheck auto-fix support for `php-bcmath`; app role asserts extension availability | None | Keep extension check in precheck and app validation | High | `scripts/lib/common.sh`, app tasks (`Assert PHP bcmath extension is available`) |
| APP host must be able to test DB connectivity (`SELECT 1`) | App role runs explicit `mysql --host ... --execute=SELECT 1` using GLPI DB user | None | Keep mandatory APP->DB test in apply/post-check flow | High | app tasks (`Validate APP to DB connectivity using GLPI DB user`) |
| APP host must have MariaDB client for diagnostics/connectivity checks | Precheck validates/installs `mariadb-client` when app stack is expected in local mode | None | Keep mandatory app-host check | High | `scripts/lib/common.sh` (`mariadb-client-on-app-host`) |
| Mandatory PHP baseline for GLPI 11 (`dom`, `fileinfo`, `filter`, `libxml`, `simplexml`, `tokenizer`, `xmlreader`, `xmlwriter`, `curl`, `gd`, `intl`, `mysqli`, `session`, `zlib`, `mbstring`, `openssl`, `bcmath`) | App validation asserts full mandatory extension list and fails with exact missing modules | None | Keep full extension assertion and package baseline | High | app tasks (`Assert mandatory PHP extensions are available`) |
| DB engine compatibility baseline (MariaDB) | DB role provisions MariaDB and validates service/startup paths | None for MariaDB scope | Keep MariaDB as supported baseline in this kit | Medium | `ansible/roles/db/*`, deploy DB flow |

## Per-engine Linux verdict

| Engine | Verdict | Notes |
|---|---|---|
| nginx | Compliant with compatibility hardening | Includes installer compatibility route and explicit PHP allowlist/deny policy. |
| apache | Compliant in baseline routing model | Uses `public` root and rewrite-to-index policy per GLPI model. |
| lighttpd | Compliant in baseline routing model | Uses `public` root with rewrite-if-not-file behavior. |

## Install-flow verdict

Status: **Compliant after current fixes**, with objective checks for:
- root route reachability,
- installer compatibility route behavior,
- representative install-page assets,
- sensitive path blocking.

## Security verdict

Status: **Compliant for baseline hardening** under selected engine policy:
- one engine per host,
- no broad PHP execution,
- protected path validation enforced in automated checks.

## Prioritized actions

### Critical
- Keep installer compatibility and blocked-path checks mandatory in every `deploy apply app` and `deploy post-check app` execution.

### High
- Keep `bcmath` and `mariadb-client` checks mandatory for app-local flow in GLPI 11 deployments.
- Keep APP->DB `SELECT 1` test as a required post-configuration validation.

### Medium
- Expand asset validation sample size for stricter customer acceptance gates.

## Runtime evidence locations

Operational evidence is persisted under:
- `.runtime/<environment>/logs/`
- `.runtime/<environment>/state/`
- `.runtime/<environment>/evidence/`

Use these artifacts as the objective acceptance bundle for homologation sign-off before production rollout.
