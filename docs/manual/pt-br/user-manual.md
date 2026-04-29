# Runbook Operacional GLPI SoEnergy

## 1. Finalidade

Este manual e o runbook oficial para instalar, validar, promover e operar os ambientes GLPI SoEnergy.

Ele se destina a:

- operadores Linux
- engenheiros DevOps ou de infraestrutura
- aprovadores tecnicos responsaveis por homologacao e producao
- agentes de IA que precisem seguir as regras do repositorio antes de sugerir ou aplicar mudancas

Este manual explica:

- o que cada comando faz
- onde cada comando deve ser executado
- quando cada comando deve ser executado
- o que cada comando altera nos hosts de destino
- quais pre-requisitos sao obrigatorios antes de a execucao continuar

## 2. Perfil Exigido

Skill obrigatoria do operador:

- administracao de servidores Ubuntu
- uso de `sudo`
- acesso SSH por chave
- execucao e troubleshooting com Ansible
- nocao de controle de mudanca em ambiente corporativo

Perfil recomendado para IA:

- agente que leia `README.md`, `AGENTS.md`, `docs/standards/index.md` e este runbook antes de agir

## 3. Topologias Suportadas

Topologia principal:

- dual-server
- um host `app`
- um host `db`

Topologia suportada como fallback:

- single-server
- um unico host Ubuntu executando aplicacao e banco

Como a topologia e definida:

- o inventario runtime define os hosts reais
- se `app host` e `db host` forem o mesmo valor, o deploy funciona como single-server
- se `app host` e `db host` forem valores diferentes, o deploy funciona como dual-server

## 4. Onde Executar os Comandos

Origens de execucao suportadas:

- no host `app`
- no host `db`
- no mesmo host em modo single-server

Regra operacional:

- o host de execucao precisa ter o clone do Git, `bash`, `git`, `ansible-playbook`, `ansible-inventory`, acesso por chave SSH e `sudo`

O que acontece no modo dual-server:

- o `glpictl` roda localmente no host de execucao
- o Ansible conecta por SSH no host remoto definido no inventario runtime
- tarefas `db` rodam apenas no grupo `glpi_db`
- tarefas `app` rodam apenas no grupo `glpi_app`

## 5. Pre-requisitos Obrigatorios

### 5.1 Plataforma e repositorio

- Ubuntu Linux no host de execucao
- repositorio clonado localmente
- espaco livre local suficiente para `.runtime`, logs e evidencias

### 5.2 Ferramentas obrigatorias

- `bash`
- `git`
- `ansible-playbook`
- `ansible-inventory`

Ferramenta recomendada:

- `ssh`

### 5.3 Acessos e permissoes obrigatorias

- `sudo` valido no host de execucao
- operador deve pertencer ao grupo `glpiops`
- arquivo de chave SSH privada deve existir
- arquivo de chave SSH privada deve estar em modo `0600`
- hosts remotos devem ser alcancaveis por SSH
- o usuario SSH deve ter privilegio para executar as mudancas necessarias

### 5.4 Setup obrigatorio do operador

```bash
sudo groupadd -f glpiops
sudo usermod -aG glpiops "$USER"
newgrp glpiops
sudo -v
```

### 5.5 Primeiro comando obrigatorio

```bash
bash scripts/bootstrap-permissions.sh
```

Para que serve:

- garante permissao de execucao nos scripts
- prepara `.runtime/`
- valida a baseline de permissoes do operador
- grava o bootstrap marker

## 6. CLI Oficial

Entrypoint oficial:

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Ambientes suportados:

- `staging`
- `production`

Dominios suportados:

- `deploy`
- `certify`
- `promote`
- `tls`
- `ops`
- `audit`

Nota de compatibilidade:

- scripts especificos como `deploy-staging.sh`, `deploy-db.sh` e `manage-tls.sh` continuam funcionando
- eles sao wrappers do `glpictl.sh`

## 7. Matriz de Comportamento dos Comandos

