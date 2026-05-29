# 02 - Ambiente e Topologia

Este capítulo mostra o que preencher e onde preencher para evitar erro operacional no deploy.

A configuração principal fica em:

- `config/<environment>.env`

Use `config/.env.example` apenas como template inicial.

Exemplo genérico:

```env
GLPI_DOMAIN=<seu-dominio>
DATABASE_NAME=<nome-db>
DATABASE_USER=<usuario-db>
DATABASE_PASSWORD=<segredo>
TLS_MODE=<none|self_signed|provided>
```

Exemplo preenchido fictício:

```env
GLPI_DOMAIN=glpi.empresa.example
DATABASE_NAME=glpi
DATABASE_USER=nehemiah_glpi
DATABASE_PASSWORD=troque-este-segredo
TLS_MODE=provided
```

Escolha topologia e modo de execução com cuidado:

- `TOPOLOGY_MODE=single-server`: app e db no mesmo host
- `TOPOLOGY_MODE=dual-server`: app e db em hosts diferentes
- `EXECUTION_MODE=local`: comandos executados em cada host alvo
- `EXECUTION_MODE=ssh`: execução remota centralizada (depende de política)

Antes de rodar os checks de deploy, sincronize seu arquivo de ambiente com o template baseline atual usando `env-sync.py`.

Comece em modo de relatório (sem alterar arquivo):

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.yml \
  --mode report
```

Se o relatório mostrar somente alterações gerenciadas permitidas, aplique:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.yml \
  --mode apply \
  --allow-managed
```

Para gerar evidência em arquivo:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.yml \
  --mode report \
  --write-report .runtime/reports/env-sync-staging.txt
```

Como ler o retorno rapidamente:

- saída `0`: sincronização/check concluído sem divergência acionável;
- saída `2`: diferenças encontradas em modo `report` (revisar antes de aplicar);
- saída `3`: existe chave com revisão manual obrigatória (`review_required`);
- saída `4`: problema de permissão ou backup ao tentar aplicar.

Valide após editar:

```bash
./scripts/glpictl.sh staging deploy check all
```

Erro comum e ação rápida:

- erro: role de host incorreta em fluxo dual-server local
- ação: usar role DB no host DB e role APP no host APP
- erro: `ModuleNotFoundError: No module named 'yaml'` ao executar `env-sync.py`
- ação: instalar dependência local com `sudo apt-get install -y python3-yaml` e executar novamente

Próximo passo:

- [03 - Deploy em Linux](03-deploy-linux-traditional.md)
- [Guia de Preenchimento do Ambiente](../appendices/configuration-field-guide.md)
- [Entradas e Arquivos de Runtime](../appendices/runtime-input-reference.md)
