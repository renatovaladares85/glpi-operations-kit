# Ansible Standard

## Main structure

- `config/<environment>.env`
- `ansible/inventories/<environment>/hosts.yml`
- `ansible/inventories/<environment>/group_vars/all.yml`
- `ansible/roles/<role>/tasks/main.yml`
- `ansible/roles/<role>/handlers/main.yml`
- `ansible/roles/<role>/templates/*.j2`

## Rules

- Prefer small, focused roles.
- Use `config/<environment>.env` as the primary public configuration source.
- Keep `group_vars` generic and safe as fallback defaults only.
- Never version secrets in inventories or vars.
- Use templates for variable configurations.
- Validate syntax before considering a block ready for commit.

## Minimum validation

- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`

## Secrets

- Secrets must enter at runtime through a guided script.
- Secrets must be stored only under `.runtime/<environment>/secrets.yml`.
- The rendered public runtime file must be generated from `config/<environment>.env`.
- Mutable runtime overrides must be stored in `.runtime/<environment>/overrides.runtime.yml`.
- Extra vars precedence must follow `public.runtime.yml -> overrides.runtime.yml -> secrets.yml`.
- The playbook must fail with a clear message when a critical secret is missing.
