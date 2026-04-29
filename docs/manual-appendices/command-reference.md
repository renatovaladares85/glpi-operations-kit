# Appendix: Command Reference

## Staging Orchestrator

```bash
./scripts/deploy-staging.sh check
./scripts/deploy-staging.sh apply base
./scripts/deploy-staging.sh apply db
./scripts/deploy-staging.sh apply app
./scripts/deploy-staging.sh apply monitoring
./scripts/deploy-staging.sh apply backup
./scripts/deploy-staging.sh apply all
./scripts/deploy-staging.sh post-check all
```

## TLS Management

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```

## Targeted Script Entry Points

```bash
./scripts/bootstrap-host.sh staging
./scripts/deploy-db.sh staging
./scripts/deploy-app.sh staging
./scripts/deploy-monitoring.sh staging
./scripts/deploy-backup.sh staging
```

## Local Validation Commands

```bash
ansible-inventory --list -i ansible/inventories/staging/hosts.yml
ansible-playbook --syntax-check ansible/site.yml
```
