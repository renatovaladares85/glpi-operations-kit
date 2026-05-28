# 05 - Backup, Restore e Teste de Restore

Este capítulo cobre backup e restore de forma operacional, sem fixar governança local de cada cliente. As regras de processo devem seguir a política do seu projeto.

No kit, existem dois fluxos diferentes e complementares.

## Fluxo 1: baseline operacional do ambiente (`glpictl`)

Quando você executa o baseline de backup, o kit prepara a rotina de backup no ambiente Linux.

```bash
./scripts/glpictl.sh <environment> deploy apply backup
```

Na prática, esse fluxo configura:

- diretórios de backup em `BACKUP_BASE_DIR` (db, files, config e plugins);
- script de dump de banco no host DB;
- script de backup de arquivos/config/plugins no host APP;
- agendamento em `cron`;
- retenção baseada em `BACKUP_RETENTION_DAYS`.

Onde ajustar:

- `BACKUP_BASE_DIR`
- `BACKUP_RETENTION_DAYS`

Essas chaves ficam em `config/<environment>.env`. O significado de cada campo está em [Guia de Preenchimento do Ambiente](../appendices/configuration-field-guide.md).

## Fluxo 2: backup/restore transferível (`backup-app.sh`)

Esse fluxo é manual e orientado para gerar artefato de migração/recuperação em formato único.

Comandos-base:

```bash
sudo ./scripts/backup-app.sh backup --target <app|db|all> [opções]
sudo ./scripts/backup-app.sh restore --target <app|db|all> --artifact <arquivo> [opções]
```

O `--target` define o escopo:

- `app`: arquivos e configuração da aplicação;
- `db`: dump e restore do banco;
- `all`: app + db.

### Como os parâmetros de banco funcionam

No backup de `db` ou `all`, você pode informar parâmetros explicitamente (`--db-host`, `--db-port`, `--db-user`, `--db-password`, `--db-name`).

Se você não informar host/usuário/base no backup, o script tenta descobrir em `config_db.php` do GLPI. Se ainda faltar dado obrigatório, ele interrompe e informa qual parâmetro precisa ser passado.

No restore de `db` ou `all`, `--db-host`, `--db-user` e `--db-name` são exigidos. A senha pode ser passada com `--db-password` ou digitada em prompt seguro durante a execução.

### Controles importantes

- `--artifact`: arquivo de entrada/saída do artefato.
- `--output-dir` e `--artifact-name`: controlam onde e como salvar o backup.
- `--exclude-app`: exclui áreas do app por CSV (`core/`, `config/`, `var/`, `log/`, `plugins/`, `marketplace/` ou caminho absoluto).
- `--exclude-db-tables-data`: exclui somente dados de tabelas específicas no dump.
- `--encrypt` e `--passphrase-file`: criptografam o artefato final.
- `--force`: no restore de app, permite sobrescrever destino já populado.
- `--db-recreate`: no restore de DB, recria a base antes de importar.

Atenção: `--db-recreate` remove a base atual antes do import. Confirme o alvo antes de executar.

Atenção: `--force` pode sobrescrever conteúdo existente no restore de app.

### Exemplos práticos

Backup completo criptografado:

```bash
sudo ./scripts/backup-app.sh backup --target all --output-dir /var/backups/glpi --encrypt
```

Backup apenas de banco com parâmetros explícitos:

```bash
sudo ./scripts/backup-app.sh backup --target db --db-host 127.0.0.1 --db-port 3306 --db-user glpi_backup --db-name glpi
```

Restore de banco recriando a base:

```bash
sudo ./scripts/backup-app.sh restore --target db --artifact /var/backups/glpi/glpi-transfer.tar.gz --db-host 127.0.0.1 --db-port 3306 --db-user glpi_restore --db-name glpi --db-recreate
```

Restore completo (app + db):

```bash
sudo ./scripts/backup-app.sh restore --target all --artifact /var/backups/glpi/glpi-transfer.tar.gz --force --db-host 127.0.0.1 --db-port 3306 --db-user glpi_restore --db-name glpi --db-recreate
```

## Validação pós-restore

Depois do restore, valide serviço, aplicação e conectividade:

```bash
./scripts/glpictl.sh <environment> deploy post-check all
./scripts/glpictl.sh <environment> audit check
```

Se precisar, valide também no host:

```bash
nginx -t
systemctl status nginx
systemctl status php8.3-fpm
mysql --version
```

## Erros comuns e ação rápida

- erro: artefato inválido ou checksum divergente
- ação: gerar novo artefato e validar integridade antes do restore

- erro: restore DB sem parâmetros obrigatórios
- ação: informar `--db-host`, `--db-user`, `--db-name` e repetir

- erro: base já contém tabelas
- ação: usar `--db-recreate` somente quando a substituição da base for intencional

## Próximo passo

- [Padrão de Backup e Restore](../../../standards/backup-restore.md)
- [Referência de Comandos](../appendices/command-reference.md)
- [Checagens Operacionais](../appendices/operational-checks.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
