# Appendix: Deferred Features

This section lists capabilities that are not fully implemented as executable workflows in the current repository baseline.

## Not Implemented

- LDAP/AD integration workflow
- SMTP integration workflow
- centralized Prometheus/Grafana/Alertmanager provisioning
- HA and replication orchestration

## Partially Implemented

- certificate lifecycle automation
  - current state: TLS mode switching is script-driven
  - missing: full enterprise/public certificate automation pipeline
- backup security hardening
  - current state: backup scripts and scheduling exist
  - missing: complete production-grade encryption/key management workflow

## Planned

- expanded corporate homologation checks as executable scripts
- fuller production readiness automation for integrations and high availability
