# 06 - Atualização In-Place do GLPI

Este repositório usa atualização in-place com validações técnicas obrigatórias.

Condições mínimas antes de atualizar:

1. backup disponível e verificável;
2. versão alvo definida em `config/<environment>.env`;
3. caminho técnico de rollback confirmado;
4. comandos de validação pós-atualização definidos.

Sequência típica:

```bash
./scripts/glpictl.sh <environment> deploy check all
./scripts/glpictl.sh <environment> deploy apply app
./scripts/glpictl.sh <environment> deploy post-check all
bash scripts/release-readiness.sh <environment>
```

Como saber que deu certo:

- `deploy apply app` concluído;
- `post-check` concluído;
- relatório de readiness sem falhas críticas.

Erro comum e ação rápida:

- erro: atualização iniciada sem backup verificável
- ação: interromper, gerar novo backup verificável e reexecutar

Próximo passo:

- [03 - Deploy em Linux](03-deploy-linux-traditional.md)
- [Checagens Operacionais](../appendices/operational-checks.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
