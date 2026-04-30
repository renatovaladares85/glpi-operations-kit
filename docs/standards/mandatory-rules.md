# Mandatory Rules

These rules must not be broken by agents.

## Mandatory rules

- Read `README.md`, `AGENTS.md`, and `docs/standards/index.md` before acting.
- Consult only the thematic files required for the current task.
- Run environment pre-flight checks before starting implementation.
- Run `bash scripts/bootstrap-permissions.sh` before any deploy script in a fresh operator session.
- Run `bash scripts/release-readiness.sh <environment>` before declaring an environment complete.
- Keep public environment values in `config/<environment>.yml`.
- Keep mutable runtime overrides in `.runtime/<environment>/overrides.runtime.yml`.
- Keep secrets only in `.runtime/<environment>/secrets.yml`.
- Maintain one SSH key pair per environment for remote execution contexts.
- Keep SSH private keys at mode `0600`.
- Classify each pre-flight result as `mandatory` or `optional`.
- Stop when a mandatory pre-flight item fails and cannot be fixed.
- Continue after a mandatory pre-flight failure only with explicit user approval.
- Enforce operator membership in `glpiops` for deployment operations.
- Apply security policy checks in every environment using `SECURITY_MODE=secure|permissive`.
- In `secure`, policy violations block execution.
- In `permissive`, policy violations become warnings and must be persisted as evidence with justification.
- Use `scripts/ops-maintenance.sh` for post-implementation user and certificate lifecycle tasks.
- Persist day-2 operation logs and checkpoints under `.runtime/<env>/logs` and `.runtime/<env>/state`.
- Never version secrets.
- Never use common or easily guessable usernames, passwords, or identifiers.
- Use biblical-context naming for generated or suggested identifiers when applicable.
- Never use plain biblical words or predictable biblical patterns as secrets.
- Do not duplicate rules already documented in another thematic markdown file.
- Create commits only when a validated functional block is complete.
- Use `Conventional Commits`.
- Record recurring errors in `learned-lessons.md`.
- Record safe repetitive commands in `repetitive-commands.md`.
- Promote critical rules to this file when they prevent repetition, security risk, or waste.
- Minimize token usage, calls, and unnecessary file reads.
