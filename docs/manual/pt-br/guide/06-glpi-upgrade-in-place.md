# 06 - Atualização In-Place do GLPI

Este repositório adota atualização in-place com controles de segurança obrigatórios.

Condições mínimas antes de atualizar:

1. backup validado disponível;
2. janela de manutenção aprovada;
3. ensaio em staging concluído;
4. caminho de rollback confirmado.

Sequência típica:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy post-check all
bash scripts/release-readiness.sh staging
```

Normalmente você define a versão alvo em `config/<environment>.env` antes de aplicar.

Como saber que deu certo:

- `deploy apply app` concluído;
- `post-check` concluído;
- relatório de readiness sem falhas críticas.

Erro comum e ação rápida:

- erro: atualização iniciada sem backup validado
- ação: interromper, gerar backup, e reexecutar com janela controlada

Próximo passo:

- [03 - Deploy em Linux](03-deploy-linux-traditional.md)
- [Checagens Operacionais](../appendices/operational-checks.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
