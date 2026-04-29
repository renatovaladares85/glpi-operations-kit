# Apêndice: Referência de Entradas Runtime

Arquivos gerados:

- `.runtime/staging/inventory.runtime.yml`
- `.runtime/staging/app.runtime.yml`
- `.runtime/staging/db.secrets.yml`
- `.runtime/staging/monitoring.secrets.yml`

Topologias:

- Single-server: app host e db host iguais.
- Dual-server: app host e db host distintos.

Entradas obrigatórias:

- app host IP/hostname
- db host IP/hostname
- usuário SSH
- caminho da chave SSH
- versão final do GLPI
- modo TLS (`none`, `self_signed`, `provided`)
- caminhos de cert/key (modo `provided`)
- nome do banco
- usuário do banco
- senha do banco
- senha root do MariaDB
- usuário/senha do `mysqld_exporter`

Modelos de arquivo:

- Use os mesmos modelos em [runtime-input-reference.md](../../../manual-appendices/runtime-input-reference.md).
