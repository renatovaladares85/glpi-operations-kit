# GLPI Operations Kit - Manual do Operador (PT-BR)

Este manual orienta uma instalação completa do GLPI Operations Kit em shell Linux. Ele cobre preparação, preenchimento do `.env`, TLS, SSO, banco, aplicação, monitoramento, backup, validação e rollback.

Você pode editar arquivos no Windows, mas os comandos operacionais devem ser executados em shell Linux no host alvo ou em host Linux executor.

## Índice

1. [Pré-requisitos](#pré-requisitos)
2. [Arquivos que você precisa preencher](#arquivos-que-você-precisa-preencher)
3. [Fluxo recomendado do zero](#fluxo-recomendado-do-zero)
4. [Escolha de topologia](#escolha-de-topologia)
5. [TLS e certificados](#tls-e-certificados)
6. [SSO e autenticação externa](#sso-e-autenticação-externa)
7. [Banco, aplicação, monitoramento e backup](#banco-aplicação-monitoramento-e-backup)
8. [Validação, evidências e rollback](#validação-evidências-e-rollback)
9. [Apêndices](#apêndices)

## Pré-requisitos

Antes de alterar o ambiente, confirme:

- Acesso Linux com `sudo` quando necessário.
- Repositório disponível no host executor.
- Arquivo `config/<environment>.env` criado a partir de `config/product.env`.
- Segredos fortes disponíveis para banco e monitoramento.
- FQDN do GLPI definido, principalmente quando TLS ou SSO forem usados.
- Decisão de topologia: `single-server` ou `dual-server`.
- Decisão de execução: `local` ou `ssh`.

Prepare permissões e baseline local:

```bash
bash scripts/bootstrap-permissions.sh
```

## Arquivos que você precisa preencher

| Arquivo | Finalidade | Deve ir para Git? |
|---|---|---|
| `config/product.env` | Template versionado do produto. | Sim. Não coloque valores reais sensíveis. |
| `config/<environment>.env` | Configuração pública e alguns segredos obrigatórios do ambiente. | Não commitar cópias reais de ambiente. |
| `.runtime/<environment>/secrets.yml` | Segredos runtime, principalmente auth externa. | Nunca. |
| `.runtime/<environment>/public.runtime.yml` | Renderização pública gerada pelos scripts. | Nunca. |
| `.runtime/<environment>/evidence/` | Evidências de execução. | Nunca, salvo pacote auditado e sanitizado fora do Git. |
| `.runtime/<environment>/backups/` | Snapshots/backup por domínio. | Nunca. |

Para preencher cada chave do `.env`, use [Guia de Preenchimento do Ambiente](appendices/configuration-field-guide.md).

## Fluxo recomendado do zero

1. Criar configuração do ambiente.

```bash
cp config/product.env config/staging.env
```

2. Preencher `config/staging.env` usando o guia campo a campo.

3. Executar precheck.

```bash
./scripts/glpictl.sh staging deploy check all
```

4. Aplicar banco, aplicação, monitoramento e backup na ordem correta.

```bash
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

5. Validar TLS e auth quando aplicável.

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging auth check
```

6. Gerar evidências finais.

```bash
./scripts/glpictl.sh staging audit check
bash scripts/release-readiness.sh staging
```

## Escolha de topologia

Use `TOPOLOGY_MODE=single-server` quando app e DB ficam no mesmo host. Use `EXECUTION_HOST_ROLE_DEFAULT=all`.

Use `TOPOLOGY_MODE=dual-server` quando app e DB ficam em hosts separados. Em execução local sem SSH direto entre servidores:

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

Use `EXECUTION_MODE=ssh` somente quando a política permitir orquestração remota e a chave privada estiver disponível com permissão restrita.

## TLS e certificados

O kit suporta `TLS_MODE=none`, `TLS_MODE=self_signed` e `TLS_MODE=provided`.

Para produção, o caminho esperado é `provided`: certificado HTTPS de servidor, cadeia completa em PEM e chave privada PEM correspondente. Não é certificado de cliente. mTLS/client certificate não é automatizado pelo kit atual.

Leia [Modos TLS e Operações de Certificado](appendices/tls-modes.md) antes de solicitar certificado à CA ou equipe de segurança.

## SSO e autenticação externa

`AUTH_MODE=local` preserva o comportamento atual. Para LDAP, SAML ou OIDC, o domínio `auth` prepara, valida e gera evidências sem instalar plugin automaticamente e sem remover login local/admin.

Para Azure/Entra ID com SAML, leia [Guia de Autenticação, SSO e Azure/Entra ID](appendices/auth-sso-guide.md). O plugin SAML deve ser instalado manualmente no GLPI via Marketplace ou procedimento aprovado.

Fluxo básico:

```bash
./scripts/glpictl.sh staging auth check
./scripts/glpictl.sh staging auth prepare
./scripts/glpictl.sh staging auth apply
./scripts/glpictl.sh staging auth post-check
```

## Banco, aplicação, monitoramento e backup

O deploy principal segue a sintaxe:

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Comandos centrais:

| Comando | Finalidade |
|---|---|
| `deploy check all` | Valida ferramentas, permissões, config, runtime, política e inventário. |
| `deploy apply db` | Instala/configura MariaDB, base, usuário e grants. |
| `deploy apply app` | Instala GLPI, web engine, PHP-FPM, paths seguros e conectividade APP -> DB. |
| `deploy apply monitoring` | Aplica exporters e baseline de observabilidade. |
| `deploy apply backup` | Aplica baseline de backup/retenção. |
| `deploy post-check all` | Valida estado final. |

Use [Referência de Comandos](appendices/command-reference.md) para lista completa.

## Validação, evidências e rollback

Arquivos de runtime, evidência e backup ficam em `.runtime/<environment>/`.

Estruturas importantes:

| Estrutura | Uso |
|---|---|
| `.runtime/<env>/state/` | Checkpoints e ponteiros de estado. |
| `.runtime/<env>/evidence/` | Evidências por domínio. |
| `.runtime/<env>/backups/<domain>/<timestamp>/` | Snapshots por domínio com manifesto e instrução de rollback. |

Comandos padronizados onde disponíveis:

```bash
./scripts/glpictl.sh staging auth rollback
./scripts/glpictl.sh staging tls rollback
./scripts/glpictl.sh staging ops rollback
./scripts/glpictl.sh staging audit rollback
./scripts/glpictl.sh staging deploy rollback all
```

Rollback de metadados locais restaura runtime/evidências/estado do domínio. Rollback de alterações manuais em GLPI, IAM, certificado externo ou infraestrutura remota deve seguir o checklist operacional da equipe responsável.

## Apêndices

- [Guia de Preenchimento do Ambiente](appendices/configuration-field-guide.md)
- [Exemplos de Ambiente](appendices/environment-examples.md)
- [Modos TLS e Operações de Certificado](appendices/tls-modes.md)
- [Guia de Autenticação, SSO e Azure/Entra ID](appendices/auth-sso-guide.md)
- [Entradas e Arquivos de Runtime](appendices/runtime-input-reference.md)
- [Referência de Comandos](appendices/command-reference.md)
- [Checagens Operacionais](appendices/operational-checks.md)
- [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md)
