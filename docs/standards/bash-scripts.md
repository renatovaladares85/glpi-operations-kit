# Bash Scripts Standard

## Objective

Standardize guided scripts for `Ubuntu/Linux` operations.

## Rules

- Use `#!/usr/bin/env bash`
- Use `set -euo pipefail`
- Centralize shared functions in `scripts/lib/common.sh`
- Run environment pre-flight checks before implementation logic
- Resolve effective security mode before mutating operations (`SECURITY_MODE` or config default)
- Explain why each sensitive value is being requested
- Explain where the value will be written
- Stop execution when critical information is missing
- Persist execution logs for each operational run
- Persist checkpoint/state data for resumable operations
- When running in `permissive`, persist risk-acceptance evidence with justification and violated policies

## Runtime secrets

- Store only under `.runtime/<environment>/secrets.yml`
- Never version `.runtime/`
- Never echo secrets to the terminal
- If a script ever suggests or generates account names, prefer biblical-context naming.
- If a script ever suggests or generates secrets, use high-entropy random values and never plain biblical words or predictable biblical patterns.

## Standard flow

- `bootstrap-permissions`
- `config render`
- `pre-flight`
- `check`
- `apply`
- `post-check`
- `day-2-ops`

## Public configuration

- Use `config/<environment>.env` as the single public configuration source.
- Render `.runtime/<environment>/public.runtime.yml` and `inventory.runtime.yml` from that file.
- Keep mutable operational overrides in `.runtime/<environment>/overrides.runtime.yml`.
- Merge precedence must stay explicit: `public.runtime.yml -> overrides.runtime.yml -> secrets.yml`.
- Prompt only for missing secret values, not for public values already present in config.

## Pre-flight policy

Each implementation script must:

- verify mandatory requirements before changing anything;
- verify optional but recommended requirements;
- clearly label each result as `mandatory` or `optional`;
- stop when a mandatory item is missing or invalid;
- continue after a mandatory failure only with explicit user authorization.

Mandatory examples:

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory` when inventory validation is required
- minimum local disk space for runtime artifacts
- script execute permission baseline
- sudo/root capability for deployment
- operator membership in `glpiops`
- secure runtime and secret file permissions

Optional examples:

- `ssh` available locally before remote operations
- extra diagnostic tools that improve troubleshooting but do not block execution

## Required error behavior

When a critical value is missing, the script must explain:

- which value is missing;
- why it is needed;
- which file or component will use it.

When a script proposes default names or credentials, it must explain:

- whether the value is an identifier or a secret;
- that identifiers should use biblical context when appropriate;
- that secrets must remain random and must not be simple biblical words.

When a mandatory pre-flight item fails, the script must explain:

- which requirement failed;
- whether it is mandatory or optional;
- whether it can be safely updated automatically;
- that execution is blocked until the issue is fixed or explicitly overridden by the user.
