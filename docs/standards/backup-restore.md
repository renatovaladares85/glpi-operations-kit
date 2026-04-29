# Backup and Restore Standard

## Backup minimo

- dump do banco
- copia de `/etc/glpi`
- copia de `/var/lib/glpi/files`
- copia de `/var/lib/glpi/plugins`

## Retencao inicial

- `staging`: 14 dias
- `production`: 30 dias

## Restore

- Documentar procedimento
- Testar restore periodicamente
- Nao restaurar backup em base parcialmente migrada

## Regras para agentes

- Ao mudar backup, documentar impacto operacional
- Ao mudar restore, documentar risco e validacao
