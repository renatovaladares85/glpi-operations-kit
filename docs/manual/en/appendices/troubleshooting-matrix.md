# Appendix - Troubleshooting Matrix (EN)

## Missing `ansible-playbook` or `ansible-inventory`

- Symptom: `deploy check` fails in mandatory tooling checks.
- Validate: `command -v ansible-playbook && command -v ansible-inventory`
- Fix: accept script auto-install prompt or run `sudo apt-get install -y ansible`
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy check all`
  - Example: `./scripts/glpictl.sh staging deploy check all`

## `permission denied` on script execution

- Symptom: `./scripts/*.sh` fails with permission errors.
- Validate: `ls -l scripts/*.sh`
- Fix: run `bash scripts/bootstrap-permissions.sh`
- Safe resume: rerun the blocked command

## `sudo` password prompt during local validation

- Symptom: `deploy check` or another command asks for `sudo` password.
- Clarification: this password is for the local Linux VM/host account.
- It is not: MySQL password, RDS password, or SSH credential.
- Fix:
  - VM-managed DB (`DATABASE_DEPLOYMENT_MODE=self_hosted`): use an operator account with sudo privileges.
  - Managed RDS (`DATABASE_DEPLOYMENT_MODE=managed`): use app/validation flow without Linux DB-host operations.

## Missing `config/<env>.env` in precheck

- Symptom: precheck fails with a mandatory message indicating missing environment config file.
- Validate: `ls -l config/<env>.env`
  - Example: `ls -l config/staging.env`
- Fix: `cp config/product.env config/<env>.env`, then edit the new file with your environment values.
  - Example: `cp config/product.env config/staging.env`
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy check all`.
  - Example: `./scripts/glpictl.sh staging deploy check all`

## Wrong host role in local dual-server flow

- Symptom: `deploy apply db` or `deploy apply app` is blocked by role policy.
- Validate: check `EXECUTION_HOST_ROLE_DEFAULT` in `config/<env>.env` and verify effective mode in precheck report.
  - Example: `config/staging.env`
- Fix: use `db` role on DB host and `app` role on APP host for local dual-server.
- Safe resume: rerun command on the correct host with corrected role.

## `deploy apply db` blocked with `DATABASE_DEPLOYMENT_MODE=managed`

- Symptom: execution fails saying `deploy apply db` is not supported in managed mode.
- Cause: managed RDS/external DB has no Linux DB host for MariaDB provisioning tasks.
- Fix:
  - keep using `deploy apply app|monitoring|backup`;
  - validate APP->RDS TCP connectivity (`mysql --protocol=TCP --host <rds-endpoint> ...`).
- Safe resume: rerun with a compatible target (`app`, `monitoring`, `backup`).

## SSH key path invalid in `EXECUTION_MODE=ssh`

- Symptom: precheck fails on SSH key policy.
- Validate: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
  - Example: `ls -l ~/.ssh/glpi_staging_ed25519 ~/.ssh/glpi_staging_ed25519.pub`
- Fix: generate key pair and update `NETWORK_SSH_PRIVATE_KEY_PATH`.
- Safe resume: rerun `deploy check`.

## SSH private key mode unsafe

- Symptom: key permission check fails.
- Validate: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
  - Example: `stat -c '%a' ~/.ssh/glpi_staging_ed25519`
- Fix: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
  - Example: `chmod 600 ~/.ssh/glpi_staging_ed25519`
- Safe resume: rerun `deploy check`.

## Policy blocked in `secure` mode

- Symptom: mutable command exits due to policy violation.
- Validate:
  - effective mode (`SECURITY_MODE` or `OPERATIONS_SECURITY_MODE_DEFAULT`)
  - policy flags in `config/<env>.env` (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_SSO`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`)
  - Example: `config/staging.env`
- Fix: either comply with policy requirements or switch to permissive execution with explicit justification.
- Safe resume:
  - secure path: fix config and rerun;
  - permissive path: rerun with `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="<reason>"`.
  - Example: `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="risk-accepted-for-maintenance"`

## Ordered execution blocked

- Symptom: `apply app` blocked before `apply db`.
- Validate: `.runtime/<env>/state/deploy-sequence.yml`
  - Example: `.runtime/staging/state/deploy-sequence.yml`
- Fix:
  - secure mode: run `check -> apply db -> apply app -> monitoring -> backup -> post-check`
  - permissive mode: continue with warning and evidence
- Safe resume: run only the next required stage.

## Web server mismatch (single-engine policy)

- Symptom: `deploy check` or `deploy apply app` is blocked by `single-web-server` policy.
- Validate:
  - configured engine: `grep '^WEB_SERVER_TYPE=' config/<env>.env`
  - Example: `grep '^WEB_SERVER_TYPE=' config/staging.env`
  - active services: `systemctl is-active nginx apache2 lighttpd`
- Fix:
  - keep only one active engine matching `WEB_SERVER_TYPE`;
  - stop/disable conflicting engines on the host.
- Safe resume:
  - rerun `./scripts/glpictl.sh <env> deploy check all` and then `deploy apply app`.
  - Example: `./scripts/glpictl.sh staging deploy check all`

## TLS provided files missing

- Symptom: `tls install-provided` fails.
- Validate: file existence for `TLS_PROVIDED_LOCAL_CERT_PATH` and `TLS_PROVIDED_LOCAL_KEY_PATH`.
- Fix: set valid local paths and rerun TLS action.
- Safe resume: `./scripts/glpictl.sh <env> tls install-provided`.
  - Example: `./scripts/glpictl.sh staging tls install-provided`

## Missing `bcmath` during GLPI install (QR code requirement)

- Symptom: GLPI installer reports missing `bcmath`, or `deploy apply app` fails in PHP extension assertion.
- Validate: `php -m | grep -i '^bcmath$'`
- Fix:
  - run `./scripts/glpictl.sh <env> deploy check all` and accept auto-install; or
  - Example: `./scripts/glpictl.sh staging deploy check all`
  - manual remediation: `sudo apt-get update && sudo apt-get install -y php-bcmath`
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy apply app`.
  - Example: `./scripts/glpictl.sh staging deploy apply app`

## APP host cannot run DB connectivity checks

- Symptom: app validation fails with `mysql: command not found` or APP->DB `SELECT 1` check fails.
- Validate:
  - `command -v mysql`
  - `mysql --protocol=TCP --host <db-host> --port <db-port> --user <glpi-db-user> --password --execute "SELECT 1;"`
  - Example: `mysql --protocol=TCP --host 192.0.2.20 --port 3306 --user nehemiah_glpi --password --execute "SELECT 1;"`
- Fix:
  - install client: `sudo apt-get update && sudo apt-get install -y mariadb-client`
  - confirm DB user/password and network path from APP host.
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy apply app`.
  - Example: `./scripts/glpictl.sh staging deploy apply app`

## `/install/install.php` returns 404 or install flow breaks

- Symptom: root page opens, but installer redirect path returns 404 or stops.
- Validate:
  - `curl -I -H "Host: <glpi-domain>" http://127.0.0.1:<http-port>/`
  - Example: `curl -I -H "Host: glpi-staging.example.internal" http://127.0.0.1:80/`
  - `curl -I -H "Host: <glpi-domain>" http://127.0.0.1:<http-port>/install/install.php`
  - Example: `curl -I -H "Host: glpi-staging.example.internal" http://127.0.0.1:80/install/install.php`
- Fix:
  - rerun `./scripts/glpictl.sh <env> deploy apply app` to re-render selected engine template;
  - Example: `./scripts/glpictl.sh staging deploy apply app`
  - for nginx, confirm official GLPI router pattern in `nginx-glpi.conf`: `root .../public`, `location / { try_files $uri /index.php$is_args$args; }`, and `location ~ ^/index\.php$`.
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy post-check app`.
  - Example: `./scripts/glpictl.sh staging deploy post-check app`

## `render_product_config.py` NameError (`values` or `web_server_type`)

- Symptom: `deploy check` fails with errors such as `NameError: name 'values' is not defined` or `NameError: name 'web_server_type' is not defined`.
- Validate:
  - `python3 scripts/lib/render_product_config.py --config config/<env>.env --mode public-runtime`
  - Example: `python3 scripts/lib/render_product_config.py --config config/staging.env --mode public-runtime`
  - `python3 scripts/lib/render_product_config.py --config config/<env>.env --mode inventory`
  - Example: `python3 scripts/lib/render_product_config.py --config config/staging.env --mode inventory`
- Fix:
  - update local repository to latest commit (`git pull`) containing the renderer scope fix;
  - ensure `WEB_SERVER_TYPE` is present in `config/<env>.env`.
  - Example: `config/staging.env`
- Safe resume:
  - rerun `./scripts/glpictl.sh <env> deploy check all`.
  - Example: `./scripts/glpictl.sh staging deploy check all`
