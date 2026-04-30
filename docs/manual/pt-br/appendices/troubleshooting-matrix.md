# Apendice: Troubleshooting

## Permission denied em scripts

- Check: `ls -l scripts/*.sh`
- Fix: `bash scripts/bootstrap-permissions.sh`

## Operacao bloqueada por lock

- Causa: execucao concorrente de `ops-maintenance.sh`
- Check: `.runtime/<env>/state/.ops-maintenance.lock`
- Acao: validar se nao existe processo ativo antes de remover lock

## Falha de certificado

- Check: `./scripts/glpictl.sh staging ops cert check`
- Acao: aplicar novo certificado com `./scripts/glpictl.sh staging ops cert apply`

## Caminho invalido da chave SSH no config do produto

- Check: `ls -l <caminho-da-chave>`
- Acao: corrigir `config/<environment>.yml` e garantir `chmod 600 <caminho-da-chave>`

## Host app/db invalido no config do produto

- Check: validar sintaxe do hostname ou IP informado
- Acao: corrigir `config/<environment>.yml` e executar novamente o comando

## Falha em usuario DB

- Check: revisar `.runtime/<env>/logs/*.log` e `.summary.yml`
- Acao: rerun com `./scripts/glpictl.sh staging ops users disable db` ou `./scripts/glpictl.sh staging ops users add db`

## Continuar apos falha

- Comando: `./scripts/glpictl.sh staging ops resume`
