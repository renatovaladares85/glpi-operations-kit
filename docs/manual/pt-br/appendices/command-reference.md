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
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
```

`deploy check all` valida ferramentas, permissões, política, inventário, host role e baseline de runtime antes de mudança mutável. No fluxo local do host APP, também valida `mariadb-client` e pode auto-corrigir `php-bcmath` para baseline GLPI 11. `deploy apply db` aplica MariaDB e provisionamento de base/usuário/grants. `deploy apply app` aplica layout GLPI, engine web selecionado (`nginx`, `apache` ou `lighttpd`), PHP-FPM, validações obrigatórias de extensão PHP e teste de conectividade APP->DB (`SELECT 1`). `deploy apply monitoring` aplica exporters e baseline de observabilidade. `deploy apply backup` aplica baseline de backup e retenção. `deploy post-check all` confirma validade operacional após as etapas mutáveis e imprime resumo explícito do engine web.

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

Esses comandos validam o contrato do engine selecionado: acesso raiz, rota de compatibilidade do instalador (`/install/install.php` quando esperada), assets `.js/.css` detectados na página e bloqueio de caminhos sensíveis (`/config`, `/files`, `/vendor`, `.php` arbitrário fora do roteador).

## Comandos de ciclo de vida TLS

```bash
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

## Certificação, prontidão e evidências

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

## Operações day-2

```bash
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit check
./scripts/glpictl.sh <env> ops resume
```

## Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```
