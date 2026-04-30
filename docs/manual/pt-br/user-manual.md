# Runbook Operacional do GLPI Operations Kit

## 1. Finalidade do Manual

Este runbook é o guia oficial para instalar, validar e operar o GLPI Operations Kit em ambientes corporativos.

Público-alvo:

- operadores Linux;
- engenheiros de DevOps/infraestrutura;
- aprovadores técnicos de homologação e produção;
- agentes de IA que seguem os padrões do repositório.

## 2. Skill Necessária do Operador

Perfil mínimo:

- administração de servidores Ubuntu;
- gestão de chaves SSH;
- uso de `sudo`;
- execução e troubleshooting com Ansible;
- disciplina de controle de mudanças e evidências.

## 3. Topologias Suportadas

- Dual-server (recomendado): 1 host app + 1 host db.
- Single-server (suportado): app e db no mesmo host.

Origem de execução:

- host app, host db ou host único;
- o host executor precisa ter clone do repositório e ferramentas obrigatórias.

## 4. Modelo de Configuração e Runtime

Configuração pública:

- `config/staging.yml`
- `config/production.yml`

Segredos runtime:

- `.runtime/<env>/secrets.yml` (nunca versionar)

Precedência runtime:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Referências detalhadas:

- [Matriz de Pré-Requisitos](../../product/prerequisites-matrix.md)
- [Referência de Configuração](../../product/configuration-reference.md)
- [Parâmetros de Ambiente](../../product/environment-parameters.md)

## 5. Pré-Requisitos (Obrigatório, Opcional e Condicional)

Obrigatório em todos os ambientes:

- Ubuntu 24.04
- `bash`, `git`, `python3`, `ansible-playbook`, `ansible-inventory`
- `sudo` funcional ou root
- operador no grupo `glpiops`
- `.runtime` com permissões seguras

Condicional obrigatório:

- par de chaves SSH por ambiente + conectividade com alvos quando houver execução remota;
- arquivos locais de certificado/chave quando `tls.mode=provided`.

Opcional:

- checks de diagnóstico com `ssh` (recomendado).

Comportamento do precheck:

- para pacotes obrigatórios ausentes, os scripts perguntam se podem instalar automaticamente no Ubuntu;
- se a instalação automática falhar (ou for negada), a execução é bloqueada com comandos de correção.

## 6. Geração e Distribuição de Chaves SSH (Obrigatório em Execução Remota)

Chave de staging:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_staging_ed25519 -C "glpi-staging-ops"
chmod 600 ~/.ssh/glpi_staging_ed25519
chmod 644 ~/.ssh/glpi_staging_ed25519.pub
```

Chave de produção:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/glpi_production_ed25519 -C "glpi-production-ops"
chmod 600 ~/.ssh/glpi_production_ed25519
chmod 644 ~/.ssh/glpi_production_ed25519.pub
```

Distribuição para hosts app/db:

```bash
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@APP_HOST
ssh-copy-id -i ~/.ssh/glpi_staging_ed25519.pub ubuntu@DB_HOST
```

Validação de conectividade:

```bash
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@APP_HOST "echo ok"
ssh -i ~/.ssh/glpi_staging_ed25519 ubuntu@DB_HOST "echo ok"
```

## 7. CLI Oficial

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Ambientes suportados:

- qualquer ambiente que possua `config/<environment>.yml`;
- exemplos comuns: `staging`, `production`.

Domínios:

- `deploy`, `certify`, `promote`, `tls`, `ops`, `audit`

## 8. Matriz de Comportamento dos Comandos (Detalhada)

| Comando | Finalidade detalhada | Alvos afetados | Quando usar |
|---|---|---|---|
| `deploy check all` | executa precheck, valida pré-requisitos obrigatórios/opcionais/condicionais, valida inventário runtime e grava relatórios estruturados | host de execução | antes de qualquer mutação |
| `deploy apply db` | instala e endurece MariaDB, configura schema/usuário/grants do GLPI, aplica baseline operacional de banco | `glpi_db` | primeira etapa de apply |
| `deploy apply app` | instala Nginx/PHP-FPM/layout GLPI, aplica modo TLS, valida serviços e filesystem seguro | `glpi_app` | após `apply db` |
| `deploy apply monitoring` | aplica baseline de exporters e configuração de monitoramento | app/db conforme role | após db + app |
| `deploy apply backup` | aplica baseline de backup e retenção | app/db conforme role | após db + app |
| `deploy post-check all` | executa validações de pós-deploy para app e db | `glpi_app`, `glpi_db` | após etapas de apply |
| `staging certify run` | gera pacote de evidências de homologação e artefato de certificação | checks locais + remotos | antes de rollout sensível |
| `tls <action>` | altera modo TLS (`none`, `self-signed`, `provided`) e reaplica app com segurança | `glpi_app` | operações de certificado |
| `ops ...` | operação day-2: usuários, certificado, auditoria, retomada | depende da operação | manutenção pós-implantação |
| `audit check` | executa trilha de auditoria operacional e compliance | app + db | após mudanças day-2 |

