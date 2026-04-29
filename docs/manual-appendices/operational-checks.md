# Appendix: Operational Checks

## Pre-flight Checks

Current mandatory checks include:

- `bash` exists
- local free disk space threshold
- `git` exists
- `ansible-playbook` exists
- `ansible-inventory` exists (staging flow)

Current optional check:

- `ssh` command presence

## Service and Deployment Checks

After deployment:

- `ansible-inventory` loads runtime inventory successfully
- Nginx config test succeeds (`nginx -t`)
- PHP-FPM config test succeeds (`php-fpm8.3 -t`)
- MariaDB schema and user creation succeed
- GLPI files and runtime directories exist with expected ownership

## Usability Checks

- GLPI installer page loads
- DB connectivity from app host works
- app-to-db restriction is enforced by configured DB host rule

## Monitoring and Backup Checks

- monitoring exporters are installed and enabled
- backup scripts are deployed
- backup cron jobs are configured

## Runtime Data Hygiene

- `.runtime/` exists locally
- runtime secrets are not committed to Git
