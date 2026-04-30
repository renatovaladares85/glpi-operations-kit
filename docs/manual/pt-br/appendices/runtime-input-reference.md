# Apêndice: Referência de Configuração e Arquivos Runtime

## 1. Fonte pública de configuração

Arquivos principais:

- `config/staging.yml`
- `config/production.yml`
- `config/product.example.yml`

Valores públicos devem ser mantidos nesses arquivos e renderizados para runtime automaticamente.

## 2. Mapa de arquivos runtime

| Arquivo | Tipo | Produtor | Consumidor | Sensibilidade | Finalidade |
|---|---|---|---|---|---|
| `.runtime/<env>/inventory.runtime.yml` | gerado | `glpictl` + render | inventário Ansible | restrito | define hosts de destino e acesso SSH |
| `.runtime/<env>/public.runtime.yml` | gerado | `glpictl` + render | variáveis Ansible | restrito | converte valores públicos em variáveis de role |
| `.runtime/<env>/overrides.runtime.yml` | mutável runtime | `glpictl` / operador | variáveis Ansible | restrito | sobrescreve comportamentos mutáveis (por exemplo TLS) |
| `.runtime/<env>/secrets.yml` | segredo runtime | prompts do operador | variáveis Ansible | secreto | armazena apenas segredos fora do Git |
| `.runtime/<env>/state/deploy-sequence.yml` | estado gerado | `glpictl` | `glpictl` | restrito | controla ordem obrigatória de execução |
| `.runtime/<env>/state/precheck-report-latest.yml` | estado gerado | precheck | operação/auditoria | restrito | relatório estruturado de pré-requisitos |
| `.runtime/<env>/evidence/precheck-report-latest.md` | evidência gerada | precheck | operação/auditoria | restrito | resumo legível de pré-requisitos |

## 3. Precedência de merge

1. `public.runtime.yml`
2. `overrides.runtime.yml`
3. `secrets.yml`

Impacto operacional:

- baseline público vem de `config/<env>.yml`;
- override runtime altera comportamento sem reescrever baseline;
- segredos prevalecem para chaves sensíveis.

## 4. Segredos obrigatórios

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

Se faltar:

- o script solicita em runtime;
- a execução é bloqueada até preencher.

## 5. Requisitos condicionais

- Se `tls.mode=provided`:
  - caminhos locais de certificado/chave devem existir.
- Se `topology.mode=dual-server`:
  - chave SSH por ambiente e conectividade com app/db são obrigatórias.
- Em produção:
  - políticas de TLS/HTTPS/SSO são obrigatórias e bloqueantes.
