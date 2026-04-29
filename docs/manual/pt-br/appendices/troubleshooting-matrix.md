# Apendice: Troubleshooting

## Permission denied em scripts

- Check: `ls -l scripts/*.sh`
- Fix: `bash scripts/bootstrap-permissions.sh`

## Operacao bloqueada por lock

- Causa: execucao concorrente de `ops-maintenance.sh`
- Check: `.runtime/<env>/state/.ops-maintenance.lock`
- Acao: validar se nao existe processo ativo antes de remover lock

## Falha de certificado

- Check: `bash scripts/ops-maintenance.sh cert staging check`
- Acao: aplicar novo certificado com `cert staging apply`

## Falha em usuario DB

- Check: revisar `.runtime/<env>/logs/*.log` e `.summary.yml`
- Acao: rerun com `users staging disable db` ou `users staging add db`

## Continuar apos falha

- Comando: `bash scripts/ops-maintenance.sh resume staging`
