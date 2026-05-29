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

Valide após editar:

```bash
./scripts/glpictl.sh staging deploy check all
```

Erro comum e ação rápida:

- erro: role de host incorreta em fluxo dual-server local
- ação: usar role DB no host DB e role APP no host APP

Próximo passo:

- [03 - Deploy em Linux](03-deploy-linux-traditional.md)
- [Guia de Preenchimento do Ambiente](../appendices/configuration-field-guide.md)
- [Entradas e Arquivos de Runtime](../appendices/runtime-input-reference.md)
