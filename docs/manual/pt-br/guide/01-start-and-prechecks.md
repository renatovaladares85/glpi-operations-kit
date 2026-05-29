# 01 - Início e Prechecks

Antes de instalar ou alterar qualquer ambiente, confirme que você está no contexto correto e que o ambiente está pronto.

A maior parte das falhas de deploy acontece por:

- host de execução incorreto;
- arquivo de ambiente ausente;
- pré-requisitos locais faltando.

Primeiro confirme que você está em shell Linux e que o arquivo de ambiente já existe.

Onde verificar:

- `config/.env.example` (template)
- `config/<environment>.env` (seu ambiente)

Execute a preparação de baseline:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
```

Como saber que deu certo:

- sem falha obrigatória no precheck;
- arquivos runtime gerados em `.runtime/<environment>/`;
- inventário pronto para os próximos passos.

Erro comum e ação rápida:

- erro: `config/<environment>.env` ausente
- ação: criar a partir do template e executar o precheck novamente

```bash
cp config/.env.example config/staging.env
./scripts/glpictl.sh staging deploy check all
```

Próximo passo:

- [02 - Ambiente e Topologia](02-environment-and-topology.md)
- [Referência de Comandos](../appendices/command-reference.md)
- [Matriz de Pré-requisitos](../../../product/prerequisites-matrix.md)
