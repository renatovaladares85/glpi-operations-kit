# Appendix: Command Reference

## 1. Ubuntu Dependency Installation (Manual)

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client ansible
```

Validation:

```bash
command -v bash
command -v git
command -v ansible-playbook
command -v ansible-inventory
command -v ssh
```

## 2. Mandatory Permission Bootstrap

```bash
bash scripts/bootstrap-permissions.sh
```

## 3. Staging Orchestrator

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

## 4. Manual Ansible Fallback (No Script Path)

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/app.runtime.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags monitoring --extra-vars @.runtime/staging/monitoring.secrets.yml --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags backup --extra-vars @.runtime/staging/app.runtime.yml
```

## 5. TLS Management

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```

## 6. Targeted Script Entry Points

```bash
./scripts/bootstrap-host.sh staging
./scripts/bootstrap-permissions.sh
./scripts/deploy-db.sh staging
./scripts/deploy-app.sh staging
./scripts/deploy-monitoring.sh staging
./scripts/deploy-backup.sh staging
```

## 7. Service Validation on Target Hosts

```bash
sudo nginx -t
sudo php-fpm8.3 -t
sudo systemctl status nginx php8.3-fpm mariadb --no-pager
```
