# 03 - Deploy em Linux (Stack Tradicional)

Este é o caminho principal deste repositório para GLPI 11.x em Ubuntu com Nginx, PHP-FPM e MariaDB/MySQL.

Execute na ordem:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Se a topologia for dual-server com execução local, separe o fluxo.

Host DB:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

Host APP:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Valide configuração dos serviços:

```bash
nginx -t
php-fpm8.3 -t
```

O que validar após o deploy:

- serviço web ativo;
- PHP-FPM ativo;
- endpoint da aplicação respondendo.

Erro comum e ação rápida:

- erro: bloqueio por ordem de execução
- ação: executar a etapa anterior faltante e tentar de novo

Próximo passo:

- [04 - TLS e Certificados](04-tls-and-certificates.md)
- [Referência de Comandos](../appendices/command-reference.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
