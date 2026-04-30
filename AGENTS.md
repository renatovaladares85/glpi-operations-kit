# AGENTS.md

This file is the primary entry point for any AI agent working in this repository.

## 1. Required reading order

Before proposing, analyzing, or executing any change, read in this order:

1. `README.md`
2. `AGENTS.md`
3. `docs/standards/index.md`
4. Only the relevant thematic files inside `docs/standards/`

## 2. Project objective

- Standardize, automate, and operate a reusable GLPI deployment product kit.
- Preserve strict separation between `staging` and `production`.
- Work with low context cost, low token waste, and minimal repetition.
- Keep rules clear for rollback, auditability, and recovery.

## 3. Primary stack

- `Ubuntu`
- `Ansible`
- `Nginx`
- `PHP-FPM`
- `MariaDB`
- operational scripts in `bash`

## 4. Where to find each standard

- Commits, checkpoints, and rollback: [commit-convention.md](docs/standards/commit-convention.md)
- Infrastructure inventories, roles, templates, and secrets: [ansible.md](docs/standards/ansible.md)
- Guided `bash` scripts, prompts, and runtime secrets: [bash-scripts.md](docs/standards/bash-scripts.md)
- Security, permissions, TLS, LGPD, and sensitive data: [security.md](docs/standards/security.md)
- Monitoring, exporters, alerts, and thresholds: [monitoring.md](docs/standards/monitoring.md)
- Backup, restore, retention, and tests: [backup-restore.md](docs/standards/backup-restore.md)
- Approved repetitive commands: [repetitive-commands.md](docs/standards/repetitive-commands.md)
- Learned errors and prevention rules: [learned-lessons.md](docs/standards/learned-lessons.md)
- Non-negotiable rules: [mandatory-rules.md](docs/standards/mandatory-rules.md)

## 5. When to consult `docs/standards`

- Always consult only the minimum required for the current task.
- Do not reread every standards file if the task touches only one area.
- If a standard already exists, reuse it instead of rewriting it elsewhere.
- If a rule is ambiguous, update the correct thematic file instead of duplicating it in `AGENTS.md`.

## 6. Commit rules

- The official standard is `Conventional Commits`.
- Commits must happen only when a `validated functional block` is complete.
- Do not mix changes with different goals, risks, or technologies in one commit.
- If a block is not isolated or validated, keep it in the working tree and do not commit yet.
- Always use descriptive commit messages with `type(scope): description`.

## 7. How to record new learnings

- If an error repeats or causes rework, record it in `learned-lessons.md`.
- If a command is repeated in a safe and useful way, record it in `repetitive-commands.md`.
- If a rule becomes mandatory to avoid risk or waste, promote it to `mandatory-rules.md`.
- Do not rely on agent memory as the source of truth; document it in the repository.

## 8. Mandatory operating rules

- Prefer modifying existing files before creating new ones.
- Run an environment pre-flight check before starting any implementation.
- Classify pre-flight results as `mandatory` or `optional`.
- Attempt safe, low-risk environment updates only when they are clearly supported by the current workflow.
- If a mandatory pre-flight item cannot be fixed, stop and do not continue unless the user explicitly authorizes continuation.
- Never version secrets.
- Keep public environment values in `config/<environment>.env`.
- Sensitive values must be requested at runtime when applicable.
- When generating or suggesting usernames, service accounts, aliases, host labels, or similar identifiers, prefer biblical-context naming.
- Never use common, obvious, or easily guessable usernames, passwords, or identifiers.
- Biblical context may guide naming, but secrets must still use high entropy and must never be simple biblical words or predictable patterns.
- Keep sensitive directories outside the web root.
- Do not rewrite documentation that is already consolidated in another thematic markdown file.
- Always minimize token usage, calls, and unnecessary file reads.
- When you identify a repetitive command, promote it to a documented standard.
- When you identify a recurring error, document the cause, fix, and prevention rule.

## 9. Minimum validation expectations

When applicable, validate as much as possible before considering a block ready for commit:

- environment pre-flight checks
- `ansible-inventory --list`
- `ansible-playbook --syntax-check ansible/site.yml`
- `nginx -t`
- `php-fpm8.3 -t`
- connectivity tests
- smoke tests

## 10. Main references

- Project overview: [README.md](README.md)
- Live implementation plan: [implementation-plan.md](docs/implementation-plan.md)
- Prerequisites matrix: [prerequisites-matrix.md](docs/product/prerequisites-matrix.md)
- Environment parameters: [environment-parameters.md](docs/product/environment-parameters.md)
- Standards catalog: [docs/standards/index.md](docs/standards/index.md)
