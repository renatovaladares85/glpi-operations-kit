# Bash Scripts Standard

## Objective

Standardize guided scripts for `Ubuntu/Linux` operations.

## Rules

- Use `#!/usr/bin/env bash`
- Use `set -euo pipefail`
- Centralize shared functions in `scripts/lib/common.sh`
- Explain why each sensitive value is being requested
- Explain where the value will be written
- Stop execution when critical information is missing

## Runtime secrets

- Store only under `.runtime/<environment>/`
- Never version `.runtime/`
- Never echo secrets to the terminal

## Standard flow

- `check`
- `apply`
- `post-check`

## Required error behavior

When a critical value is missing, the script must explain:

- which value is missing;
- why it is needed;
- which file or component will use it.
