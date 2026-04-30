# Appendix: Operational Checks

## 1. Pre-flight Dependency Matrix

Mandatory:

- `bash`
- free local disk space >= 1 GB
- `git`
- `ansible-playbook`
- `ansible-inventory`
- operator in `glpiops`
- sudo/root capability
- script execute permissions
- `.runtime` and secret file permission baseline

Optional:

- `ssh`

Check commands:

```bash
command -v bash
command -v git
command -v ansible-playbook
command -v ansible-inventory
command -v ssh
df -Pk .
```

Auto-install behavior in scripts:

- For missing mandatory command, script asks whether it should install on Ubuntu.
- If accepted, script runs apt install.
- If install fails, script prints manual remediation and blocks flow.
- For permission or group deviations, script offers automatic safe fixes and blocks if unresolved.

## 2. Service and Deployment Checks

After deployment:

- `ansible-inventory` parses runtime inventory
- Nginx validation succeeds
- PHP-FPM validation succeeds
- MariaDB schema and user exist
- GLPI directories exist with expected permissions
- readiness gate report is generated and archived

Validation commands:

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list >/dev/null
sudo nginx -t
sudo php-fpm8.3 -t
sudo systemctl status nginx php8.3-fpm mariadb --no-pager
```

## 3. Usability Checks

- GLPI installer page loads
- DB connectivity from app host works
- app-to-db restriction is enforced by configured DB host rule

## 4. Monitoring and Backup Checks

- monitoring exporters are installed and enabled
- backup scripts are deployed
- backup cron jobs are configured

## 5. Day-2 Operation Checks

- `bash scripts/ops-maintenance.sh audit staging check`
- certificate warning check: `bash scripts/ops-maintenance.sh cert staging check`
- resumable checkpoint check: `.runtime/<env>/state/*.state.yml`
- execution log check: `.runtime/<env>/logs/*.log`

## 6. Runtime Data Hygiene

- `.runtime/` exists locally
- `overrides.runtime.yml` is present for mutable operational settings
- runtime secrets are not committed to Git
- secret files use restricted permissions (`chmod 600`)

## 7. Release Readiness Gate

Run:

```bash
bash scripts/release-readiness.sh staging
```

Expected outputs:

- `.runtime/staging/evidence/readiness-report.md`
- `.runtime/staging/evidence/readiness-report.json`
