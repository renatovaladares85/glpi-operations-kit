# GLPI Operations Kit - Manual do Operador (PT-BR, Espelho)

<<<<<<< HEAD
Este manual orienta uma instalação completa do GLPI Operations Kit em shell Linux. Ele cobre preparação, preenchimento do `.env`, TLS, banco, aplicação, monitoramento, backup, validação e rollback.
=======
Este manual é o espelho da versão canônica em EN.
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

Use esta página como roteador:

1. comece pela trilha guiada;
2. execute as etapas operacionais;
3. valide os resultados;
4. consulte apêndices técnicos apenas quando precisar de profundidade.

<<<<<<< HEAD
1. [Pré-requisitos](#pré-requisitos)
2. [Arquivos que você precisa preencher](#arquivos-que-você-precisa-preencher)
3. [Fluxo recomendado do zero](#fluxo-recomendado-do-zero)
4. [Escolha de topologia](#escolha-de-topologia)
5. [TLS e certificados](#tls-e-certificados)
6. [Configuração manual de SSO no GLPI](#configuração-manual-de-sso-no-glpi)
7. [Banco, aplicação, monitoramento e backup](#banco-aplicação-monitoramento-e-backup)
8. [Validação, evidências e rollback](#validação-evidências-e-rollback)
9. [Apêndices](#apêndices)
=======
## Trilha Operacional (Guiada)
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

1. [Início e Prechecks](guide/01-start-and-prechecks.md)
2. [Ambiente e Topologia](guide/02-environment-and-topology.md)
3. [Deploy em Linux (Ubuntu + Nginx + PHP-FPM + MariaDB)](guide/03-deploy-linux-traditional.md)
4. [TLS e Certificados](guide/04-tls-and-certificates.md)
5. [Backup, Restore e Teste de Restore](guide/05-backup-restore-and-restore-test.md)
6. [Atualização In-Place do GLPI](guide/06-glpi-upgrade-in-place.md)
7. [Plugins e Marketplace (Fluxo Manual)](guide/07-plugins-and-marketplace.md)
8. [Validação e Troubleshooting](guide/08-validation-and-troubleshooting.md)
9. [Trilha de Referência Docker/Compose (Separada)](guide/09-docker-compose-reference.md)
10. [Cobertura da Automação](guide/10-automation-coverage.md)

## Atalhos por Intenção

<<<<<<< HEAD
- Acesso Linux com `sudo` quando necessário.
- Repositório disponível no host executor.
- Arquivo `config/<environment>.env` criado a partir de `config/product.env`.
- Segredos fortes disponíveis para banco e monitoramento.
- FQDN do GLPI definido, principalmente quando TLS for usado.
- Decisão de topologia: `single-server` ou `dual-server`.
- Decisão de execução: `local` ou `ssh`.
=======
- Quero instalar o GLPI: [Deploy em Linux](guide/03-deploy-linux-traditional.md)
- Quero configurar variáveis de ambiente: [Ambiente e Topologia](guide/02-environment-and-topology.md)
- Quero TLS/HTTPS: [TLS e Certificados](guide/04-tls-and-certificates.md)
- Quero backup: [Backup, Restore e Teste de Restore](guide/05-backup-restore-and-restore-test.md)
- Quero restore: [Backup, Restore e Teste de Restore](guide/05-backup-restore-and-restore-test.md)
- Quero atualizar o GLPI: [Atualização In-Place do GLPI](guide/06-glpi-upgrade-in-place.md)
- Quero validar serviços e saúde do ambiente: [Validação e Troubleshooting](guide/08-validation-and-troubleshooting.md)
- Estou com erro: [Validação e Troubleshooting](guide/08-validation-and-troubleshooting.md)
- Quero entender o que a automação faz: [Cobertura da Automação](guide/10-automation-coverage.md)
- Preciso de detalhes de comandos: [Referência de Comandos](appendices/command-reference.md)
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

## Referências Técnicas (Profundidade)

<<<<<<< HEAD
```bash
bash scripts/bootstrap-permissions.sh
```

## Arquivos que você precisa preencher

| Arquivo | Finalidade | Deve ir para Git? |
|---|---|---|
| `config/product.env` | Template versionado do produto. | Sim. Não coloque valores reais sensíveis. |
| `config/<environment>.env` | Configuração pública do ambiente mais 3 segredos de deploy (`DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD`, `MONITORING_MYSQLD_EXPORTER_PASSWORD`). | Não commitar cópias reais de ambiente. |
| `.runtime/<environment>/secrets.yml` | Segredos runtime usados pelos fluxos de execução. | Nunca. |
| `.runtime/<environment>/public.runtime.yml` | Renderização pública gerada pelos scripts. | Nunca. |
| `.runtime/<environment>/evidence/` | Evidências de execução. | Nunca, salvo pacote auditado e sanitizado fora do Git. |
| `.runtime/<environment>/backups/` | Snapshots/backup por domínio. | Nunca. |

Nota de fluxo de segredos:

- Os 3 segredos de deploy armazenados em `config/<environment>.env` são materializados automaticamente em `.runtime/<environment>/secrets.yml`.
- Credenciais de SSO/IdP são configuradas manualmente no GLPI e no provedor de identidade, fora da orquestração do kit.

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

5. Validar TLS quando aplicável.

```bash
./scripts/glpictl.sh staging tls check
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

## Configuração manual de SSO no GLPI

SSO/SAML/OIDC é configurado diretamente na aplicação GLPI e no provedor de identidade (por exemplo Entra ID). O kit não automatiza integração com IdP e não aplica configurações de SSO por script.

Sequência operacional recomendada:

1. Manter fallback de admin local testado no GLPI.
2. Instalar/habilitar manualmente o plugin de SSO no GLPI quando necessário.
3. Configurar metadados do IdP, claims e mapeamento JIT diretamente no GLPI.
4. Executar teste piloto de login antes de liberar usuários de produção.

Use [Guia de Autenticação, SSO e Azure/Entra ID](appendices/auth-sso-guide.md) como checklist no nível da aplicação.

## Banco, aplicação, monitoramento e backup

O deploy principal segue a sintaxe:

```bash
./scripts/glpictl.sh <environment> <domain> <action> [target] [scope]
```

Exemplo preenchido:

```bash
./scripts/glpictl.sh staging deploy apply app
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
./scripts/glpictl.sh staging tls rollback
./scripts/glpictl.sh staging ops rollback
./scripts/glpictl.sh staging audit rollback
./scripts/glpictl.sh staging deploy rollback all
```

Rollback de metadados locais restaura runtime/evidências/estado do domínio. Rollback de alterações manuais em GLPI, IAM, certificado externo ou infraestrutura remota deve seguir o checklist operacional da equipe responsável.

## Apêndices
=======
Use estes documentos quando precisar de explicações campo a campo ou detalhes técnicos avançados:
>>>>>>> df2502e (docs(manual): restructure operational guide with EN canonical flow and PT-BR mirror)

- [Índice de Apêndices](appendices/index.md)
- [Guia de Preenchimento do Ambiente](appendices/configuration-field-guide.md)
- [Modos TLS e Operações de Certificado](appendices/tls-modes.md)
- [Guia de Autenticação, SSO e Azure/Entra ID](appendices/auth-sso-guide.md)
- [Entradas e Arquivos de Runtime](appendices/runtime-input-reference.md)
- [Referência de Comandos](appendices/command-reference.md)
- [Checagens Operacionais](appendices/operational-checks.md)
- [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md)

## Notas de Escopo

- EN permanece canônico.
- PT-BR espelha EN após atualização canônica.
- Docker/Compose está documentado como trilha de referência separada nesta fase.