| Forma do comando | Finalidade | Hosts alvo | Quando usar |
|---|---|---|---|
| `glpictl <env> deploy check all` | Validar precheck e inventario runtime | checks locais + parse do inventario | antes de qualquer apply |
| `glpictl <env> deploy apply db` | Instalar e configurar MariaDB | `glpi_db` | primeiro apply em ambiente novo |
| `glpictl <env> deploy apply app` | Instalar e configurar stack do GLPI | `glpi_app` | depois que o banco estiver acessivel |
| `glpictl <env> deploy apply monitoring` | Instalar exporters | app e db conforme a role | depois da baseline de app e db |
| `glpictl <env> deploy apply backup` | Instalar baseline de backup | hosts definidos pela role | depois da baseline de app e db |
| `glpictl <env> deploy apply all` | Aplicar base, app, db, monitoring e backup | ambos os grupos | execucao completa controlada |
| `glpictl <env> deploy post-check all` | Rodar validacao pos-deploy | app e db | depois do deploy |
| `glpictl staging certify run` | Gerar evidencias de homologacao e gate | checks locais + app + db | antes de producao |
| `glpictl <env> tls <action>` | Alterar ou recarregar TLS | `glpi_app` | depois da baseline da app |
| `glpictl <env> ops ...` | Manutencao day-2 | depende da operacao | depois do deploy |
| `glpictl <env> audit check` | Rodar auditoria operacional | app e db | depois do deploy ou de mudancas |
| `glpictl production promote apply <target>` | Deploy em producao com gate | depende do target | depois da certificacao aprovada |

## 8. Arquivos Runtime e Seus Significados

Raiz runtime:

- `.runtime/<environment>/`

Arquivos de configuracao:

- `inventory.runtime.yml`
- `app.runtime.yml`
- `db.secrets.yml`
- `monitoring.secrets.yml`

Estado operacional:

- `.runtime/<environment>/logs/`
- `.runtime/<environment>/state/`
- `.runtime/<environment>/evidence/`

Gate de promocao:

- `.runtime/promotion/staging-certified.yml`

Comportamento importante:

- se os arquivos runtime estiverem ausentes, o `glpictl` atualmente coleta todos os inputs runtime antes de continuar
- isso significa que `apply db` pode pedir valores de app e monitoring tambem
- isso e seguro, mas ainda nao esta otimizado para o menor numero de prompts

## 9. O Que `apply db` Faz

Comando:

```bash
./scripts/glpictl.sh staging deploy apply db
```

Onde executar:

- no host app, no host db, ou no mesmo host em single-server

Quando executar:

- primeiro passo de apply em ambiente novo
- antes de `apply app`

O que altera:

- instala pacotes do MariaDB quando aplicavel pela role
- aplica tuning e hardening basico do MariaDB
- cria ou atualiza o banco do GLPI
- cria ou atualiza o usuario do banco do GLPI
- usa somente o grupo de inventario `glpi_db`

O que precisa:

- inventario runtime
- nome do banco
- usuario do banco
- senha do banco
- senha root do MariaDB
- acesso SSH ao host do banco

O que validar depois:

- servico MariaDB em execucao no host db
- schema do GLPI existente
- usuario do banco existente
- host da aplicacao autorizado a conectar

## 10. O Que `apply app` Faz

Comando:

```bash
./scripts/glpictl.sh staging deploy apply app
```

Onde executar:

- no host app, no host db, ou no mesmo host em single-server

Quando executar:

- depois de `apply db` concluir com sucesso
- depois que o host do banco estiver acessivel e as credenciais forem conhecidas

O que altera:

- instala e configura Nginx
- instala e configura PHP-FPM
- baixa ou prepara os arquivos do GLPI
- aplica o layout seguro do filesystem do GLPI
- configura arquivos do lado da aplicacao
- aplica o modo TLS do lado da aplicacao
- usa somente o grupo de inventario `glpi_app`

O que precisa:

- inventario runtime
- versao do GLPI
- host da aplicacao
- modo TLS
- caminhos dos certificados se `provided`
- arquivo runtime do banco ja preenchido com conectividade da aplicacao

