# Apendice: Checks Operacionais

Pre-flight obrigatorio:

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`
- usuario no grupo `glpiops`
- sudo valido

Checks day-2:

- `bash scripts/ops-maintenance.sh audit staging check`
- verificar logs em `.runtime/staging/logs/`
- verificar estado em `.runtime/staging/state/`

Continuidade:

- para falhas incompletas use `bash scripts/ops-maintenance.sh resume staging`
