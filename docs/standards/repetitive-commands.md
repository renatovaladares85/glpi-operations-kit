# Repetitive Commands

Record recurring commands here when they are safe, reusable, and reduce context cost.

## Format

### Objective

### Command

### When to use

### Preconditions

### Risks

## Initial commands

### Objective

Apply mandatory local permission bootstrap before any deployment.

### Command

```bash
bash scripts/bootstrap-permissions.sh
```

### When to use

At the beginning of each operator setup and before first deploy on a new machine/session.

### Preconditions

- Ubuntu/Linux host
- sudo privileges

### Risks

- low risk; changes local file modes/group membership requirements

### Objective

Run day-2 operational audit checks.

### Command

```bash
bash scripts/ops-maintenance.sh audit staging check
```

### When to use

After post-implementation changes (users, certs, permissions) and before closing the local operational cycle.

### Preconditions

- runtime inventory and bootstrap marker available

### Risks

- low risk; validation-oriented operation

### Objective

Resume interrupted day-2 operations from latest checkpoint.

### Command

```bash
bash scripts/ops-maintenance.sh resume staging
```

### When to use

After a failed maintenance run with checkpoint state available.

### Preconditions

- `.runtime/staging/state/*.state.yml` exists

### Risks

- medium; resumes prior workflow so must confirm previous failure context

### Objective

Run the mandatory pre-flight check before implementation.

### Command

```bash
./scripts/glpictl.sh staging deploy check all
```

### When to use

Before any staging implementation or validation session.

### Preconditions

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`

### Risks

- low risk; read-only

### Objective

Run the release readiness gate and generate audit-ready reports.

### Command

```bash
bash scripts/release-readiness.sh staging
```

### When to use

Before declaring staging complete and before requesting production approval.

### Preconditions

- bootstrap completed
- runtime config rendered
- runtime secrets present

### Risks

- low risk; validation-only but fails hard on unresolved critical gaps

### Objective

Generate an environment-specific SSH key pair for remote deployment.

### Command

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_staging_ed25519 -C "glpi-staging-ops"
chmod 600 ~/.ssh/glpi_staging_ed25519
chmod 644 ~/.ssh/glpi_staging_ed25519.pub
```

### When to use

Before first remote deployment to staging.

### Preconditions

- `openssh-client` installed

### Risks

- low risk; key overwrite risk if the same path is reused without backup

### Objective

Validate the Ansible inventory structure.

### Command

```bash
ansible-inventory --list -i .runtime/<env>/inventory.runtime.yml
```

### When to use

Before running playbooks or after changing environment runtime configuration.

### Preconditions

- `ansible` installed

### Risks

- low risk; read-only

### Objective

Validate the main playbook syntax.

### Command

```bash
ansible-playbook --syntax-check -i .runtime/<env>/inventory.runtime.yml ansible/site.yml
```

### When to use

Before committing Ansible changes.

### Preconditions

- `ansible` installed

### Risks

- low risk; does not change remote state

### Objective

Create a full GLPI transfer backup (app + DB) in a single artifact for migration or clone.

### Command

```bash
sudo ./scripts/backup-app.sh backup --target all --encrypt
```

### When to use

Before migration, clone, or full environment copy where application files and database must be restored together.

### Preconditions

- Linux host with root privileges
- `tar`, `gzip`, `mysqldump`, and `openssl` available
- DB access credentials discoverable from `config_db.php` or passed explicitly

### Risks

- high data exposure impact if artifact/passphrase handling is weak
- backup can become partial if exclusions are used intentionally
