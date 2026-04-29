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
