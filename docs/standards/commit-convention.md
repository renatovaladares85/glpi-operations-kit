# Commit Convention

## Official standard

This repository uses `Conventional Commits`.

Format:

```text
type(scope): description
```

## Allowed types

- `feat`
- `fix`
- `docs`
- `refactor`
- `chore`
- `perf`
- `test`
- `build`
- `ci`

## Recommended initial scopes

- `ansible-base`
- `ansible-app`
- `ansible-db`
- `monitoring`
- `backup`
- `scripts`
- `docs`
- `agents`
- `security`

## When to create a commit

Create a commit only when a `validated functional block` is complete.

Definition of a validated functional block:

- changes one coherent unit of behavior;
- can be understood and reverted in isolation;
- received the minimum applicable validation;
- does not mix unrelated goals or risks.

## Good examples

- `docs(agents): create standards catalog for AI workflows`
- `fix(scripts): correct runtime secret flow`
- `feat(ansible-app): add initial glpi nginx template`
- `chore(monitoring): add base exporters for staging`

## Bad examples

- `update files`
- `fix: many things`
- `docs(ansible-app): change scripts and monitoring`
- `feat(all): adjust everything`

## Recovery rule

Each commit should make it easy to identify:

- what changed;
- which area was affected;
- whether rollback can happen without touching the rest.
