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
| `python3` + yaml module | Local tooling | all | always | mandatory | Required to render runtime config and inventory from `config/<env>.yml` | `python3 -c "import yaml"` | Yes (`apt`) | Yes |
| `ansible-playbook` | Local tooling | all | always | mandatory | Required to apply Ansible roles | `command -v ansible-playbook` | Yes (`apt`) | Yes |
| `ansible-inventory` | Local tooling | all | always | mandatory | Required to validate generated inventory | `command -v ansible-inventory` | Yes (`apt`) | Yes |
| `sudo` (or root) | Privilege | all | always | mandatory | Required for package, permissions, and service operations | `sudo -v` | Partial | Yes |
| Operator in `glpiops` | Privilege | all | always | mandatory | Enforces least-privilege operational model | `id -nG` | Yes (`groupadd/usermod`) | Yes |
| Script execute permission | Permissions | all | always | mandatory | Prevents first-run execution failures | `ls -l scripts/*.sh` | Yes (`chmod +x`) | Yes |
| `.runtime` secure mode | Permissions | all | always | mandatory | Contains secrets, runtime state, and evidence | `stat -c '%a' .runtime` | Yes (`chmod`) | Yes |
| SSH key pair per environment | Security artifact | all | when remote execution is used | conditional-mandatory | Supports safe environment isolation and host access | key existence + mode `0600` | Partial | Yes |
| SSH connectivity to app/db | Network access | all | `topology.mode=dual-server` | conditional-mandatory | Confirms execution host can reach both targets | `ssh -i <key> <user>@<host> "echo ok"` | No | Yes |
| TLS local files | Security artifact | all | `tls.mode=provided` | conditional-mandatory | Required to install valid cert/key in app host | local file existence check | No | Yes |
| Promotion gate file | Promotion control | production | always | mandatory | Production rollout depends on staged evidence | `.runtime/promotion/staging-certified.yml` exists | No | Yes |
| Production TLS mode | Environment policy | production | always | mandatory | Production must not run insecure TLS mode | `tls.mode` in config/runtime | No | Yes |
| Production HTTPS enabled | Environment policy | production | `security.require_https_in_production=true` | mandatory | Compliance baseline for secure sessions and transport | `glpi_use_tls=true` runtime value | No | Yes |
| Production SSO enabled | Environment policy | production | `security.require_sso_in_production=true` | mandatory | Corporate identity and access policy gate | `security.sso_enabled=true` in config | No | Yes |
| `ssh` client | Diagnostic tooling | all | always | optional | Useful for diagnostics and manual checks | `command -v ssh` | Yes (`apt`) | No |
| Free local disk >= 1 GB | Local host health | all | always | mandatory | Required for runtime artifacts and evidence | `df -Pk .` | No | Yes |

## Notes

- Staging/development may run with `tls.mode=none` only if policy allows insecure non-production modes.
- Production is blocked unless security policies and promotion gate conditions are satisfied.
- Precheck reports are persisted under:
  - `.runtime/<env>/state/precheck-report-latest.yml`
  - `.runtime/<env>/evidence/precheck-report-latest.md`
