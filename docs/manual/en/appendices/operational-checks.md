# Appendix: Operational Checks

## 1. Precheck outputs

After `deploy check`, validate:

- `.runtime/<env>/state/precheck-report-latest.yml`
- `.runtime/<env>/evidence/precheck-report-latest.md`

These reports classify each prerequisite as mandatory, optional, or conditional.

## 2. Deploy sequence controls

State file:

- `.runtime/<env>/state/deploy-sequence.yml`

Recommended order:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Policy behavior:

- when `security.require_ordered_execution=true` and `SECURITY_MODE=secure`, out-of-order calls are blocked;
- when `security.require_ordered_execution=true` and `SECURITY_MODE=permissive`, out-of-order calls continue with warning + evidence.

## 3. Service checks after apply

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list >/dev/null
sudo nginx -t
sudo php-fpm8.3 -t
sudo systemctl status nginx php8.3-fpm mariadb --no-pager
```

## 4. Certification and readiness evidence

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Mandatory artifacts:

- `.runtime/staging/evidence/readiness-report.md`
- `.runtime/staging/evidence/readiness-report.json`
- `.runtime/promotion/staging-certified.yml`

## 5. Day-2 operation evidence

Validate:

- `.runtime/<env>/logs/*.log`
- `.runtime/<env>/logs/*.summary.yml`
- `.runtime/<env>/state/*.state.yml`
- `.runtime/<env>/state/security-mode-last.yml` (when permissive mode is used)
- `.runtime/<env>/evidence/security-mode-*.yml` (when permissive mode is used)

These files are required for troubleshooting and audit.
