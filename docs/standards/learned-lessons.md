# Learned Lessons

Record real learnings here to avoid repeating mistakes.

## Format

### Problem

### Cause

### Applied fix

### Prevention rule

### When to consult

## Initial learnings

### Problem

Operational scripts were first created in `PowerShell` even though the target workflow is `Ubuntu/Linux`.

### Cause

The operational interface was not aligned with the target operating system early enough.

### Applied fix

Replace `.ps1` scripts with `.sh` scripts and standardize operations on `bash`.

### Prevention rule

If the operational environment is Linux, the automation interface must be Linux-first unless there is an explicit requirement otherwise.

### When to consult

When creating or reviewing operational scripts.

### Problem

Quoting errors in chained shell commands increase rework and waste calls.

### Cause

Indirect execution across different shells without simplifying the command shape.

### Applied fix

Prefer shorter, scriptable commands with fewer quoting layers.

### Prevention rule

If a command with complex quoting can be simplified, document and use the shorter, more predictable form.

### When to consult

When validating scripts or calling one tool from another shell.

### Problem

Generated names or credentials can drift toward common, obvious, or guessable defaults when there is no naming rule.

### Cause

Without an explicit convention, helpers and operators tend to fall back to generic names such as `admin`, `glpi`, or simple themed words.

### Applied fix

Adopt biblical-context naming for visible identifiers and require high-entropy randomness for all secrets.

### Prevention rule

Use biblical context for usernames, service accounts, aliases, and labels, but never use plain biblical words or predictable biblical patterns as passwords, tokens, or keys.

### When to consult

When creating users, service accounts, aliases, labels, or secrets.
