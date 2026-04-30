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

## Produção bloqueada por política TLS

- Sintoma: apply de produção falha por modo TLS/HTTPS.
- Validação: `config/production.yml` em `tls.mode`, `security.require_tls_in_production`, `security.require_https_in_production`
- Correção: configurar `tls.mode=provided` e caminhos de certificado válidos
- Retomada segura: `production deploy check all` e repetir apply

## Produção bloqueada por política SSO

- Sintoma: apply de produção falha por política de SSO.
- Validação: `config/production.yml` em `security.sso_enabled`
- Correção: configurar `security.sso_enabled: true`
- Retomada segura: refazer precheck e deploy

## Bloqueio por ordem de execução

- Sintoma: `apply app` bloqueado antes de `apply db`.
- Validação: `.runtime/<env>/state/deploy-sequence.yml`
- Correção: seguir sequência obrigatória `check -> db -> app -> monitoring -> backup -> post-check`
- Retomada segura: executar somente a próxima etapa exigida

## Arquivos TLS provided ausentes

- Sintoma: `tls install-provided` falha.
- Validação: existência dos arquivos locais e caminhos no config/override
- Correção: informar caminhos válidos e reaplicar comando TLS
- Retomada segura: `tls install-provided`
