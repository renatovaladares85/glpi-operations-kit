# 06 - GLPI Upgrade In Place

This repository uses an in-place upgrade posture with strict safety checks.

Minimum conditions before upgrade:

1. validated backup available;
2. approved maintenance window;
3. staging rehearsal completed;
4. rollback path confirmed.

Typical sequence:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy post-check all
bash scripts/release-readiness.sh staging
```

You usually set the target version in `config/<environment>.env` before applying.

What success looks like:

- deploy apply app succeeds;
- post-check succeeds;
- readiness report has no critical failures.

Common error and quick action:

- error: upgrade attempted without validated backup
- action: stop upgrade, produce backup, then re-run with controlled window

Go next:

- [03 - Deploy on Linux](03-deploy-linux-traditional.md)
- [Operational Checks](../appendices/operational-checks.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
