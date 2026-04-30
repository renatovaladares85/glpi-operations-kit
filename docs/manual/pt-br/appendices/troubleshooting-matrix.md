# Apêndice: Matriz de Troubleshooting

## Falta `ansible-playbook` ou `ansible-inventory`

- Sintoma: precheck falha em ferramenta obrigatória.
- Validação: `command -v ansible-playbook && command -v ansible-inventory`
- Correção: aceitar instalação automática ou executar `sudo apt-get install -y ansible`
- Retomada segura: `./scripts/glpictl.sh <env> deploy check all`

## Caminho de chave SSH inválido ou ausente

- Sintoma: precheck falha na política de chave SSH.
- Validação: `ls -l ~/.ssh/glpi_<env>_ed25519 ~/.ssh/glpi_<env>_ed25519.pub`
- Correção: gerar par de chaves e ajustar `network.ssh.private_key_path`
- Retomada segura: executar check novamente

## Modo da chave SSH inseguro

- Sintoma: falha por permissão de chave.
- Validação: `stat -c '%a' ~/.ssh/glpi_<env>_ed25519`
- Correção: `chmod 600 ~/.ssh/glpi_<env>_ed25519`
- Retomada segura: executar check novamente

## Bloqueio por política em modo seguro

- Sintoma: comando mutável falha com violação de política (TLS/HTTPS/SSO/gate/ordem).
- Validação:
  - `echo "$SECURITY_MODE"` ou `operations.security_mode_default`;
  - flags em `config/<env>.yml`: `security.require_tls`, `security.require_https`, `security.require_sso`, `security.require_promotion_gate`, `security.require_ordered_execution`.
- Correção:
  - cumprir os requisitos de política;
  - ou executar em modo permissivo com justificativa explícita.
- Retomada segura:
  - caminho seguro: corrigir config e repetir comando;
  - caminho permissivo: `SECURITY_MODE=permissive SECURITY_JUSTIFICATION="<motivo>" ./scripts/glpictl.sh ...`.

## Bloqueio por ordem de execução

- Sintoma: `apply app` bloqueado antes de `apply db`.
- Validação: `.runtime/<env>/state/deploy-sequence.yml`
- Correção:
  - em `secure`: seguir sequência `check -> db -> app -> monitoring -> backup -> post-check`;
  - em `permissive`: pode continuar, com warning/evidência automática.
- Retomada segura: executar a próxima etapa exigida

## Arquivos TLS provided ausentes

- Sintoma: `tls install-provided` falha.
- Validação: existência dos arquivos locais e caminhos no config/override
- Correção: informar caminhos válidos e reaplicar comando TLS
- Retomada segura: `tls install-provided`
