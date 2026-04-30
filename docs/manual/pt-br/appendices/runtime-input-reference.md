# Apêndice: Referência de Inputs Runtime e Arquivos Runtime

## 1. Fonte pública de configuração

Arquivos principais:

- `config/product.example.yml`
- `config/<environment>.yml` (criado a partir de `product.example.yml`)

Todos os valores não sensíveis devem sair desses arquivos.

## 2. Chaves públicas do contrato de execução

Essas chaves controlam como os scripts executam:

- `execution.mode`: `local` ou `ssh`
- `execution.host_role_default`: `app`, `db` ou `all`

Overrides por variável de ambiente:

- `GLPI_EXECUTION_MODE`
- `GLPI_HOST_ROLE`
- `GLPI_ENVIRONMENT`

## 3. Mapa de artefatos runtime

| Arquivo | Tipo | Produtor | Consumidor | Sensibilidade | Finalidade operacional |
|---|---|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | gerado | render via `glpictl` | inventário Ansible | restrito | define alvos e modelo de conexão (`local` ou `ssh`) |
| `.runtime/<env>/public.runtime.yml` | gerado | render via `glpictl` | variáveis Ansible | restrito | converte dados públicos para variáveis das roles |
| `.runtime/<env>/overrides.runtime.yml` | runtime mutável | `glpictl` / operador | variáveis Ansible | restrito | sobrescritas sem editar `config/<env>.yml` |
| `.runtime/<env>/secrets.yml` | segredo runtime | prompts do operador | variáveis Ansible | secreto | credenciais e valores sensíveis fora do Git |
| `.runtime/<env>/state/precheck-report-latest.yml` | estado gerado | precheck | operação/auditoria | restrito | status estruturado de pré-requisitos e políticas |
| `.runtime/<env>/evidence/precheck-report-latest.md` | evidência gerada | precheck | operação/auditoria | restrito | relatório legível de pré-requisitos |
| `.runtime/<env>/state/deploy-sequence.yml` | estado gerado | `glpictl` | `glpictl` | restrito | rastreia a ordem de execução |
| `.runtime/<env>/state/security-mode-last.yml` | estado gerado | `glpictl` | operação/auditoria | restrito | último contexto de risco aceito em modo permissivo |
| `.runtime/<env>/evidence/security-mode-*.yml` | evidência gerada | `glpictl` | operação/auditoria | restrito | histórico de exceções de política em modo permissivo |
| `.runtime/<env>/logs/*.log` e `*.summary.yml` | log gerado | scripts operacionais | operação/auditoria | restrito | trilha de execução e resumo de operação |

## 4. Precedência de merge runtime

Ordem de merge:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Significado prático:

- baseline vem de `config/<env>.yml`
- operações mutáveis (ex.: troca de TLS) escrevem em overrides
- segredos sempre ficam no arquivo de segredos runtime

## 5. Segredos obrigatórios

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

Comportamento quando faltar:

- scripts solicitam de forma interativa
- execução mutável fica bloqueada até preencher

## 6. Requisitos condicionais

- Se `execution.mode=local`:
  - não existe validação obrigatória de conectividade SSH remota.
  - em dual-server, execute ações DB e APP nos respectivos hosts.
- Se `execution.mode=ssh`:
  - chave SSH por ambiente e conectividade remota são obrigatórias.
- Se `tls.mode=provided`:
  - `tls.provided_local_cert_path` e `tls.provided_local_key_path` devem apontar para arquivos locais existentes.
- Se flags de segurança estiverem habilitadas:
  - `security.require_tls=true` exige `tls.mode=provided`.
  - `security.require_https=true` exige TLS ativo (`self_signed` ou `provided`).
  - `security.require_sso=true` exige `security.sso_enabled=true`.
  - `security.require_promotion_gate=true` exige `.runtime/promotion/staging-certified.yml`.

## 7. Tratamento da política por modo de segurança

- `SECURITY_MODE=secure`: violações de política bloqueiam operações mutáveis.
- `SECURITY_MODE=permissive`: violações viram warning e são registradas com justificativa.
