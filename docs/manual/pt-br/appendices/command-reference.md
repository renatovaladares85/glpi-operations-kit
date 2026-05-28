# Apêndice - Referência de Comandos (PT-BR)

Este apêndice complementa o runbook principal com comandos diretos e finalidade operacional. A sintaxe é a mesma; o que muda é o ambiente e os valores em `config/<environment>.env`.

## Preparar ferramentas do host

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

Use quando o host executor for novo ou estiver sem dependências.

## Preparar permissões dos scripts

```bash
bash scripts/bootstrap-permissions.sh
```

Execute antes do primeiro comando de deploy em sessão nova de operador.

## Criar e editar configuração de ambiente

```bash
cp config/product.env config/staging.env
```

Esse comando cria o baseline do ambiente. Os scripts carregam esse arquivo automaticamente.

## Comandos principais de implantação

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy prepare all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
./scripts/glpictl.sh <env> deploy rollback all
```

Exemplo com valores preenchidos:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy prepare all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging deploy rollback all
```

## Fluxo dual-server local (sem SSH direto entre servidores)

No host DB:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

No host APP:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

## Modo SSH opcional

```bash
GLPI_EXECUTION_MODE=ssh ./scripts/glpictl.sh staging deploy check all
```

Use somente quando a política permitir orquestração remota.

## Validação de rota web e fluxo de instalação

```bash
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy post-check app
```

## Comandos de ciclo de vida TLS

```bash
./scripts/glpictl.sh <env> tls check
./scripts/glpictl.sh <env> tls prepare self-signed
./scripts/glpictl.sh <env> tls apply self-signed
./scripts/glpictl.sh <env> tls post-check
./scripts/glpictl.sh <env> tls rollback
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

## Certificação, prontidão e evidências

```bash
./scripts/glpictl.sh staging certify check
./scripts/glpictl.sh staging certify prepare
./scripts/glpictl.sh staging certify run
./scripts/glpictl.sh staging certify apply
./scripts/glpictl.sh staging certify post-check
./scripts/glpictl.sh staging certify rollback
bash scripts/release-readiness.sh staging
```

## Operações day-2

```bash
./scripts/glpictl.sh <env> ops check
./scripts/glpictl.sh <env> ops prepare
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit check
./scripts/glpictl.sh <env> ops timezone check
./scripts/glpictl.sh <env> ops timezone apply
./scripts/glpictl.sh <env> ops resume
./scripts/glpictl.sh <env> ops rollback
./scripts/glpictl.sh <env> audit check
./scripts/glpictl.sh <env> audit prepare
./scripts/glpictl.sh <env> audit rollback
```

## Nota sobre SSO

A configuração SSO/SAML/OIDC é manual no GLPI e no IdP. O contrato atual da CLI não possui domínio `auth`.

## Backup e restore unificado GLPI (app|db|all)

```bash
sudo ./scripts/backup-app.sh backup --target all --encrypt
sudo ./scripts/backup-app.sh backup --target app --exclude-app "var/_cache,var/_sessions"
sudo ./scripts/backup-app.sh backup --target db --exclude-db-tables-data "glpi_logs,glpi_sessions"

sudo ./scripts/backup-app.sh restore --target app --artifact /var/backups/glpi/<arquivo>.tar.gz --force
sudo ./scripts/backup-app.sh restore --target db --artifact /var/backups/glpi/<arquivo>.tar.gz --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
sudo ./scripts/backup-app.sh restore --target all --artifact /var/backups/glpi/<arquivo>.tar.gz --force --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
```

## Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```
