# Ansible Standard

## Main structure

- `ansible/inventories/<environment>/hosts.yml`
- `ansible/inventories/<environment>/group_vars/all.yml`
- `ansible/roles/<role>/tasks/main.yml`
- `ansible/roles/<role>/handlers/main.yml`
- `ansible/roles/<role>/templates/*.j2`

## Rules

- Prefer small, focused roles.
- Use `group_vars` for non-sensitive environment values.
- Never version secrets in inventories or vars.
- Use templates for variable configurations.
- Validate syntax before considering a block ready for commit.

## Minimum validation

- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`

## Secrets

- Secrets must enter at runtime through a guided script.
- The script may generate a local temporary file outside Git.
- The playbook must fail with a clear message when a critical secret is missing.
