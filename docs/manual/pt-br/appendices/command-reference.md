# Apêndice: Referência de Comandos

## 1. Instalação de dependências no Ubuntu (manual)

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client ansible
```

Validação:

```bash
command -v bash
command -v git
command -v ansible-playbook
command -v ansible-inventory
command -v ssh
```

## 2. Bootstrap obrigatório de permissões

```bash
bash scripts/bootstrap-permissions.sh
```

## 3. Orquestrador de staging

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

## 4. Fallback manual com Ansible (sem script)

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/app.runtime.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags monitoring --extra-vars @.runtime/staging/monitoring.secrets.yml --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags backup --extra-vars @.runtime/staging/app.runtime.yml
```

## 5. Gestão de TLS

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```
