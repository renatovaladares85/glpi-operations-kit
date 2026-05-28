# Prerequisites Matrix (Canonical)

## Purpose

This matrix is the canonical source for pre-deployment prerequisites used by scripts and manuals.
Each item defines:

- classification (`mandatory`, `optional`, `conditional-mandatory`)
- applicability (environment, topology, TLS mode)
- technical/compliance reason
- validation method
- auto-fix support
- blocking behavior

## Matrix

| Item | Category | Environment | Condition | Requirement | Reason | Validation | Auto-fix | Block on Failure |
|---|---|---|---|---|---|---|---|---|
| Ubuntu 24.04 baseline | Platform | all | always | mandatory | Official support baseline for package and service behavior | `cat /etc/os-release` | No | Yes |
| `bash` | Local tooling | all | always | mandatory | Required by all operational scripts | `command -v bash` | Yes (`apt`) | Yes |
| `git` | Local tooling | all | always | mandatory | Required for repository lifecycle and repeatable operations | `command -v git` | Yes (`apt`) | Yes |
| `python3` + yaml module | Local tooling | all | always | mandatory | Required to render runtime config and inventory from `config/<env>.env` | `python3 -c "import yaml"` | Yes (`apt`) | Yes |
| `ansible-playbook` | Local tooling | all | always | mandatory | Required to apply Ansible roles | `command -v ansible-playbook` | Yes (`apt`) | Yes |
| `ansible-inventory` | Local tooling | all | always | mandatory | Required to validate generated inventory | `command -v ansible-inventory` | Yes (`apt`) | Yes |
| `sudo` (or root) | Privilege | all | always | mandatory | Required for package, permissions, and service operations | `sudo -v` | Partial | Yes |
| Operator in `glpiops` | Privilege | all | always | mandatory | Enforces least-privilege operational model | `id -nG` | Yes (`groupadd/usermod`) | Yes |
| Script execute permission | Permissions | all | always | mandatory | Prevents first-run execution failures | `ls -l scripts/*.sh` | Yes (`chmod +x`) | Yes |
| `.runtime` secure mode | Permissions | all | always | mandatory | Contains secrets, runtime state, and evidence | `stat -c '%a' .runtime` | Yes (`chmod`) | Yes |
| Security mode default | Policy control | all | always | mandatory | Defines default policy behavior when `SECURITY_MODE` is not passed | `OPERATIONS_SECURITY_MODE_DEFAULT` in config | No | Yes |
| Execution mode contract | Execution contract | all | always | mandatory | Prevents wrong orchestration model for local/ssh execution | `EXECUTION_MODE` or `GLPI_EXECUTION_MODE` | No | Yes |
| Host role contract | Execution contract | all | always | mandatory | Ensures local host runs only allowed mutable actions | `EXECUTION_HOST_ROLE_DEFAULT` or `GLPI_HOST_ROLE` | No | Yes |
| SSH key pair per environment | Security artifact | all | `EXECUTION_MODE=ssh` | conditional-mandatory | Supports safe environment isolation and host access | key existence + mode `0600` | Partial | Yes |
| SSH connectivity to app/db | Network access | all | `EXECUTION_MODE=ssh` + `TOPOLOGY_MODE=dual-server` | conditional-mandatory | Confirms execution host can reach both targets | `ssh -i <key> <user>@<host> "echo ok"` | No | Yes |
| TLS local files | Security artifact | all | `TLS_MODE=provided` | conditional-mandatory | Required to install valid cert/key in app host | local file existence check | No | Yes |
| Promotion gate file | Promotion control | all | `SECURITY_REQUIRE_PROMOTION_GATE=true` | conditional-mandatory | Enforces certification before mutable rollout when policy is enabled | `.runtime/promotion/staging-certified.yml` exists | No | Yes in `secure`; No in `permissive` |
| TLS mode policy | Security policy | all | `SECURITY_REQUIRE_TLS=true` | conditional-mandatory | Requires valid provided certificate mode when policy is enabled | `TLS_MODE=provided` | No | Yes in `secure`; No in `permissive` |
| HTTPS policy | Security policy | all | `SECURITY_REQUIRE_HTTPS=true` | conditional-mandatory | Requires encrypted transport when policy is enabled | `TLS_MODE!=none` | No | Yes in `secure`; No in `permissive` |
| Ordered execution policy | Workflow policy | all | `SECURITY_REQUIRE_ORDERED_EXECUTION=true` | conditional-mandatory | Prevents out-of-order deployment state | deploy sequence state file | No | Yes in `secure`; No in `permissive` |
| `ssh` client | Diagnostic tooling | all | always | optional | Useful for diagnostics and manual checks | `command -v ssh` | Yes (`apt`) | No |
| Free local disk >= 1 GB | Local host health | all | always | mandatory | Required for runtime artifacts and evidence | `df -Pk .` | No | Yes |

## Notes

- Policy blocking is controlled by execution mode:
  - `SECURITY_MODE=secure`: policy failures block.
  - `SECURITY_MODE=permissive`: policy failures become warnings with persisted risk evidence.
- `SECURITY_MODE` defaults to `OPERATIONS_SECURITY_MODE_DEFAULT` from config.
- Precheck reports are persisted under:
  - `.runtime/<env>/state/precheck-report-latest.yml`
  - `.runtime/<env>/evidence/precheck-report-latest.md`
