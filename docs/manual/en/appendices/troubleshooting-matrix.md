# Appendix - Troubleshooting Matrix (EN)

## Missing `ansible-playbook` or `ansible-inventory`

- Symptom: `deploy check` fails in mandatory tooling checks.
- Validate: `command -v ansible-playbook && command -v ansible-inventory`
- Fix: accept script auto-install prompt or run `sudo apt-get install -y ansible`
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy check all`

## `permission denied` on script execution

- Symptom: `./scripts/*.sh` fails with permission errors.
- Validate: `ls -l scripts/*.sh`
- Fix: run `bash scripts/bootstrap-permissions.sh`
- Safe resume: rerun the blocked command

## Missing `config/<env>.env` in precheck

- Symptom: precheck fails with a mandatory message indicating missing environment config file.
- Validate: `ls -l config/<env>.env`
- Fix: `cp config/product.env config/<env>.env`, then edit the new file with your environment values.
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy check all`.

## Wrong host role in local dual-server flow

- Symptom: `deploy apply db` or `deploy apply app` is blocked by role policy.
- Validate: check `EXECUTION_HOST_ROLE_DEFAULT` in `config/<env>.env` and verify effective mode in precheck report.
- Fix: use `db` role on DB host and `app` role on APP host for local dual-server.
- Safe resume: rerun command on the correct host with corrected role.

## SSH key path invalid in `EXECUTION_MODE=ssh`

- Symptom: precheck fails on SSH key policy.
- Validate: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
- Fix: generate key pair and update `NETWORK_SSH_PRIVATE_KEY_PATH`.
- Safe resume: rerun `deploy check`.

## SSH private key mode unsafe

- Symptom: key permission check fails.
- Validate: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
- Fix: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
- Safe resume: rerun `deploy check`.

## Policy blocked in `secure` mode

- Symptom: mutable command exits due to policy violation.
- Validate:
  - effective mode (`SECURITY_MODE` or `OPERATIONS_SECURITY_MODE_DEFAULT`)
  - policy flags in `config/<env>.env` (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_SSO`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`)
- Fix: either comply with policy requirements or switch to permissive execution with explicit justification.
- Safe resume:
  - secure path: fix config and rerun;
  - permissive path: rerun with `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="<reason>"`.

## Ordered execution blocked

- Symptom: `apply app` blocked before `apply db`.
- Validate: `.runtime/<env>/state/deploy-sequence.yml`
- Fix:
  - secure mode: run `check -> apply db -> apply app -> monitoring -> backup -> post-check`
  - permissive mode: continue with warning and evidence
- Safe resume: run only the next required stage.

## TLS provided files missing

- Symptom: `tls install-provided` fails.
- Validate: file existence for `TLS_PROVIDED_LOCAL_CERT_PATH` and `TLS_PROVIDED_LOCAL_KEY_PATH`.
- Fix: set valid local paths and rerun TLS action.
- Safe resume: `./scripts/glpictl.sh <env> tls install-provided`.
