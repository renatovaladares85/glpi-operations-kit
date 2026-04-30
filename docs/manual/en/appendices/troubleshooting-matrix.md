# Appendix: Troubleshooting Matrix

## Missing `ansible-playbook` or `ansible-inventory`

- Symptom: precheck fails on mandatory tooling.
- Check: `command -v ansible-playbook && command -v ansible-inventory`
- Fix: accept auto-install prompt or run `sudo apt-get install -y ansible`
- Safe resume: rerun `./scripts/glpictl.sh <env> deploy check all`

## SSH key path invalid or missing

- Symptom: precheck fails on SSH key policy.
- Check: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
- Fix: generate key pair and update `network.ssh.private_key_path`
- Safe resume: rerun deploy check

## SSH private key mode unsafe

- Symptom: key mode check fails.
- Check: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
- Fix: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
- Safe resume: rerun deploy check

## Production blocked by TLS policy

- Symptom: production apply exits with TLS mode/HTTPS error.
- Check: `config/production.yml` -> `tls.mode`, `security.require_tls_in_production`, `security.require_https_in_production`
- Fix: set `tls.mode=provided`, configure valid certificate paths
- Safe resume: rerun `production deploy check all`, then apply

## Production blocked by SSO policy

- Symptom: production apply exits with SSO policy error.
- Check: `config/production.yml` -> `security.sso_enabled`
- Fix: set `security.sso_enabled: true`
- Safe resume: rerun precheck and apply flow

## Execution order blocked

- Symptom: `apply app` blocked before `apply db`.
- Check: `.runtime/<env>/state/deploy-sequence.yml`
- Fix: execute mandatory sequence from `check -> apply db -> apply app ...`
- Safe resume: run next required stage only

## TLS provided files missing

- Symptom: `tls install-provided` fails.
- Check: local cert/key file existence and paths in config/override.
- Fix: set valid local file paths and rerun TLS command
- Safe resume: rerun `tls install-provided`
