# 05 - Backup, Restore e Teste de Restore

Um backup só é confiável quando o restore já foi testado.

A automação atual cobre rotinas de backup para:

- dump de banco;
- arquivos do GLPI;
- configuração do GLPI;
- plugins.

Aplicar baseline de backup:

```bash
./scripts/glpictl.sh staging deploy apply backup
```

Também proteja manualmente (fora do Git):

- cópias de arquivo de ambiente para recuperação;
- segredos runtime;
- materiais de certificado/chave TLS;
- dependências de infraestrutura necessárias para rebuild.

Nesta fase, restore é fluxo manual orientado, com suporte de rollback do repositório focado em metadados runtime/snapshots de domínio.

Antes de restore em produção:

1. abrir janela de manutenção;
2. confirmar backup recente;
3. testar restore em staging ou ambiente isolado;
4. validar acesso da aplicação após restore.

Validação pós-restore:

```bash
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging audit check
```

Erro comum e ação rápida:

- erro: restore executado sem conjunto de backup testado
- ação: interromper, recompor backup e testar restore em staging primeiro

Próximo passo:

- [Padrão de Backup e Restore](../../../standards/backup-restore.md)
- [Checagens Operacionais](../appendices/operational-checks.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
