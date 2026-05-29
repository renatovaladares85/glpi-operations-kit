# Apêndice - Referência de Comandos (PT-BR)

Este apêndice complementa o runbook principal com comandos diretos e finalidade operacional. A sintaxe é a mesma; o que muda é o ambiente e os valores em `config/<environment>.env`.

Se sua tarefa agora é sincronizar `.env`, vá direto para as seções `Gerar ou recuperar .env.sync.yml` e `Sincronização de arquivos de ambiente (env-sync)` neste arquivo.

## Preparar ferramentas do host

```bash
sudo apt-get update
sudo apt-get install -y bash git python3 python3-yaml ansible openssh-client
```

Use quando o host executor for novo ou estiver sem dependências.

## Preparar permissões dos scripts

```bash
bash scripts/bootstrap-permissions.sh
```

Execute antes do primeiro comando de deploy em sessão nova de operador.

## Criar e editar configuração de ambiente

```bash
cp config/.env.example config/staging.env
```

Esse comando cria o baseline do ambiente. Os scripts carregam esse arquivo automaticamente.

## Gerar ou recuperar `.env.sync.yml`

O `scripts/env-sync.py` possui modo de geração de contrato com descoberta automática de ambientes.

Comando padrão de geração (saída para revisão, sem sobrescrever `.env.sync.yml`):

```bash
python3 scripts/env-sync.py --generate-contract
```

O que esse comando faz:

- Usa `config/.env.example` como fonte oficial das chaves.
- Descobre ambientes reais somente em `config/*.env` (excluindo `config/.env.example`).
- Gera `.env.sync.generated.yml`.
- Escreve relatório de auditoria em `docs/env-sync-contract-report.md`.
- Executa pós-checks em modo report (self-check + ambientes encontrados).

Publicar o contrato gerado em `.env.sync.yml` apenas quando explícito:

```bash
python3 scripts/env-sync.py --generate-contract --publish
```

Opções úteis:

```bash
python3 scripts/env-sync.py \
  --generate-contract \
  --output .env.sync.generated.yml \
  --report-output docs/env-sync-contract-report.md \
  --strict-post-checks
```

Notas das opções:

- `--output`: caminho do contrato gerado (default `.env.sync.generated.yml`)
- `--publish`: copia a saída gerada para `.env.sync.yml`
- `--report-output`: caminho do relatório (default `docs/env-sync-contract-report.md`)
- `--no-report`: desativa geração de relatório em arquivo
- `--strict-post-checks`: falha quando arquivos reais descobertos (`config/<environment>.env`) tiverem pendências
- Em falha estrita, a saída mostra as chaves afetadas (`missing`, `review_required`, `extra`, `ambiguous`) para correção rápida.
- `--reconcile-interactive`: resolução interativa de conflitos durante `--mode apply`
- `--extra-action comment|remove`: como tratar chaves que existem só no target na reconciliação interativa

Se `.env.sync.yml` foi removido localmente por engano e você quer a versão rastreada no Git:

```bash
git restore .env.sync.yml
```

## Fluxo obrigatório após mudar `config/.env.example`

Sempre que você adicionar, remover ou alterar qualquer chave em `config/.env.example`, execute este fluxo:

1. Regenerar contrato e rodar checks estritos para os ambientes descobertos:

```bash
python3 scripts/env-sync.py \
  --generate-contract \
  --output .env.sync.generated.yml \
  --report-output docs/env-sync-contract-report.md \
  --strict-post-checks
```

2. Revisar o relatório:
   - chaves obrigatórias ausentes em cada arquivo de ambiente;
   - divergências `review_required` que exigem decisão operacional;
   - chaves extras fora do template.

3. Para cada ambiente, executar sync report/apply até limpar pendências:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.generated.yml \
  --mode report
```

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/staging.env \
  --rules .env.sync.generated.yml \
  --mode apply \
  --allow-managed
```

Notas:

- `add_missing` fica habilitado por padrão no contrato gerado.
- Chaves extras são reportadas para saneamento; não são removidas automaticamente por padrão (`remove_extra: false`).
- O self-check do template continua no relatório, mas o bloqueio estrito considera os arquivos reais descobertos.

## Sincronização de arquivos de ambiente (env-sync)

Use `scripts/env-sync.py` para comparar o template baseline do kit (`config/.env.example`) com um arquivo de ambiente (`config/<environment>.env`) usando regras de política em `.env.sync.yml`.

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode report
```

Aplicar correções do contrato ao ambiente:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode apply
```

Reconciliação interativa (recomendado após mudança de template):

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.generated.yml \
  --mode apply \
  --reconcile-interactive \
  --extra-action comment
```

Comportamento da reconciliação interativa:

- Chaves faltantes no ambiente são adicionadas a partir do source.
- Para cada chave divergente, o script pergunta se mantém valor do source ou do target.
- Chaves que existem só no target são comentadas (ou removidas com `--extra-action remove`).

Gerar relatório em arquivo:

```bash
python3 scripts/env-sync.py \
  --source config/.env.example \
  --target config/production.env \
  --rules .env.sync.yml \
  --mode report \
  --write-report .runtime/reports/env-sync-production.txt
