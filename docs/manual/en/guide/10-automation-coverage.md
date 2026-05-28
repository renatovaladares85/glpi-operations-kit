# 10 - Automation Coverage

This chapter tells you what this repository already automates and what remains manual.

Main CLI contract:

```bash
./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit|auth> <action> [target] [scope]
```

Already covered by automation:

- deploy lifecycle (`check`, `prepare`, `apply`, `post-check`, `rollback`)
- tls lifecycle (`check`, `prepare`, `apply`, `post-check`, `rollback`)
- auth lifecycle (`check`, `prepare`, `apply`, `post-check`, `rollback`)
- certify/promotion gate workflows
- ops/audit workflows
- runtime logs, state, evidence, and domain snapshots

Not automated as operational baseline in this phase:

- automatic plugin installation
- dedicated Let\'s Encrypt workflow
- full Docker/Compose operational automation

Go next:

- [Command Reference](../appendices/command-reference.md)
- [Runtime Inputs and Files](../appendices/runtime-input-reference.md)
- [Deferred Features](../appendices/deferred-features.md)
