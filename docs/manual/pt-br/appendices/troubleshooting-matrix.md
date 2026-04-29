# Apêndice: Matriz de Troubleshooting

## Falta `ansible-playbook` ou `ansible-inventory`

- Sintoma: pre-flight acusa comando obrigatório ausente e pergunta se instala.
- Causa provável: pacote Ansible ausente.
- Verificação: `command -v ansible-playbook && command -v ansible-inventory`
- Correção: aceitar instalação pelo script ou `sudo apt-get update && sudo apt-get install -y ansible`

## Chave SSH inválida

- Sintoma: prompt rejeita caminho da chave.
- Verificação: `ls -l <path-to-key>`
- Correção: usar chave real com `chmod 600`.

## Host app/db inválido

- Sintoma: prompt rejeita host.
- Causa provável: hostname/IP malformado.
- Correção: informar hostname válido ou IPv4 válido.

## Falha de acesso SSH entre hosts

- Verificação: `ssh -i <key> <user>@<host> "hostname && id"`
- Correção: ajustar usuário/chave/rede e garantir sudo.

## Falha `nginx -t`

- Verificação: `sudo nginx -t`
- Correção: revisar TLS runtime e reaplicar `./scripts/deploy-staging.sh apply app`.

## Falha `php-fpm8.3 -t`

- Verificação: `sudo php-fpm8.3 -t`
- Correção: revisar variáveis runtime e reaplicar role `app`.
