# Apêndice - Matriz de Troubleshooting (PT-BR)

## Falta `ansible-playbook` ou `ansible-inventory`

- Sintoma: `deploy check` falha em ferramentas obrigatórias.
- Validação: `command -v ansible-playbook && command -v ansible-inventory`
- Correção: aceitar instalação automática no prompt ou executar `sudo apt-get install -y ansible`
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy check all`
  - Exemplo: `./scripts/glpictl.sh staging deploy check all`

## Falta collection Ansible obrigatória

- Sintoma: `ansible-playbook` falha com `couldn't resolve module/action`, por exemplo `community.mysql.mysql_db`.
- Validação: `ansible-doc -t module community.mysql.mysql_db`
- Correção: `ansible-galaxy collection install -r ansible/requirements.yml`
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy check all` antes de tentar `deploy apply`.

## `permission denied` ao executar script

- Sintoma: `./scripts/*.sh` falha por permissão.
- Validação: `ls -l scripts/*.sh`
- Correção: executar `bash scripts/bootstrap-permissions.sh`
- Retomada segura: repetir o comando que falhou.

## Solicitação de senha no `sudo` durante validações locais

- Sintoma: `deploy check` ou outro comando pede senha `sudo`.
- Esclarecimento: essa senha é da conta Linux local da VM/host operacional.
- Não é: senha do MySQL, senha do RDS, nem chave/senha SSH.
- Correção:
  - para ambientes VM (`DATABASE_DEPLOYMENT_MODE=self_hosted`): usar conta com privilégio sudo;
  - para RDS gerenciado (`DATABASE_DEPLOYMENT_MODE=managed`): usar fluxo de validação/app sem operações de host DB Linux.

## Ausência de `config/<env>.env` no precheck

- Sintoma: o precheck falha com item obrigatório informando arquivo de configuração do ambiente ausente.
- Validação: `ls -l config/<env>.env`
  - Exemplo: `ls -l config/staging.env`
- Correção: `cp config/.env.example config/<env>.env` e, em seguida, editar o novo arquivo com os valores do ambiente.
  - Exemplo: `cp config/.env.example config/staging.env`
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy check all`.
  - Exemplo: `./scripts/glpictl.sh staging deploy check all`

## Host role incorreto no fluxo local dual-server

- Sintoma: `deploy apply db` ou `deploy apply app` bloqueado por política de role.
- Validação: conferir `EXECUTION_HOST_ROLE_DEFAULT` em `config/<env>.env` e o modo efetivo no relatório de precheck.
  - Exemplo: `config/staging.env`
- Correção: usar role `db` no host DB e role `app` no host APP quando a execução for local.
- Retomada segura: repetir no host correto com role corrigido.

## `deploy apply db` bloqueado com `DATABASE_DEPLOYMENT_MODE=managed`

- Sintoma: execução falha informando que `deploy apply db` não é suportado em modo gerenciado.
- Causa: em RDS/DB gerenciado não existe host Linux DB para provisionamento MariaDB via role `db`.
- Correção:
  - manter `deploy apply app|monitoring|backup`;
  - validar conectividade APP->RDS via TCP (`mysql --protocol=TCP --host <rds-endpoint> ...`).
- Retomada segura: repetir com alvo compatível (`app`, `monitoring`, `backup`).

## Banco managed incompatível com a versão do GLPI

- Sintoma: `deploy check`, `deploy prepare` ou `deploy apply app` bloqueia com `managed-db-version-compatible` ou `Unsupported database server`.
- Causa: a versão configurada do GLPI exige versão mínima do banco:
  - GLPI 11: MySQL >= 8.0 ou MariaDB >= 10.6.
  - GLPI 10: MySQL >= 5.7 ou MariaDB >= 10.2.
- Validação:
  - `mysql --protocol=TCP --host <db-host> --port <db-port> --user <glpi-db-user> --database <db-name> --password --batch --skip-column-names --execute "SELECT VERSION(), @@version_comment;"`
  - Exemplo: `mysql --protocol=TCP --host 192.0.2.20 --port 3306 --user nehemiah_glpi --database glpi --password --batch --skip-column-names --execute "SELECT VERSION(), @@version_comment;"`
- Correção:
  - pedir upgrade do banco managed para MariaDB >= 10.6 ou MySQL >= 8.0 quando usar GLPI 11;
  - ou ajustar `GLPI_VERSION` para uma versão GLPI 10.x compatível quando o banco permanecer em MariaDB 10.5;
  - manter `DATABASE_COMPATIBILITY_POLICY=block` como padrão seguro.
- Exceção temporária em não produção:
  - usar `DATABASE_COMPATIBILITY_POLICY=defer` somente com `ENVIRONMENT_STAGE` não produtivo, `SECURITY_MODE=permissive`, `DATABASE_COMPATIBILITY_JUSTIFICATION` preenchido e confirmação explícita;
  - nesse modo o kit instala a camada APP, mas pula bootstrap/schema GLPI e smoke checks web que dependem de schema válido;
  - não usar `warn/defer` em produção sem aprovação externa explícita e `DATABASE_UNSUPPORTED_PROD_OVERRIDE=true`.
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy check all` e só depois `deploy apply app`.
- Após upgrade do banco: repetir `./scripts/glpictl.sh <env> deploy apply app` e `./scripts/glpictl.sh <env> deploy post-check all`.

## Conexão MySQL cai em `reading initial communication packet`

- Sintoma: `mysql -h <db-host> -P <port> ...` retorna `Lost connection to MySQL server at 'reading initial communication packet'`.
- Causa provável: porta errada, serviço na porta não é MySQL/MariaDB, firewall/proxy encerra o handshake, ou endpoint aceita TCP mas não entrega banner MySQL.
- Observação: `ping` valida apenas ICMP; não comprova que a porta fala protocolo MySQL.
- Validação:
  - `nc -vz <db-host> <db-port>`
  - `mysql --protocol=TCP --host <db-host> --port <db-port> --user <glpi-db-user> --database <db-name> --password --connect-timeout=7 --execute "SELECT 1;"`
- Correção:
  - confirmar com a equipe de banco a porta MySQL/MariaDB real, normalmente `3306`;
  - liberar a origem do host APP no firewall/security group/allowlist;
  - confirmar que o endpoint informado é do banco, não de RDP ou outro serviço.

## Caminho de chave SSH inválido em `EXECUTION_MODE=ssh`

- Sintoma: precheck falha na política de chave SSH.
- Validação: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
  - Exemplo: `ls -l ~/.ssh/glpi_staging_ed25519 ~/.ssh/glpi_staging_ed25519.pub`
- Correção: gerar par de chaves e ajustar `NETWORK_SSH_PRIVATE_KEY_PATH`.
- Retomada segura: repetir `deploy check`.

## Modo da chave SSH inseguro

- Sintoma: validação de permissão da chave privada falha.
- Validação: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
  - Exemplo: `stat -c '%a' ~/.ssh/glpi_staging_ed25519`
- Correção: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
  - Exemplo: `chmod 600 ~/.ssh/glpi_staging_ed25519`
- Retomada segura: repetir `deploy check`.

## Bloqueio por política em modo `secure`

- Sintoma: comando mutável encerra por violação de política.
- Validação:
  - modo efetivo (`SECURITY_MODE` ou `OPERATIONS_SECURITY_MODE_DEFAULT`)
  - flags de política em `config/<env>.env` (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`)
  - Exemplo: `config/staging.env`
- Correção: cumprir requisitos de política ou executar em modo permissivo com justificativa explícita.
- Retomada segura:
  - caminho seguro: corrigir configuração e repetir;
  - caminho permissivo: repetir com `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="<motivo>"`.
  - Exemplo: `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="risco-aceito-para-manutencao"`

## Bloqueio por ordem de execução

- Sintoma: `apply app` bloqueado antes de `apply db`.
- Validação: `.runtime/<env>/state/deploy-sequence.yml`
  - Exemplo: `.runtime/staging/state/deploy-sequence.yml`
- Correção:
  - modo seguro: seguir `check -> apply db -> apply app -> monitoring -> backup -> post-check`
  - modo permissivo: continuar com warning e evidência
- Retomada segura: executar somente a próxima etapa necessária.

## Conflito de servidor web (política de engine único)

- Sintoma: `deploy check` ou `deploy apply app` é bloqueado pela política `single-web-server`.
- Validação:
  - engine configurado: `grep '^WEB_SERVER_TYPE=' config/<env>.env`
  - Exemplo: `grep '^WEB_SERVER_TYPE=' config/staging.env`
  - serviços ativos: `systemctl is-active nginx apache2 lighttpd`
- Correção:
  - manter apenas um engine ativo, correspondente ao `WEB_SERVER_TYPE`;
  - parar/desabilitar engines conflitantes no host.
- Retomada segura:
  - repetir `./scripts/glpictl.sh <env> deploy check all` e depois `deploy apply app`.
  - Exemplo: `./scripts/glpictl.sh staging deploy check all`

## Falha em `tls install-provided`

- Sintoma: ação TLS falha.
- Validação: existência dos arquivos em `TLS_PROVIDED_LOCAL_CERT_PATH` e `TLS_PROVIDED_LOCAL_KEY_PATH`.
- Correção: ajustar caminhos válidos e repetir ação TLS.
- Retomada segura: `./scripts/glpictl.sh <env> tls install-provided`.
  - Exemplo: `./scripts/glpictl.sh staging tls install-provided`

## Apache não escuta em HTTPS ou exibe o vhost padrão no Rocky

- Sintoma: porta 443 ausente, certificado incorreto ou página padrão do Apache.
- Validação: `sudo apachectl configtest; sudo httpd -M | grep ssl; sudo httpd -S; sudo ss -lntp | grep ':443'`.
- Causa provável: `WEB_SERVER_TYPE`/`TLS_MODE` incorretos, override `GLPI_APP_PACKAGES`
  sem `mod_ssl`, ou `/etc/httpd/conf.d/ssl.conf` recriado após atualização do pacote.
- Correção: ajustar o `.env`, deixar `GLPI_APP_PACKAGES` vazio ou incluir todos os
  pacotes obrigatórios, e repetir `tls apply` ou `deploy apply app`.
- Não remova `/etc/httpd/conf.modules.d/00-ssl.conf`; ele carrega o módulo SSL.

## Falta de `bcmath` durante a instalação do GLPI (requisito de QR Code)

- Sintoma: instalador do GLPI informa falta de `bcmath` ou o `deploy apply app` falha na validação de extensão PHP.
- Validação: `php -m | grep -i '^bcmath$'`
- Correção:
  - executar `./scripts/glpictl.sh <env> deploy check all` e aceitar a auto-instalação; ou
  - Exemplo: `./scripts/glpictl.sh staging deploy check all`
  - remediação manual: `sudo apt-get update && sudo apt-get install -y php-bcmath`
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy apply app`.
  - Exemplo: `./scripts/glpictl.sh staging deploy apply app`

## Host APP sem cliente MariaDB para testes de conectividade

- Sintoma: validação da aplicação falha com `mysql: command not found` ou teste APP->DB `SELECT 1` falha.
- Validação:
  - `command -v mysql`
  - `mysql --protocol=TCP --host <db-host> --port <db-port> --user <glpi-db-user> --password --execute "SELECT 1;"`
  - Exemplo: `mysql --protocol=TCP --host 192.0.2.20 --port 3306 --user nehemiah_glpi --password --execute "SELECT 1;"`
- Correção:
  - instalar cliente: `sudo apt-get update && sudo apt-get install -y mariadb-client`
  - confirmar usuário/senha do banco e caminho de rede a partir do host APP.
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy apply app`.
  - Exemplo: `./scripts/glpictl.sh staging deploy apply app`

## `/install/install.php` retorna 404 ou fluxo de instalação quebra

- Sintoma: a página raiz abre, mas o caminho do instalador retorna 404 ou interrompe o fluxo.
- Validação:
  - `curl -I -H "Host: <glpi-domain>" http://127.0.0.1:<http-port>/`
  - Exemplo: `curl -I -H "Host: glpi-staging.example.internal" http://127.0.0.1:80/`
  - `curl -I -H "Host: <glpi-domain>" http://127.0.0.1:<http-port>/install/install.php`
  - Exemplo: `curl -I -H "Host: glpi-staging.example.internal" http://127.0.0.1:80/install/install.php`
- Correção:
  - repetir `./scripts/glpictl.sh <env> deploy apply app` para regenerar o template do engine selecionado;
  - Exemplo: `./scripts/glpictl.sh staging deploy apply app`
  - para nginx, confirmar rota de compatibilidade e allowlist de PHP no `nginx-glpi.conf`.
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy post-check app`.
  - Exemplo: `./scripts/glpictl.sh staging deploy post-check app`

## `render_product_config.py` com NameError (`values` ou `web_server_type`)

- Sintoma: `deploy check` falha com erros como `NameError: name 'values' is not defined` ou `NameError: name 'web_server_type' is not defined`.
- Validação:
  - `python3 scripts/lib/render_product_config.py --config config/<env>.env --mode public-runtime`
  - Exemplo: `python3 scripts/lib/render_product_config.py --config config/staging.env --mode public-runtime`
  - `python3 scripts/lib/render_product_config.py --config config/<env>.env --mode inventory`
  - Exemplo: `python3 scripts/lib/render_product_config.py --config config/staging.env --mode inventory`
- Correção:
  - atualizar o repositório local para o commit mais recente (`git pull`) com o ajuste de escopo do renderer;
  - garantir que `WEB_SERVER_TYPE` exista em `config/<env>.env`.
  - Exemplo: `config/staging.env`
- Retomada segura:
  - repetir `./scripts/glpictl.sh <env> deploy check all`.
  - Exemplo: `./scripts/glpictl.sh staging deploy check all`
