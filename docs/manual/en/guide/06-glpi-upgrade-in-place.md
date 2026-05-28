# 06 - GLPI Upgrade In Place

This repository uses in-place upgrade with mandatory technical validations.

Minimum conditions before upgrade:

1. backup artifact is available and verifiable;
2. target version is defined in `config/<environment>.env`;
3. technical rollback path is confirmed;
4. post-upgrade validation commands are prepared.

Typical sequence:

```bash
./scripts/glpictl.sh <environment> deploy check all
./scripts/glpictl.sh <environment> deploy apply app
./scripts/glpictl.sh <environment> deploy post-check all
bash scripts/release-readiness.sh <environment>
```

What success looks like:

- `deploy apply app` succeeds;
- `post-check` succeeds;
- readiness report has no critical failures.

Common error and quick action:

- error: upgrade started without a verifiable backup
- action: stop, generate a new verifiable backup, and rerun

Go next:

- [03 - Deploy on Linux](03-deploy-linux-traditional.md)
- [Operational Checks](../appendices/operational-checks.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
