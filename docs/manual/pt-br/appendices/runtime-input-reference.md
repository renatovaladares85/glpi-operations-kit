# Apêndice - Entradas e Arquivos de Runtime (PT-BR)

Este apêndice explica como os dados de configuração e runtime circulam no projeto, para que você entenda rapidamente de onde vem cada valor e onde cada arquivo gerado é consumido.

## Entrada pública versus segredo

Os valores públicos de deploy ficam em `config/<environment>.env`, criado a partir de `config/product.env`. Isso inclui endpoints, topologia, modo TLS, tuning, pacotes e flags de política. Os segredos de deploy lidos desse arquivo (`DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD` e `DATABASE_MANAGED_ADMIN_PASSWORD` opcional) são materializados em `.runtime/<environment>/secrets.yml`.

## Como funciona o `GLPI_APP_PACKAGES` automático

`GLPI_APP_PACKAGES` tem dois modos:

- Automático: deixe `GLPI_APP_PACKAGES=` vazio.
- Manual: preencha `GLPI_APP_PACKAGES` com lista completa separada por vírgula.

No modo automático, o renderer `scripts/lib/render_product_config.py` monta `WEB_SERVER_PACKAGES[WEB_SERVER_TYPE] + DEFAULT_GLPI_APP_PACKAGES`.

## Mapa de arquivos runtime

| Arquivo | Quem cria | Por que existe | Quem consome |
|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | renderizador via `glpictl` | Modelo efetivo de alvo (`local` ou `ssh`) | `ansible-inventory`, `ansible-playbook` |
| `.runtime/<env>/public.runtime.yml` | renderizador via `glpictl` | Converte `key=value` público em variáveis de role | `ansible-playbook` |
| `.runtime/<env>/overrides.runtime.yml` | scripts e operador | Sobrescritas mutáveis (ex.: TLS) | `ansible-playbook` |
| `.runtime/<env>/secrets.yml` | renderizador de `config/<env>.env` | Segredos fora do Git com permissão restrita | `ansible-playbook` |
| `.runtime/<env>/state/precheck-report-latest.yml` | precheck | Status técnico do precheck/política | operadores, auditoria |
| `.runtime/<env>/evidence/precheck-report-latest.md` | precheck | Resumo legível do precheck | operadores, auditoria |
| `.runtime/<env>/state/deploy-sequence.yml` | fluxo deploy | Estado de execução ordenada | `glpictl` |
| `.runtime/<env>/state/security-mode-last.yml` | política em permissive | Contexto do último aceite de risco | operadores, auditoria |
| `.runtime/<env>/evidence/security-mode-*.yml` | política em permissive | Histórico de exceções/justificativas | operadores, auditoria |
| `.runtime/<env>/logs/*.log` e `*.summary.yml` | scripts operacionais | Trilha e resumo de execução | operadores, troubleshooting, auditoria |

## Precedência de merge em execução

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

## Valores do contrato de execução

`GLPI_EXECUTION_MODE`, `GLPI_HOST_ROLE` e `SECURITY_MODE` podem ser passados como override temporário, mas o padrão vem de `EXECUTION_MODE`, `EXECUTION_HOST_ROLE_DEFAULT` e `OPERATIONS_SECURITY_MODE_DEFAULT`.

## Chaves secretas obrigatórias

As chaves mínimas no `config/<environment>.env` para materialização de segredos são:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD` quando `DATABASE_DEPLOYMENT_MODE=self_hosted`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD` quando `DATABASE_DEPLOYMENT_MODE=self_hosted`

Opcional para fallback em managed mode:

- `DATABASE_MANAGED_ADMIN_PASSWORD`

Se faltar chave obrigatória, o script falha cedo e bloqueia operação mutável.

## Regras condicionais de runtime

Quando o modo é `local`, não há exigência de conectividade SSH remota, e comandos por papel devem rodar no host correto na topologia dual-server.

Quando o modo é `ssh`, chave e conectividade remota tornam-se obrigatórias:

- `NETWORK_SSH_USER` deve estar ativo.
- `NETWORK_SSH_PRIVATE_KEY_PATH` deve apontar para arquivo real.

Quando `TLS_MODE=provided`, os caminhos locais de certificado e chave devem existir:

- `TLS_PROVIDED_LOCAL_CERT_PATH`
- `TLS_PROVIDED_LOCAL_KEY_PATH`

As flags de política (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`) são sempre avaliadas; o bloqueio depende do `SECURITY_MODE` efetivo.

Chaves legadas `AUTH_*` / `SSO_*` podem existir em `.env` antigo e são ignoradas pelos fluxos de execução.
