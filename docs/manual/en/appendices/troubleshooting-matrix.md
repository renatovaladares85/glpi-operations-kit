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

## Blocked by secure policy mode

- Symptom: mutable command exits with policy violation (TLS/HTTPS/SSO/gate/order).
- Check:
  - `echo "$SECURITY_MODE"` or `operations.security_mode_default`;
  - `config/<env>.yml` policy flags: `security.require_tls`, `security.require_https`, `security.require_sso`, `security.require_promotion_gate`, `security.require_ordered_execution`.
- Fix: either comply with policy requirements or run in permissive mode with explicit justification.
- Safe resume:
  - secure path: fix config and rerun command;
  - permissive path: rerun with `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="<reason>"`.

## Execution order blocked

- Symptom: `apply app` blocked before `apply db`.
- Check: `.runtime/<env>/state/deploy-sequence.yml`
- Fix:
  - secure mode: execute sequence `check -> apply db -> apply app -> monitoring -> backup -> post-check`;
  - permissive mode: you can continue, but warnings/evidence are registered automatically.
- Safe resume: run next required stage only

## TLS provided files missing

- Symptom: `tls install-provided` fails.
- Check: local cert/key file existence and paths in config/override.
- Fix: set valid local file paths and rerun TLS command
- Safe resume: rerun `tls install-provided`
