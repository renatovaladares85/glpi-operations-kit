# Security Standard

## Regras base

- Nao versionar segredos.
- Manter diretorios sensiveis fora da web root.
- Usar menor privilegio para SSH, banco e arquivos.
- Restringir acesso ao banco apenas a hosts autorizados.
- Preservar TLS e permissoes restritas.

## Layout sensivel do GLPI

- codigo: `/usr/share/glpi`
- config: `/etc/glpi`
- dados: `/var/lib/glpi/files`
- plugins: `/var/lib/glpi/plugins`
- logs: `/var/log/glpi`

## LGPD

- Evitar dados sensiveis em logs e exemplos.
- Restringir acesso a anexos e backups.
- Criptografar backups quando aplicavel.

## Regras para agentes

- Ao tocar secrets, consultar este arquivo primeiro.
- Se surgir nova regra critica, promover para `mandatory-rules.md`.
