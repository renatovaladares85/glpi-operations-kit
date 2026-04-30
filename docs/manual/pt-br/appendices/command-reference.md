# Apêndice: Referência de Comandos

## 1. Instalação de dependências no Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

O que faz:

- instala as ferramentas locais obrigatórias para scripts e Ansible.

Quando usar:

- primeira preparação do host executor.

## 2. Primeiro comando obrigatório (bootstrap de permissões)

```bash
bash scripts/bootstrap-permissions.sh
```

O que faz:

- aplica permissão de execução em `scripts/*.sh`
- valida `sudo`
- valida participação no grupo `glpiops`
- cria/repara baseline seguro de `.runtime`

Saída esperada:

- `Bootstrap completed.`

## 3. Variáveis do contrato de execução

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=app
export SECURITY_MODE=secure
```

Significado:

- `GLPI_ENVIRONMENT`: seletor do arquivo `config/<environment>.yml`
- `GLPI_EXECUTION_MODE`: `local` ou `ssh`
- `GLPI_HOST_ROLE`: `app`, `db` ou `all`
- `SECURITY_MODE`: `secure` bloqueia violações de política, `permissive` registra risco e continua

## 4. Fluxo dual-server em modo local (sem SSH entre servidores, compatível com 2FA)

No host DB:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=db
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

No host APP:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=app
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Motivo do fluxo:

- elimina dependência de SSH direto servidor-a-servidor
- permite autenticação corporativa interativa com 2FA em cada host

## 5. Fluxo single-server

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=all
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

## 6. Modo SSH remoto (opcional)

```bash
export GLPI_EXECUTION_MODE=ssh
export GLPI_HOST_ROLE=all
./scripts/glpictl.sh staging deploy check all
```

Quando usar:

- somente quando automação remota for permitida.

Requisitos adicionais:

- par de chaves por ambiente
- chave privada com modo `0600`
- conectividade com hosts de destino

## 7. Comandos principais de deploy

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
```

Finalidade:

- `check`: valida pré-requisitos e políticas
- `apply db`: provisiona/fortalece banco de dados
- `apply app`: provisiona aplicação e stack web
- `apply monitoring`: baseline de exporters
- `apply backup`: baseline de backup
- `post-check`: verificação pós-implantação

## 8. Comandos de TLS

```bash
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

Finalidade:

- alterar modo TLS e reaplicar a role de aplicação com segurança.

## 9. Certificação e prontidão

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Finalidade:

- gerar evidências de certificação e relatórios de prontidão.

## 10. Operações day-2

```bash
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit
./scripts/glpictl.sh <env> ops resume
```

Finalidade:

- ciclo de vida de usuários, ciclo de certificados, auditoria e continuidade com checkpoint.

## 11. Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

Quando usar:

- apenas se a orquestração principal via CLI estiver temporariamente indisponível.
