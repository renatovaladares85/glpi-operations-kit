# Apêndice: Matriz de Troubleshooting

## Falta `ansible-playbook` ou `ansible-inventory`

- Sintoma: precheck falha em ferramenta obrigatória.
- Validação: `command -v ansible-playbook && command -v ansible-inventory`
- Correção: aceitar instalação automática ou executar `sudo apt-get install -y ansible`
- Retomada segura: `./scripts/glpictl.sh <env> deploy check all`

## `permission denied` ao executar script

- Sintoma: `./scripts/<script>.sh` falha por permissão.
- Validação: `ls -l scripts/*.sh`
- Correção: `bash scripts/bootstrap-permissions.sh`
- Retomada segura: repetir o comando original

## Inconsistência entre `GLPI_HOST_ROLE` e comando no modo local

- Sintoma: `deploy apply db` ou `deploy apply app` bloqueado por role.
- Validação: `echo "$GLPI_EXECUTION_MODE" && echo "$GLPI_HOST_ROLE"`
- Correção:
  - para `apply db`: usar `GLPI_HOST_ROLE=db|all`
  - para `apply app|monitoring|backup`: usar `GLPI_HOST_ROLE=app|all`
- Retomada segura: rodar comando no host correto

## Caminho de chave SSH inválido (modo `ssh`)

- Sintoma: precheck falha na política de SSH.
- Validação: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
- Correção: gerar par de chaves e ajustar `network.ssh.private_key_path`
- Retomada segura: executar `deploy check all`

## Modo da chave SSH inseguro (modo `ssh`)

- Sintoma: chave privada sem `0600`.
- Validação: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
- Correção: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
- Retomada segura: executar `deploy check all`

## Bloqueio por política em modo `secure`

- Sintoma: comando mutável falha por política (TLS/HTTPS/SSO/gate/ordem).
- Validação:
  - `echo "$SECURITY_MODE"`
  - revisar flags em `config/<env>.yml`
- Correção:
  - cumprir requisitos de política
  - ou usar `SECURITY_MODE=permissive` com justificativa
- Retomada segura:
  - caminho recomendado: corrigir política e repetir
  - caminho permissivo: registrar justificativa e executar novamente

## Falha em `tls install-provided`

- Sintoma: comando TLS falha.
- Validação: existência dos caminhos locais de cert/key
- Correção: informar caminhos válidos e repetir a ação
- Retomada segura: `./scripts/glpictl.sh <env> tls install-provided`
