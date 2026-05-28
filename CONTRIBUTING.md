# Contributing to GLPI Operations Kit

Thank you for contributing. This project is an operational automation kit, so changes must preserve safety, rollback, auditability, and compatibility with existing commands.

## Required reading

Read these documents before proposing or implementing changes:

1. [README](README.md)
2. [AGENTS](AGENTS.md)
3. [Architecture and contribution manual](docs/architecture/README.md)
4. [Standards index](docs/standards/index.md)
5. The thematic standard for the area you are changing.

## Development rules

- Work on a feature branch, not directly on `main`, `master`, `production`, or `stable`.
- Keep changes small, coherent, and reversible.
- Do not mix unrelated domains in one commit.
- Do not commit `.runtime/`, real environment files, passwords, tokens, private keys, dumps, or customer-sensitive evidence.
- Preserve existing CLI compatibility unless a breaking change is explicitly approved.
- Any mutable operation must have validation, evidence, backup/snapshot, and rollback behavior or documented operational rollback.

## Commit convention

Use Conventional Commits:

```text
type(scope): description
```

Examples:

```text
docs(architecture): add contribution manual
feat(tls): add certificate evidence summary
fix(rollback): restore domain metadata permissions
```

## Validation expectations

Run the validations that match your change:

```bash
git diff --check
bash -n scripts/glpictl.sh scripts/lib/common.sh
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --syntax-check
```

For documentation-only changes, at minimum validate links, check for secrets, and run `git diff --check`.

## Pull request checklist

Before opening a PR, confirm:

- Scope is clear and isolated.
- Documentation is updated.
- No secrets or generated runtime artifacts are included.
- Existing commands remain compatible.
- Rollback impact is documented for mutable behavior.
- Validation results are listed in the PR description.

See the full [Architecture, Capabilities, and Contribution](docs/architecture/en/architecture-and-contribution.md) manual for implementation patterns.
