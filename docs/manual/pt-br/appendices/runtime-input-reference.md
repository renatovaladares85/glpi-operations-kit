# Apêndice - Entradas e Arquivos de Runtime (PT-BR)

Este apêndice explica como os dados de configuração e runtime circulam no projeto, para que você entenda rapidamente de onde vem cada valor e onde cada arquivo gerado é consumido.

## Entrada pública versus segredo

Todos os valores de deploy ficam em `config/<environment>.env`, criado a partir de `config/product.env`. Isso inclui endpoints, topologia, modo TLS, tuning, pacotes, flags de política e segredos obrigatórios. Os scripts materializam `.runtime/<environment>/secrets.yml` a partir desse arquivo para consumo do Ansible.

Na prática, você ajusta os valores públicos em `config/<environment>.env`, executa `deploy check`, e deixa os scripts renderizarem os arquivos runtime usados pelo Ansible.

## Mapa de arquivos runtime

| Arquivo | Quem cria | Por que existe | Quem consome |
|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | renderizador de config via `glpictl` | Codifica o modelo efetivo de alvo (`local` ou `ssh`) para a execução | `ansible-inventory`, `ansible-playbook` |
| `.runtime/<env>/public.runtime.yml` | renderizador de config via `glpictl` | Converte o `key=value` público em variáveis prontas para roles | `ansible-playbook` |
| `.runtime/<env>/overrides.runtime.yml` | scripts e ações do operador | Guarda sobrescritas mutáveis (por exemplo troca de TLS) sem alterar baseline | `ansible-playbook` |
| `.runtime/<env>/secrets.yml` | renderizador de `config/<env>.env` | Guarda segredos fora do Git com permissão restrita | `ansible-playbook` |
| `.runtime/<env>/state/precheck-report-latest.yml` | precheck | Status de pré-requisitos e política em formato máquina | operadores, auditoria |
| `.runtime/<env>/evidence/precheck-report-latest.md` | precheck | Resumo legível do precheck | operadores, auditoria |
| `.runtime/<env>/state/deploy-sequence.yml` | fluxo de deploy | Rastreia estado de execução ordenada | `glpictl` |
| `.runtime/<env>/state/security-mode-last.yml` | controle de política em permissive | Registra contexto do último aceite de risco | operadores, auditoria |
| `.runtime/<env>/evidence/security-mode-*.yml` | controle de política em permissive | Histórico de exceções e justificativas | operadores, auditoria |
| `.runtime/<env>/logs/*.log` e `*.summary.yml` | scripts operacionais | Trilha de execução e sumário compacto por execução | operadores, troubleshooting, auditoria |

## Precedência de merge em execução

Quando o Ansible roda, a precedência é explícita:

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Operacionalmente, isso significa: baseline vem de `config/<environment>.env`, ajustes mutáveis entram por overrides, e segredos entram por último via arquivo secreto.

## Valores do contrato de execução

`GLPI_EXECUTION_MODE`, `GLPI_HOST_ROLE` e `SECURITY_MODE` podem ser passados como override temporário, mas o comportamento padrão vem das chaves `EXECUTION_MODE`, `EXECUTION_HOST_ROLE_DEFAULT` e `OPERATIONS_SECURITY_MODE_DEFAULT` no arquivo de ambiente.

## Chaves secretas obrigatórias

As chaves mínimas obrigatórias no `config/<environment>.env` para materialização de segredos são:

- `DATABASE_PASSWORD`
- `DATABASE_ROOT_PASSWORD`
- `MONITORING_MYSQLD_EXPORTER_PASSWORD`

Se alguma estiver ausente, os scripts falham cedo e bloqueiam operações mutáveis até o `config/<environment>.env` ficar completo.

## Regras condicionais de runtime

Quando o modo é `local`, não há exigência de conectividade SSH remota, e comandos por papel devem ser executados no host correto em topologia dual-server. Quando o modo é `ssh`, chave e conectividade remota tornam-se obrigatórias. Quando `TLS_MODE=provided`, os caminhos locais de certificado e chave devem existir de fato. Se faltarem chaves obrigatórias no `config/<environment>.env`, a execução falha cedo e não solicita dados no terminal. As flags de política (`SECURITY_REQUIRE_TLS`, `SECURITY_REQUIRE_HTTPS`, `SECURITY_REQUIRE_SSO`, `SECURITY_REQUIRE_PROMOTION_GATE`, `SECURITY_REQUIRE_ORDERED_EXECUTION`) são sempre avaliadas, e o efeito de bloqueio depende do `SECURITY_MODE` efetivo.
