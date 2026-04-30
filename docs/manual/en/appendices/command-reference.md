# Appendix: Command Reference

## 1. Ubuntu dependency install

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

What it does:

- installs local tools required by scripts and Ansible.

When to use:

- first-time setup on an execution host.

## 2. Mandatory first command (permissions bootstrap)

```bash
bash scripts/bootstrap-permissions.sh
```

What it does:

- sets execute permission on `scripts/*.sh`
- validates `sudo`
- validates membership in `glpiops`
- creates/repairs secure `.runtime` baseline

Expected output:

- `Bootstrap completed.`

## 3. Execution contract variables

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=app
export SECURITY_MODE=secure
```

What each variable means:

- `GLPI_ENVIRONMENT`: environment file selector (`config/<environment>.yml`)
- `GLPI_EXECUTION_MODE`: `local` or `ssh`
- `GLPI_HOST_ROLE`: `app`, `db`, or `all`
- `SECURITY_MODE`: `secure` blocks policy failures, `permissive` records risk and continues

## 4. Dual-server local mode (no cross-host SSH, 2FA-friendly)

DB host:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=db
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

APP host:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=app
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Why this flow:

- avoids direct server-to-server SSH dependency
- supports interactive enterprise login and 2FA per host

## 5. Single-server flow

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=all
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

## 6. Optional remote SSH mode

```bash
export GLPI_EXECUTION_MODE=ssh
export GLPI_HOST_ROLE=all
./scripts/glpictl.sh staging deploy check all
```

When to use:

- only when remote automation is allowed.

Additional requirements:

- key pair per environment
- private key mode `0600`
- target reachability from execution host

## 7. Main deploy commands

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
```

Command intent:

- `check`: prerequisite and policy validation
- `apply db`: database provisioning/hardening
- `apply app`: application/web stack provisioning
- `apply monitoring`: exporter baseline
- `apply backup`: backup baseline
- `post-check`: post-deploy verification

## 8. TLS commands

```bash
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

Intent:

- change TLS mode and reapply app role safely.

## 9. Certification and readiness

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Intent:

- generate certification evidence and readiness reports.

## 10. Day-2 operations

```bash
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit
./scripts/glpictl.sh <env> ops resume
```

Intent:

- user lifecycle, certificate lifecycle, audit checks, and resumable maintenance.

## 11. Manual Ansible fallback

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

When to use:

- only if CLI orchestration is temporarily unavailable.