O que validar depois:

- `nginx -t`
- `php-fpm8.3 -t`
- pagina do instalador do GLPI abre
- aplicacao consegue acessar o banco

## 11. Runbook Single-Server

### 11.1 Quando usar

- laboratorio ou ambiente restrito
- validacao temporaria
- ambiente pequeno de teste nao produtivo

### 11.2 Como informar os valores runtime

- informar o mesmo valor para `app host` e `db host`

### 11.3 Ordem de execucao

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 11.4 Validacao

- servicos de banco e app no mesmo servidor
- pagina GLPI abre no endpoint da aplicacao
- artefatos de backup e monitoring existem

## 12. Runbook Dual-Server a Partir do Host App

### 12.1 Quando usar

- deploy corporativo padrao
- recomendado para homologacao e producao

### 12.2 Como informar os valores runtime

- `app host` = host app atual
- `db host` = host remoto do banco
- usuario SSH e chave devem funcionar nos dois hosts

### 12.3 Ordem de execucao

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 12.4 O que acontece internamente

- o comando roda localmente no host app
- o Ansible conecta do host app para o host db ao aplicar a role `db`
- o Ansible permanece no host app ou reconecta ao host app ao aplicar a role `app`

## 13. Runbook Dual-Server a Partir do Host DB

### 13.1 Quando usar

- quando o host db for o ponto aprovado de execucao
- quando o host app for alcancavel por SSH a partir do host db

### 13.2 Como informar os valores runtime

- `db host` = host db atual
- `app host` = host remoto da aplicacao
- usuario SSH e chave devem funcionar nos dois hosts

### 13.3 Ordem de execucao

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 13.4 O que acontece internamente

- o comando roda localmente no host db
- o Ansible conecta do host db para o host app quando tarefas de aplicacao sao necessarias

## 14. Certificacao de Homologacao e Producao

Certificacao de homologacao:

```bash
./scripts/glpictl.sh staging certify run
```

O que faz:

- roda checks de validacao
- grava evidencias em `.runtime/staging/evidence/`
- grava o arquivo de gate de promocao

Rollout de producao:

```bash
./scripts/glpictl.sh production deploy check all
./scripts/glpictl.sh production deploy apply db
./scripts/glpictl.sh production deploy apply app
./scripts/glpictl.sh production deploy apply monitoring
./scripts/glpictl.sh production deploy apply backup
./scripts/glpictl.sh production deploy post-check all
```

Condicao de bloqueio:

- `apply` em producao continua bloqueado sem `.runtime/promotion/staging-certified.yml`

## 15. Condicoes de Parada

A execucao deve parar quando qualquer pre-requisito obrigatorio nao puder ser resolvido:

- sem `sudo`
- operador fora do grupo `glpiops`
- `ansible-playbook` ausente
- `ansible-inventory` ausente
- caminho da chave SSH nao existe
- modo da chave SSH inseguro e sem correcao
- hosts de destino errados ou inacessiveis
- gate de producao ausente para apply em producao

## 16. Recomendacoes de Melhoria

### 16.1 Melhoria de maior valor

Separar a coleta de inputs runtime por dominio:

- `apply db` deve pedir apenas valores de banco
- `apply app` deve pedir apenas valores de app e TLS
- `apply monitoring` deve pedir apenas valores de monitoring quando faltarem

Motivo:

- reduz confusao operacional
- reduz numero de prompts
- reduz risco de preencher valores desnecessarios cedo demais
- reduz custo de contexto e tokens para IA
- faz o comportamento do comando ficar mais previsivel

### 16.2 Outras melhorias

- gerar um apendice de referencia de comandos a partir do contrato real da CLI
- criar um documento de perfil operacional legivel por agentes
- adicionar passos de restore drill com evidencias esperadas

## 17. Documentacao Relacionada

- [Indice multilingue](../README.md)
- [Indice de apendices](appendices/index.md)
- [Plano de implementacao](../../implementation-plan.md)
