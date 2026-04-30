# GLPI Operations Kit - Operator Runbook (EN)

This manual is for Linux operators, DevOps engineers, and auditors who need to deploy and operate GLPI with repeatable controls. You do not need to read the full codebase before starting. If you follow this runbook in order, the scripts will generate runtime files, validate prerequisites, and show explicit remediation when something is missing.

You can edit files from a Windows workstation, but all operational commands in this runbook must be executed from a Linux shell on the target servers.

The expected skill level is practical Ubuntu administration with `sudo`, basic shell usage, and familiarity with Ansible command execution. If your company requires interactive login, password, and 2FA on each host, the runbook already supports that through local host execution.

## Start here

Your first action is always to prepare configuration, then bootstrap permissions. Copy the product template and create the environment file you want to use:

```bash
cp config/product.env config/staging.env
```

Open `config/staging.env`, adjust the values for your environment, and keep secrets out of this file. Passwords and other sensitive data are stored only in `.runtime/<environment>/secrets.yml`, which is generated and maintained at runtime.

After editing the environment file, run:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
```

You do not need to run manual `export` commands for execution variables in normal use. `glpictl` automatically loads `config/<environment>.env`, then applies this precedence:

1. CLI arguments (for example `staging deploy apply db`)
2. already-set process variables (optional one-off overrides)
3. `config/<environment>.env`
4. internal defaults

## How execution works

The canonical command is:

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

`domain` maps to major operational areas (`deploy`, `tls`, `ops`, `audit`, `certify`, `promote`). `action` and `target` define exactly what will change. The same command format is used for every environment; what changes is only the `<environment>.env` content and runtime secrets.

When the scripts detect missing mandatory tooling such as `ansible-playbook` or `ansible-inventory`, they offer guided installation on Ubuntu. If auto-install fails or is denied, execution stops with a direct remediation command so you can continue from the same point after fixing the host.

## Single-server and dual-server execution

In a single-server setup, set `TOPOLOGY_MODE=single-server` and keep `EXECUTION_HOST_ROLE_DEFAULT=all` in the environment file. Then run the deploy stages in order on that same host.

In a dual-server setup, `TOPOLOGY_MODE=dual-server` is the recommended model. If your company blocks direct SSH between servers, keep `EXECUTION_MODE=local`. In that mode, each host is configured locally after interactive login with your company access policy (including 2FA when required):

1. On DB host: run `deploy check all`, then `deploy apply db`.
2. On APP host: run `deploy check all`, then `deploy apply app`, `deploy apply monitoring`, `deploy apply backup`, and `deploy post-check all`.

If remote automation is allowed, set `EXECUTION_MODE=ssh`, provide `NETWORK_SSH_USER` and `NETWORK_SSH_PRIVATE_KEY_PATH`, and keep private key mode as `0600`.

## Required execution order

The safe order is:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

When `SECURITY_REQUIRE_ORDERED_EXECUTION=true` and effective `SECURITY_MODE=secure`, out-of-order mutable calls are blocked. In `permissive` mode, policy violations are downgraded to warnings and persisted as explicit risk evidence with operator justification.

## What the key commands actually do

| Command | Where to run | Operational purpose |
|---|---|---|
| `./scripts/glpictl.sh staging deploy check all` | current host | Runs precheck, verifies permissions, validates config loading, materializes runtime files, validates inventory rendering, and confirms policy contract before any mutable change. |
| `./scripts/glpictl.sh staging deploy apply db` | DB host in local dual-server, or orchestrator host in ssh mode | Installs and hardens MariaDB packages, applies DB runtime parameters, provisions GLPI database/user/grants, and enforces DB-side access constraints for app origin. |
| `./scripts/glpictl.sh staging deploy apply app` | APP host in local dual-server, or orchestrator host in ssh mode | Installs app packages, deploys GLPI layout outside web root, configures Nginx + PHP-FPM, applies TLS mode template, and configures app connectivity to database. |
| `./scripts/glpictl.sh staging deploy apply monitoring` | APP host (and DB host according to role scope) | Installs and configures monitoring exporters and baseline observability settings from runtime values. |
| `./scripts/glpictl.sh staging deploy apply backup` | APP host (and DB host according to role scope) | Applies backup baseline, retention policy settings, and backup runtime artifacts used for operational checks. |
| `./scripts/glpictl.sh staging deploy post-check all` | current host | Runs post-deploy validations, service-level checks, and policy-related checks after mutable stages complete. |
| `./scripts/glpictl.sh staging tls self-signed` | APP host | Switches TLS mode to self-signed, updates runtime override, applies app role path, validates Nginx config, and reloads service safely. |
| `./scripts/glpictl.sh staging tls install-provided` | APP host | Validates provided cert/key paths, updates runtime override and target cert paths, reapplies app path, and reloads only after config validation. |
| `./scripts/glpictl.sh staging ops cert check` | APP host | Reads active certificate details and warns when expiration is near the configured threshold. |
| `./scripts/glpictl.sh staging audit check` | host where operational audit is performed | Consolidates permission, policy, runtime, and operational checks for day-2 verification. |
| `bash scripts/release-readiness.sh staging` | execution host with repo access | Generates readiness evidence artifacts and fails only on critical technical readiness issues. |

## TLS and security mode decisions

TLS operation has three intentional paths: `none`, `self_signed`, and `provided`. You can start with `none` in controlled development or homologation, move to `self_signed` for encrypted internal tests, and then switch to `provided` when valid certificates are available. The switch is script-driven and does not require manual Nginx template editing.

Security policy is selected per execution. `SECURITY_MODE=secure` enforces policy flags as blocking checks. `SECURITY_MODE=permissive` allows continuation with warnings, but always records who accepted the risk, when, and which policies were violated.

## Runtime files and their meaning

After `deploy check`, runtime files appear under `.runtime/<environment>/`. `public.runtime.yml` is the rendered non-sensitive baseline derived from `config/<environment>.env`. `overrides.runtime.yml` stores mutable operational overrides, such as runtime TLS transitions, without changing your baseline config. `secrets.yml` stores sensitive values collected at runtime and must stay restricted. `inventory.runtime.yml` is the effective inventory contract consumed by Ansible for local or ssh execution. `state/` and `evidence/` hold checkpoints and audit outputs used for certification, troubleshooting, and investigations.

For a command-by-command reference, use [Command Reference](appendices/command-reference.md). For field-level configuration details, use [Environment Parameters](../../product/environment-parameters.md) and [Configuration Reference](../../product/configuration-reference.md).

## Validation and troubleshooting path

The minimum operational validation after deployment is: GLPI page reachable, DB connectivity working, `nginx -t` passing, PHP-FPM config test passing, and runtime evidence files generated. If anything fails, runbook-safe remediation is documented in [Troubleshooting Matrix](appendices/troubleshooting-matrix.md), including missing dependencies, wrong host role, missing SSH material in ssh mode, invalid TLS paths, and policy-mode behavior.

## Related appendices

- [Command Reference](appendices/command-reference.md)
- [Runtime Input and Runtime Files](appendices/runtime-input-reference.md)
- [TLS Modes](appendices/tls-modes.md)
- [Operational Checks](appendices/operational-checks.md)
- [Troubleshooting Matrix](appendices/troubleshooting-matrix.md)
