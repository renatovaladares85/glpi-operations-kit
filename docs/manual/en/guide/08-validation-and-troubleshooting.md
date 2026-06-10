# 08 - Validation and Troubleshooting

After each important step, validate first. Do not declare success based only on command completion.

Core validation flow:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging audit check
bash scripts/release-readiness.sh staging
```

Service-level checks:

```bash
nginx -t
php-fpm8.3 -t
```

When there is an incident, start from symptom, not assumptions:

- page not loading
- HTTP 404/500
- database connectivity issues
- TLS certificate issues
- backup/restore failures

Common error and quick action:

- error: treating warning as success in permissive flow
- action: review evidence/state artifacts and resolve root cause before closing task

Go next:

- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
- [Operational Checks](../appendices/operational-checks.md)
- [Command Reference](../appendices/command-reference.md)
