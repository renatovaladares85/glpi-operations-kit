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

Run the mandatory pre-flight check before implementation.

### Command

```bash
./scripts/deploy-staging.sh check
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
