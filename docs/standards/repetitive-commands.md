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

After post-implementation changes (users, certs, permissions) and before closing maintenance windows.

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

Validate the Ansible inventory structure.

### Command

```bash
ansible-inventory --list -i ansible/inventories/staging/hosts.yml
```

### When to use

Before running playbooks or after changing inventories.

### Preconditions

- `ansible` installed

### Risks

- low risk; read-only

### Objective

Validate the main playbook syntax.

### Command

```bash
ansible-playbook --syntax-check ansible/site.yml
```

### When to use

Before committing Ansible changes.

### Preconditions

- `ansible` installed

### Risks

- low risk; does not change remote state