```

Notas operacionais:

- O modo padrão é `report` (sem alteração de arquivo).
- Em `apply`, o script adiciona chaves ausentes, preenche chaves obrigatórias vazias e remove extras reais ausentes do contrato.
- Em `apply`, o script cria backup antes de qualquer escrita (`.env-backups/` por padrão).
- Valores já ativos no ambiente têm precedência sobre o `.env.example` e aparecem em `KEPT TARGET VALUES`.
- Segredos são mascarados no terminal e em relatórios.
- A ferramenta não renomeia nem substitui a nomenclatura atual dos arquivos reais de ambiente.

## Comandos principais de implantação

```bash
./scripts/glpictl.sh <env> deploy check all
./scripts/glpictl.sh <env> deploy prepare all
./scripts/glpictl.sh <env> deploy apply db
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy apply monitoring
./scripts/glpictl.sh <env> deploy apply backup
./scripts/glpictl.sh <env> deploy post-check all
./scripts/glpictl.sh <env> deploy rollback all
```

Exemplo com valores preenchidos:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy prepare all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
./scripts/glpictl.sh staging deploy rollback all
```

## Fluxo dual-server local (sem SSH direto entre servidores)

No host DB:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

No host APP:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

## Modo SSH opcional

```bash
GLPI_EXECUTION_MODE=ssh ./scripts/glpictl.sh staging deploy check all
```

Use somente quando a política permitir orquestração remota.

## Validação de rota web e fluxo de instalação

```bash
./scripts/glpictl.sh <env> deploy apply app
./scripts/glpictl.sh <env> deploy post-check app
```

## Comandos de ciclo de vida TLS

```bash
./scripts/glpictl.sh <env> tls check
./scripts/glpictl.sh <env> tls prepare self-signed
./scripts/glpictl.sh <env> tls apply self-signed
./scripts/glpictl.sh <env> tls post-check
./scripts/glpictl.sh <env> tls rollback
./scripts/glpictl.sh <env> tls disable
./scripts/glpictl.sh <env> tls self-signed
./scripts/glpictl.sh <env> tls install-provided
./scripts/glpictl.sh <env> tls reload
```

## Certificação, prontidão e evidências

```bash
./scripts/glpictl.sh staging certify check
./scripts/glpictl.sh staging certify prepare
./scripts/glpictl.sh staging certify run
./scripts/glpictl.sh staging certify apply
./scripts/glpictl.sh staging certify post-check
./scripts/glpictl.sh staging certify rollback
bash scripts/release-readiness.sh staging
```

## Operações day-2

```bash
./scripts/glpictl.sh <env> ops check
./scripts/glpictl.sh <env> ops prepare
./scripts/glpictl.sh <env> ops users add os
./scripts/glpictl.sh <env> ops users disable db
./scripts/glpictl.sh <env> ops users remove os
./scripts/glpictl.sh <env> ops cert check
./scripts/glpictl.sh <env> ops cert renew
./scripts/glpictl.sh <env> ops audit check
./scripts/glpictl.sh <env> ops timezone check
./scripts/glpictl.sh <env> ops timezone apply
./scripts/glpictl.sh <env> ops resume
./scripts/glpictl.sh <env> ops rollback
./scripts/glpictl.sh <env> audit check
./scripts/glpictl.sh <env> audit prepare
./scripts/glpictl.sh <env> audit rollback
```

## Nota sobre SSO

A configuração SSO/SAML/OIDC é manual no GLPI e no IdP. O contrato atual da CLI não possui domínio `auth`.

## Backup e restore unificado GLPI (app|db|all)

```bash
sudo ./scripts/backup-app.sh backup --target all --encrypt
sudo ./scripts/backup-app.sh backup --target app --exclude-app "var/_cache,var/_sessions"
sudo ./scripts/backup-app.sh backup --target db --exclude-db-tables-data "glpi_logs,glpi_sessions"

sudo ./scripts/backup-app.sh restore --target app --artifact /tmp/glpi-backups/<arquivo>.tar.gz --force
sudo ./scripts/backup-app.sh restore --target db --artifact /tmp/glpi-backups/<arquivo>.tar.gz --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
sudo ./scripts/backup-app.sh restore --target all --artifact /tmp/glpi-backups/<arquivo>.tar.gz --force --db-host 127.0.0.1 --db-user root --db-name glpi --db-recreate
```

## Fallback manual com Ansible

```bash
ansible-inventory -i .runtime/staging/inventory.runtime.yml --list
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags db --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
ansible-playbook -i .runtime/staging/inventory.runtime.yml ansible/site.yml --tags app --extra-vars @.runtime/staging/public.runtime.yml --extra-vars @.runtime/staging/overrides.runtime.yml --extra-vars @.runtime/staging/secrets.yml
```
