# Bash Scripts Standard

## Objective

Standardize guided scripts for `Ubuntu/Linux` operations.

## Rules

- Use `#!/usr/bin/env bash`
- Use `set -euo pipefail`
- Centralize shared functions in `scripts/lib/common.sh`
- Run environment pre-flight checks before implementation logic
- Explain why each sensitive value is being requested
- Explain where the value will be written
- Stop execution when critical information is missing

## Runtime secrets

- Store only under `.runtime/<environment>/`
- Never version `.runtime/`
- Never echo secrets to the terminal

## Standard flow

- `pre-flight`
- `check`
- `apply`
- `post-check`

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

Optional examples:

- `ssh` available locally before remote operations
- extra diagnostic tools that improve troubleshooting but do not block execution

## Required error behavior

When a critical value is missing, the script must explain:

- which value is missing;
- why it is needed;
- which file or component will use it.

When a mandatory pre-flight item fails, the script must explain:

- which requirement failed;
- whether it is mandatory or optional;
- whether it can be safely updated automatically;
- that execution is blocked until the issue is fixed or explicitly overridden by the user.