## 9. Política de Ordem de Execução

Ordem recomendada:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Comportamento:

- quando `security.require_ordered_execution=true` e `SECURITY_MODE=secure`, execução fora de ordem é bloqueada;
- quando `security.require_ordered_execution=true` e `SECURITY_MODE=permissive`, execução fora de ordem continua com warning + evidência;
- arquivo de estado: `.runtime/<env>/state/deploy-sequence.yml`.

## 10. Modo de Segurança por Execução

A política de segurança não depende mais do nome do ambiente.

Use um dos modos:

- `SECURITY_MODE=secure`
- `SECURITY_MODE=permissive`

Comportamento de política:

- `secure`:
  - violações de política bloqueiam operações mutáveis (`deploy apply`, `post-check`, `tls`, `promote`, `ops`).
- `permissive`:
  - violações de política viram warning;
  - execução continua;
  - justificativa é obrigatória;
  - evidência é persistida em:
    - `.runtime/<env>/state/security-mode-last.yml`
    - `.runtime/<env>/evidence/security-mode-*.yml`

Exemplo:

```bash
SECURITY_MODE=secure ./scripts/glpictl.sh staging deploy apply db
SECURITY_MODE=permissive SECURITY_JUSTIFICATION="Janela de teste aprovada no CAB-0426" ./scripts/glpictl.sh production deploy apply app
```

## 11. Arquivos Runtime e Seus Significados

| Artefato runtime | Significado | Produtor | Consumidor |
|---|---|---|---|
| `inventory.runtime.yml` | inventário por ambiente e modelo de acesso SSH | render | Ansible |
| `public.runtime.yml` | variáveis públicas renderizadas do config | render | Ansible |
| `overrides.runtime.yml` | sobrescritas mutáveis sem alterar baseline | operador/CLI | Ansible |
| `secrets.yml` | segredos runtime | prompts do operador | Ansible |
| `state/precheck-report-latest.yml` | relatório estruturado de pré-requisitos | precheck | auditoria/troubleshooting |
| `evidence/precheck-report-latest.md` | relatório legível de pré-requisitos | precheck | operação |
| `state/deploy-sequence.yml` | status da ordem de execução | CLI | CLI |
| `state/security-mode-last.yml` | último resumo de risco aceito em modo permissivo | CLI | auditoria/compliance |
| `evidence/security-mode-*.yml` | trilha histórica de justificativas e violações de política | CLI | auditoria/compliance |
| `logs/*.log` + `*.summary.yml` | trilhas de execução e resumo | scripts de operação | auditoria/investigação |

## 12. Fluxos Passo a Passo

Single-server:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Dual-server (a partir do host app ou db):

- mesma sequência de comandos;
- mapeamento de hosts vem de `config/<env>.yml`;
- Ansible acessa o host remoto com a chave SSH definida no config.

## 13. Operações TLS e Certificado

Autoassinado:

```bash
./scripts/glpictl.sh staging tls self-signed
```

Certificado fornecido:

```bash
./scripts/glpictl.sh production tls install-provided
```

Checks pós-mudança:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I https://GLPI_DOMAIN
```

## 14. Validação e Evidências

Validação obrigatória de staging:

```bash
./scripts/glpictl.sh staging certify run
bash scripts/release-readiness.sh staging
```

Evidências obrigatórias:

- `.runtime/staging/evidence/readiness-report.md`
- `.runtime/staging/evidence/readiness-report.json`
- `.runtime/promotion/staging-certified.yml`

## 15. Documentos Relacionados

- [Índice multilíngue](../README.md)
- [Índice de apêndices PT-BR](appendices/index.md)
- [Plano de implementação](../../implementation-plan.md)
- [Matriz de pré-requisitos](../../product/prerequisites-matrix.md)
