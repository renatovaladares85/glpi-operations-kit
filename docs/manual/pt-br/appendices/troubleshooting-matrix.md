# Apêndice - Matriz de Troubleshooting (PT-BR)

## Falta `ansible-playbook` ou `ansible-inventory`

- Sintoma: `deploy check` falha em ferramentas obrigatórias.
- Validação: `command -v ansible-playbook && command -v ansible-inventory`
- Correção: aceitar instalação automática no prompt ou executar `sudo apt-get install -y ansible`
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy check all`

## `permission denied` ao executar script

- Sintoma: `./scripts/*.sh` falha por permissão.
- Validação: `ls -l scripts/*.sh`
- Correção: executar `bash scripts/bootstrap-permissions.sh`
- Retomada segura: repetir o comando que falhou.

## Ausência de `config/<env>.env` no precheck

- Sintoma: o precheck falha com item obrigatório informando arquivo de configuração do ambiente ausente.
- Validação: `ls -l config/<env>.env`
- Correção: `cp config/product.env config/<env>.env` e, em seguida, editar o novo arquivo com os valores do ambiente.
- Retomada segura: repetir `./scripts/glpictl.sh <env> deploy check all`.

## Host role incorreto no fluxo local dual-server

- Sintoma: `deploy apply db` ou `deploy apply app` bloqueado por política de role.
- Validação: conferir `EXECUTION_HOST_ROLE_DEFAULT` em `config/<env>.env` e o modo efetivo no relatório de precheck.
- Correção: usar role `db` no host DB e role `app` no host APP quando a execução for local.
- Retomada segura: repetir no host correto com role corrigido.

## Caminho de chave SSH inválido em `EXECUTION_MODE=ssh`

- Sintoma: precheck falha na política de chave SSH.
- Validação: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
- Correção: gerar par de chaves e ajustar `NETWORK_SSH_PRIVATE_KEY_PATH`.
- Retomada segura: repetir `deploy check`.

## Modo da chave SSH inseguro

- Sintoma: validação de permissão da chave privada falha.
- Validação: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
- Correção: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
- Retomada segura: repetir `deploy check`.

## Bloqueio por política em modo `secure`

- Sintoma: comando mutável encerra por violação de política.
- Validação:
  - modo efetivo (`SECURITY_MODE` ou `OPERATIONS_SECURITY_MODE_DEFAULT`)
  - flags de política em `config/<env>.env` (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_SSO`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`)
- Correção: cumprir requisitos de política ou executar em modo permissivo com justificativa explícita.
- Retomada segura:
  - caminho seguro: corrigir configuração e repetir;
  - caminho permissivo: repetir com `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="<motivo>"`.

## Bloqueio por ordem de execução

- Sintoma: `apply app` bloqueado antes de `apply db`.
- Validação: `.runtime/<env>/state/deploy-sequence.yml`
- Correção:
  - modo seguro: seguir `check -> apply db -> apply app -> monitoring -> backup -> post-check`
  - modo permissivo: continuar com warning e evidência
- Retomada segura: executar somente a próxima etapa necessária.

## Falha em `tls install-provided`

- Sintoma: ação TLS falha.
- Validação: existência dos arquivos em `TLS_PROVIDED_LOCAL_CERT_PATH` e `TLS_PROVIDED_LOCAL_KEY_PATH`.
- Correção: ajustar caminhos válidos e repetir ação TLS.
- Retomada segura: `./scripts/glpictl.sh <env> tls install-provided`.

## `render_product_config.py` com NameError (`values` ou `web_server_type`)

- Sintoma: `deploy check` falha com erros como `NameError: name 'values' is not defined` ou `NameError: name 'web_server_type' is not defined`.
- Validação:
  - `python3 scripts/lib/render_product_config.py --config config/<env>.env --mode public-runtime`
  - `python3 scripts/lib/render_product_config.py --config config/<env>.env --mode inventory`
- Correção:
  - atualizar o repositório local para o commit mais recente (`git pull`) com o ajuste de escopo do renderer;
  - garantir que `WEB_SERVER_TYPE` exista em `config/<env>.env`.
- Retomada segura:
  - repetir `./scripts/glpictl.sh <env> deploy check all`.
