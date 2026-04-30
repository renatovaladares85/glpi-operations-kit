# Apendice: Referencia de Comandos

## Dependencias Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client python3 python3-yaml ansible
```

## Bootstrap obrigatorio

```bash
bash scripts/bootstrap-permissions.sh
```

## Configuracao publica

Arquivos principais:

- `config/staging.yml`
- `config/production.yml`
- `config/product.example.yml`

## Exemplos da CLI oficial

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging certify run
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging ops cert check
```

## Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags monitoring --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags backup --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```
