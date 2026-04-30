# Apêndice - Referência de Comandos (PT-BR)

Este apêndice complementa o runbook principal com comandos diretos e finalidade operacional ampliada. A sintaxe permanece a mesma; o que muda é o ambiente e os valores de `config/<environment>.env`.

## Preparar ferramentas do host

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

Use quando o host executor for novo ou estiver sem dependências. Esse passo instala o mínimo necessário para scripts, renderização de runtime e execução de Ansible.

## Preparar permissões dos scripts

```bash
bash scripts/bootstrap-permissions.sh
```

Execute antes do primeiro comando de deploy em uma sessão nova de operador. Esse script corrige permissões de execução, valida `sudo`, valida grupo `glpiops` e ajusta permissões de `.runtime`.

## Criar e editar a configuração do ambiente

```bash
cp config/product.env config/staging.env
```

Esse comando cria o baseline do ambiente. Os scripts carregam esse arquivo automaticamente, então o uso de `export` manual não é obrigatório no fluxo normal.

## Comandos principais de implantação

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
```

`deploy check all` funciona como gate operacional antes de mudanças mutáveis: valida ferramentas, permissões, políticas, inventário, consistência de host role e baseline de runtime. `deploy apply db` cuida de pacotes MariaDB, hardening, base, usuário, grants e restrições de origem. `deploy apply app` configura layout do GLPI, Nginx, PHP-FPM e integração app-banco. `deploy apply monitoring` aplica exporters e baseline de observabilidade. `deploy apply backup` aplica baseline de backup e retenção. `deploy post-check all` confirma a validade dos serviços após as etapas mutáveis.

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

Esse fluxo foi desenhado para redes corporativas que exigem login interativo com senha e 2FA em cada host.

## Modo SSH opcional

```bash
GLPI_EXECUTION_MODE=ssh ./scripts/glpictl.sh staging deploy check all
```

Use somente quando a política permitir orquestração remota a partir de um único host. No modo ssh, a política de chave privada (`0600`) e a conectividade com os alvos viram checagens obrigatórias.

## Comandos de ciclo de vida TLS

```bash
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

`disable` força HTTP, `self-signed` cria/aplica certificado de teste, `install-provided` instala certificado/chave reais e `reload` valida e recarrega a configuração TLS efetiva no Nginx.

## Certificação, prontidão e evidências

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Esses comandos geram evidências de certificação e prontidão em `.runtime/<env>/evidence` e `.runtime/<env>/state`.

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

Esses comandos cobrem ciclo de vida de usuários, ciclo de vida de certificados, auditoria operacional e retomada de manutenção interrompida.

## Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```

Use o fallback manual somente quando a orquestração central da CLI estiver temporariamente indisponível.
