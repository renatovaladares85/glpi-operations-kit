# Appendix - Command Reference (EN)

This appendix complements the main runbook with direct commands and richer operational intent. The command syntax is always the same; what changes is the environment name and the values in `config/<environment>.env`.

## Prepare host tooling

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

Use this when the execution host is new or missing dependencies. It installs the minimum toolchain required by scripts, runtime rendering, and Ansible execution.

## Prepare script permissions

```bash
bash scripts/bootstrap-permissions.sh
```

Run this before the first deployment command in a new operator session. It fixes executable bits, validates `sudo`, validates `glpiops` membership, and secures `.runtime` baseline permissions.

## Create and edit environment configuration

```bash
cp config/product.env config/staging.env
```

This creates your environment baseline. The scripts read this file automatically, so manual `export` is not required for normal operation.

## Core deployment commands

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
```

`deploy check all` is the operational gate before mutation. It validates tools, permissions, policy flags, inventory rendering, host role consistency, and runtime baseline materialization. `deploy apply db` handles MariaDB packages, hardening, schema, user grants, and DB-access restrictions. `deploy apply app` configures GLPI application layout, Nginx, PHP-FPM, and app-to-DB integration. `deploy apply monitoring` applies exporter baseline and monitoring wiring. `deploy apply backup` applies backup baseline and retention-related settings. `deploy post-check all` confirms service validity after mutable stages.

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

This flow is designed for corporate networks that require interactive login with password and 2FA per host.

## Optional SSH mode

```bash
GLPI_EXECUTION_MODE=ssh ./scripts/glpictl.sh staging deploy check all
```

Use this only when policy allows remote orchestration from one host. In ssh mode, private key policy (`0600`) and target reachability become mandatory checks.

## Web routing and install-flow validation

```bash
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy post-check app
```

These commands now validate the selected web engine routing contract end-to-end: root access, installer compatibility route (`/install/install.php` when installer is expected), representative `.js/.css` assets discovered from the page, and blocked sensitive paths (`/config`, `/files`, `/vendor`, arbitrary `.php` outside router).

## TLS lifecycle commands

```bash
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

`disable` enforces HTTP-only mode, `self-signed` creates and applies local test certificates, `install-provided` installs real cert/key material, and `reload` validates and reloads effective Nginx TLS configuration.

## Certification, readiness, and evidence

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

These commands generate certification and readiness evidence under `.runtime/<env>/evidence` and `.runtime/<env>/state`.

## Day-2 operations

```bash
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit check
./scripts/glpictl.sh <env> ops resume
```

These commands support controlled user lifecycle, certificate lifecycle, operational audits, and resumable maintenance.

## Manual Ansible fallback

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

Use fallback Ansible commands only when central CLI orchestration is temporarily unavailable.
