# Runbook Operacional do GLPI Operations Kit

## 1. Finalidade do manual

Este runbook é o guia operacional para implantar, validar e operar o GLPI com este repositório.

Público principal:

- operadores Linux
- engenheiros de DevOps/infraestrutura
- responsáveis por mudanças e auditoria
- agentes de IA que seguem `AGENTS.md`

Skill mínima do operador:

- administração de servidores Ubuntu
- uso de `sudo`
- execução e troubleshooting em shell
- execução de Ansible (`ansible-playbook`, `ansible-inventory`)
- noções de segurança/compliance (LGPD, menor privilégio)

## 2. Modelo de execução

O projeto suporta dois modos de execução:

- `local` (padrão, recomendado para ambientes corporativos com 2FA)
- `ssh` (opcional, quando automação SSH remota é permitida)

Contrato de execução compartilhado por todos os scripts:

- `GLPI_ENVIRONMENT`: nome do ambiente (ex.: `staging`, `production`)
- `GLPI_EXECUTION_MODE=local|ssh`
- `GLPI_HOST_ROLE=app|db|all`
- `SECURITY_MODE=secure|permissive`

CLI oficial:

```bash
./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit> <action> [target] [scope]
```

Os wrappers (`deploy-*.sh`, `manage-tls.sh`, `ops-maintenance.sh`) usam o mesmo contrato da CLI.

## 3. Topologias e onde executar

Topologias suportadas:

- `single-server`: app e db no mesmo host
- `dual-server`: host app + host db

### 3.1 Dual-server sem SSH entre servidores (modelo corporativo com 2FA)

Se sua empresa não permite SSH direto entre servidores, use `GLPI_EXECUTION_MODE=local` e execute localmente em cada host após login interativo (usuário/senha/2FA).

Fluxo no host DB:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=db
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

Fluxo no host APP:

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=app
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Importante:

- Em dual-server local, `deploy apply db` só é válido com `GLPI_HOST_ROLE=db|all`.
- Em dual-server local, `deploy apply app|monitoring|backup` só é válido com `GLPI_HOST_ROLE=app|all`.
- Em dual-server local, `deploy apply all` com `GLPI_HOST_ROLE=app` ou `db` é bloqueado.

### 3.2 Single-server

```bash
export GLPI_ENVIRONMENT=staging
export GLPI_EXECUTION_MODE=local
export GLPI_HOST_ROLE=all
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

### 3.3 Modo SSH opcional

Use somente quando permitido por política:

- `GLPI_EXECUTION_MODE=ssh`
- par de chaves SSH por ambiente
- chave privada com modo `0600`
- conectividade remota com app/db

## 4. Pré-requisitos (obrigatório, opcional, condicional)

Obrigatórios em todos os ambientes:

- Ubuntu 24.04
- `bash`, `git`, `python3`, `ansible-playbook`, `ansible-inventory`
- `sudo` funcional (ou root)
- operador no grupo `glpiops`
- permissões seguras em `.runtime`

Condicionais obrigatórios:

- material SSH e conectividade apenas quando `GLPI_EXECUTION_MODE=ssh`
- arquivos locais de certificado/chave quando `tls.mode=provided`

Opcionais:

- cliente `ssh` para diagnóstico no modo local puro

Fonte canônica: [Matriz de Pré-requisitos](../../product/prerequisites-matrix.md)

Comportamento do precheck:

- quando faltar ferramenta obrigatória (por exemplo `ansible-playbook`), o script pergunta se pode instalar automaticamente no Ubuntu;
- se a instalação for negada ou falhar, execuções mutáveis ficam bloqueadas com comandos de correção manual.

## 5. Passo 0 (obrigatório): bootstrap de permissões

Execute antes de qualquer deploy:

```bash
bash scripts/bootstrap-permissions.sh
```

O que faz:

- garante permissão de execução em `scripts/*.sh`
- valida `sudo`
- valida grupo `glpiops`
- garante `.runtime/` com modo seguro
- grava marcador de bootstrap

Se aparecer `permission denied` ao chamar `./scripts/...`, rode o bootstrap novamente e repita o comando.

## 6. Modelo de configuração

Arquivos públicos:

- `config/product.example.yml`
- `config/<environment>.yml` (criado pelo operador a partir de `product.example.yml`)

Crie o arquivo do ambiente antes do deploy:

```bash
cp config/product.example.yml config/staging.yml
cp config/product.example.yml config/production.yml
```

Arquivo de segredo runtime:

- `.runtime/<environment>/secrets.yml`

Precedência runtime:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Referências detalhadas:

- [Configuration Reference](../../product/configuration-reference.md)
- [Environment Parameters](../../product/environment-parameters.md)

## 7. Ordem de execução e comportamento

Ordem recomendada:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Comportamento:

- se `security.require_ordered_execution=true` e `SECURITY_MODE=secure`, chamadas mutáveis fora de ordem são bloqueadas;
- em `SECURITY_MODE=permissive`, violações de política viram warning e ficam registradas como evidência.

## 8. O que cada comando principal faz

| Comando | Onde executar | O que altera | Quando executar |
|---|---|---|---|
| `deploy check all` | host atual | roda precheck, renderização de config, valida inventário e políticas | antes de qualquer ação mutável |
| `deploy apply db` | host DB (`GLPI_HOST_ROLE=db`) | instalação/hardening MariaDB, schema/usuário/grants do GLPI, baseline de banco | primeira etapa mutável |
| `deploy apply app` | host APP (`GLPI_HOST_ROLE=app`) | Nginx/PHP-FPM/layout GLPI, config runtime da app, template TLS | após DB pronto |
| `deploy apply monitoring` | host APP (e/ou DB conforme desenho) | baseline de exporters e configuração de monitoração | após DB + APP |
| `deploy apply backup` | host APP (e/ou DB conforme desenho) | baseline de backup e retenção | após DB + APP |
| `deploy post-check all` | host atual | validação pós-implantação e checks de serviço | após etapas de apply |

Notas:

- Em dual-server local, execute comandos por papel em cada host.
- Em modo SSH, a automação pode atingir hosts remotos a partir do host executor.

## 9. TLS e certificados

Ações suportadas:

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

Quando usar:

- `disable`: fluxo HTTP (somente quando política permitir)
- `self-signed`: criptografia de teste sem cadeia pública
- `install-provided`: instalar certificado/chave reais

## 10. Validação e evidências

Prontidão e certificação:

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Locais de evidência:

- `.runtime/<env>/state/precheck-report-latest.yml`
- `.runtime/<env>/evidence/precheck-report-latest.md`
- `.runtime/<env>/evidence/readiness-report.md`
- `.runtime/<env>/evidence/readiness-report.json`
- `.runtime/<env>/logs/`

## 11. Apêndices relacionados

- [Referência de Comandos](appendices/command-reference.md)
- [Referência de Inputs Runtime](appendices/runtime-input-reference.md)
- [Modos TLS](appendices/tls-modes.md)
- [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md)
