# Manual do Usuário GLPI SoEnergy

## 1. Visão geral

Este manual é um runbook completo para operadores instalarem e validarem o GLPI em staging, com ou sem scripts do repositório.

Ele cobre:

- fluxo guiado automatizado (scripts + Ansible)
- fluxo manual de contingência (comando a comando no Ubuntu)
- modo servidor único (app + banco no mesmo host)
- modo dois servidores (host app + host db)
- execução entre hosts via SSH (app para db e db para app)

O que está implementado é documentado como executável. Capacidades não implementadas ficam separadas.

## 2. Arquitetura e modos

Topologias suportadas:

- servidor único: um host Ubuntu com roles de app e db
- dois servidores: um host Ubuntu para app e outro para db

Modos TLS suportados:

- `none` (somente HTTP)
- `self_signed`
- `provided`

Layout seguro do GLPI:

- código: `/usr/share/glpi`
- configuração: `/etc/glpi`
- dados: `/var/lib/glpi/files`
- plugins: `/var/lib/glpi/plugins`
- logs: `/var/log/glpi`

## 3. Pré-requisitos

Política de origem de execução:

- executar a partir de host alvo (app ou db)
- bastion não é obrigatório

Ferramentas obrigatórias no host de execução:

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`

Opcional, mas recomendado:

- `ssh`

Acessos obrigatórios:

- conectividade SSH entre host de execução e host remoto na topologia dual
- privilégio sudo nos hosts alvo
- chave privada SSH válida disponível no host de execução

## 4. Fluxo guiado automatizado (Trilha A)

Ponto de entrada principal:

- `scripts/deploy-staging.sh`

O script inicia com pre-flight. Se faltar comando obrigatório, ele pergunta se pode instalar no Ubuntu. Se falhar, exibe remediação manual exata e bloqueia a execução.

### 4.1 Passo a passo

1. Rodar pre-flight e coleta de runtime:

```bash
./scripts/deploy-staging.sh check
```

2. Implantar banco:

```bash
./scripts/deploy-staging.sh apply db
```

3. Implantar aplicação:

```bash
./scripts/deploy-staging.sh apply app
```

4. Implantar monitoração:

```bash
./scripts/deploy-staging.sh apply monitoring
```

5. Implantar backup:

```bash
./scripts/deploy-staging.sh apply backup
```

Opcional (implantação combinada):

```bash
./scripts/deploy-staging.sh apply all
```

### 4.2 Entradas de runtime (obrigatórias)

O script solicita e valida:

- IP/hostname do host app
- IP/hostname do host db
- usuário SSH
- caminho da chave SSH privada
- versão do GLPI
- modo TLS
- caminhos de certificado/chave para `provided`
- nome do banco, usuário do banco, senha do banco
- senha root do MariaDB
- usuário/senha do exporter de monitoração

Arquivos de runtime são gravados em `.runtime/staging/`.

## 5. Fluxo manual de contingência (Trilha B)

Use este fluxo quando scripts não estiverem disponíveis ou quando auto-instalação falhar.

### 5.1 Instalar dependências no Ubuntu (host de execução)

```bash
sudo apt-get update
sudo apt-get install -y bash git openssh-client ansible
```

Validar:

```bash
command -v bash
command -v git
command -v ansible-playbook
command -v ansible-inventory
command -v ssh
```

### 5.2 Criar arquivos de runtime manualmente

Criar diretório:

```bash
mkdir -p .runtime/staging
chmod 700 .runtime/staging
```

Criar:

- `.runtime/staging/inventory.runtime.yml`
- `.runtime/staging/app.runtime.yml`
- `.runtime/staging/db.secrets.yml`
- `.runtime/staging/monitoring.secrets.yml`

Proteger segredos:

```bash
chmod 600 .runtime/staging/*.secrets.yml
```

### 5.3 Aplicar roles com Ansible (manual)

```bash
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/app.runtime.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags monitoring --extra-vars @.runtime/staging/monitoring.secrets.yml --extra-vars @.runtime/staging/db.secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags backup --extra-vars @.runtime/staging/app.runtime.yml
```

## 6. Operação em servidor único e dual

### 6.1 Modo servidor único

Defina app host e db host com o mesmo valor no inventory runtime.

```bash
./scripts/deploy-staging.sh apply all
```

### 6.2 Modo dual a partir do host app

Execute no host app e informe:

- app host = IP/FQDN do próprio host app
- db host = IP/FQDN do host db remoto
- usuário/chave SSH com sudo em ambos

### 6.3 Modo dual a partir do host db

Execute no host db e informe:

- db host = IP/FQDN do próprio host db
- app host = IP/FQDN do host app remoto
- usuário/chave SSH com sudo em ambos

## 7. Operações de TLS

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```

`install-provided` solicita caminhos locais do certificado/chave e reaplica role de app com segurança.

## 8. Validação e aceite

Checks mínimos:

- pre-flight sem falhas obrigatórias pendentes
- parsing do runtime inventory
- conclusão das roles app e db
- `nginx -t` válido no host app
- `php-fpm8.3 -t` válido no host app
- página do instalador GLPI abrindo
- acesso ao banco com credenciais runtime
- artefatos de monitoração e backup presentes

## 9. Troubleshooting e recuperação

Use o apêndice de troubleshooting para:

- dependências ausentes e falha de instalação
- falhas de conectividade/autenticação SSH
- falhas de validação de entradas runtime
- falhas de validação Nginx/PHP-FPM/MariaDB
- sequência segura de reexecução parcial

## 10. Documentação relacionada

- [Índice multilíngua](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual/README.md)
- [Índice de apêndices PT-BR](/D:/Stefanini/SoEnergy/glpi-soenergy/docs/manual/pt-br/appendices/index.md)
