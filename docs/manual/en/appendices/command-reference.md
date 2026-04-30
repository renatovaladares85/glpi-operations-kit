# Appendix: Command Reference

## 1. Dependency installation (Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client python3 python3-yaml ansible
```

Purpose:

- installs required local dependencies for script execution and Ansible deployment.

When to use:

- first-time setup of an execution host.

## 2. Mandatory first command

```bash
bash scripts/bootstrap-permissions.sh
```

Purpose:

- enforces script execute bits, validates `sudo`, validates `glpiops` membership, and prepares secure `.runtime` structure.

Expected result:

- `Bootstrap completed.`

## 3. SSH key pair per environment (mandatory for remote execution)

Generate staging key pair:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_staging_ed25519 -C "glpi-staging-ops"
chmod 600 ~/.ssh/glpi_staging_ed25519
chmod 644 ~/.ssh/glpi_staging_ed25519.pub
```

Generate production key pair:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_production_ed25519 -C "glpi-production-ops"
chmod 600 ~/.ssh/glpi_production_ed25519
chmod 644 ~/.ssh/glpi_production_ed25519.pub
```

Install key on target hosts:

```bash
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@APP_HOST
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@DB_HOST
```

Validate connectivity:

```bash
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@APP_HOST "echo ok"
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@DB_HOST "echo ok"
```

## 4. Core deployment sequence

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Purpose:

- executes the recommended ordered flow.
- if `security.require_ordered_execution=true`:
  - `SECURITY_MODE=secure` blocks out-of-order runs;
  - `SECURITY_MODE=permissive` allows continuation with warning + evidence.

## 5. Certification and readiness

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Purpose:

- certifies staging and generates audit evidence and promotion gate artifacts.

## 6. Mutable commands with selectable security mode

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

Secure mode example:

```bash
SECURITY_MODE=secure ./scripts/glpictl.sh production deploy apply app
```

Permissive mode example:

```bash
SECURITY_MODE=permissive SECURITY_JUSTIFICATION="Temporary controlled test approved by CAB-0426" ./scripts/glpictl.sh production deploy apply app
```

Policy behavior:

- `secure`: policy violations block.
- `permissive`: policy violations warn and are written to `.runtime/<env>/state/security-mode-last.yml` and `.runtime/<env>/evidence/security-mode-*.yml`.

## 7. TLS operations

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

Purpose:

- controls TLS mode transitions and re-applies app role safely.

## 8. Day-2 operations

```bash
./scripts/glpictl.sh staging ops users add os
./scripts/glpictl.sh staging ops users disable db
./scripts/glpictl.sh staging ops cert check
./scripts/glpictl.sh staging ops cert renew
./scripts/glpictl.sh staging ops audit
./scripts/glpictl.sh staging ops resume
```

Purpose:

- manages maintenance lifecycle actions with checkpoints and execution logs.

## 9. Manual Ansible fallback

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

Use when:

- direct CLI flow is unavailable and controlled fallback is needed.
