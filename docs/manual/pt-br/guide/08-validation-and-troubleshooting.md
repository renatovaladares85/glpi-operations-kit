# 08 - Validação e Troubleshooting

Depois de cada etapa importante, valide primeiro. Não declare sucesso apenas porque o comando terminou.

Fluxo central de validação:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging audit check
bash scripts/release-readiness.sh staging
```

Validação em nível de serviço:

```bash
nginx -t
php-fpm8.3 -t
```

Em incidente, comece por sintoma, não por suposição:

- página não abre;
- HTTP 404/500;
- falha de conexão com banco;
- erro de certificado TLS;
- falha de backup/restore.

Erro comum e ação rápida:

- erro: tratar warning como sucesso no fluxo permissive
- ação: revisar evidências/estado e corrigir causa raiz antes de encerrar a tarefa

Próximo passo:

- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
- [Checagens Operacionais](../appendices/operational-checks.md)
- [Referência de Comandos](../appendices/command-reference.md)
