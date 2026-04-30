# GLPI Operations Kit - Runbook do Operador (PT-BR)

Este manual foi escrito para operadores Linux, engenheiros de DevOps e equipes de auditoria que precisam implantar e operar o GLPI com controle, rastreabilidade e repetibilidade. Você não precisa começar lendo o código-fonte inteiro. Seguindo esta sequência, os scripts geram os arquivos de runtime, validam pré-requisitos e mostram remediações claras quando algo estiver ausente.

A edição do repositório pode ser feita em uma estação Windows, mas todos os comandos operacionais deste runbook devem ser executados em shell Linux nos servidores de destino.

A skill esperada é administração prática de Ubuntu com `sudo`, uso de shell e execução básica de Ansible. Se sua empresa exige login interativo com usuário, senha e 2FA em cada host, o fluxo local por host já cobre esse cenário sem depender de SSH entre servidores.

## Comece por aqui

A primeira ação é preparar a configuração e, em seguida, ajustar permissões. Copie o template do produto e crie o arquivo do ambiente:

```bash
cp config/product.env config/staging.env
```

Abra `config/staging.env` e ajuste todos os valores obrigatórios, incluindo os sensíveis necessários para o deploy. O script não solicita mais segredos no terminal; ele lê do arquivo de ambiente e materializa `.runtime/<environment>/secrets.yml` com permissão restrita.

Depois de ajustar o arquivo, execute:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
```

Você não precisa executar `export` manual para as variáveis de execução no fluxo normal. O `glpictl` carrega automaticamente `config/<environment>.env` e aplica esta precedência:

1. argumentos da CLI (por exemplo `staging deploy apply db`)
2. variáveis já existentes no processo (sobrescritas pontuais opcionais)
3. `config/<environment>.env`
4. defaults internos

## Como a execução funciona

O comando canônico é:

```bash
./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit> <action> [target] [scope]
```

O `domain` define a área operacional (`deploy`, `tls`, `ops`, `audit`, `certify`, `promote`) e `action/target` definem exatamente o que será alterado. O formato do comando é igual para qualquer ambiente; o que muda é apenas o conteúdo de `<environment>.env` e os segredos de runtime.

Quando faltar ferramenta obrigatória, como `ansible-playbook` ou `ansible-inventory`, os scripts oferecem instalação guiada no Ubuntu. Se a instalação falhar ou for recusada, a execução é bloqueada com comando de correção explícito, para você retomar do mesmo ponto.

## Execução em single-server e dual-server

No modelo single-server, defina `TOPOLOGY_MODE=single-server` e mantenha `EXECUTION_HOST_ROLE_DEFAULT=all` no arquivo de ambiente. Depois execute as etapas na ordem, no mesmo host.

No modelo dual-server, `TOPOLOGY_MODE=dual-server` é o padrão recomendado. Se a empresa não permite SSH direto entre servidores, mantenha `EXECUTION_MODE=local`. Nesse modo, cada host é configurado localmente após autenticação interativa, incluindo 2FA quando exigido:

1. No host DB: rode `deploy check all` e depois `deploy apply db`.
2. No host APP: rode `deploy check all`, depois `deploy apply app`, `deploy apply monitoring`, `deploy apply backup` e `deploy post-check all`.

Se automação remota for permitida, defina `EXECUTION_MODE=ssh`, preencha `NETWORK_SSH_USER` e `NETWORK_SSH_PRIVATE_KEY_PATH`, e mantenha a chave privada com modo `0600`.

## Ordem obrigatória de execução

A ordem segura é:

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Quando `SECURITY_REQUIRE_ORDERED_EXECUTION=true` e o `SECURITY_MODE` efetivo é `secure`, chamadas mutáveis fora de ordem são bloqueadas. Em `permissive`, a execução continua com warning, mas com evidência obrigatória de aceite de risco.

## O que os comandos principais fazem

| Comando | Onde executar | Finalidade operacional |
|---|---|---|
| `./scripts/glpictl.sh staging deploy check all` | host atual | Roda precheck, valida permissões, confirma carregamento de config, materializa runtime, valida inventário e contrato de política antes de qualquer alteração mutável. |
| `./scripts/glpictl.sh staging deploy apply db` | host DB em dual-server local, ou host orquestrador em modo ssh | Instala e aplica hardening no MariaDB, configura parâmetros de banco, provisiona base/usuário/grants do GLPI e reforça restrições de origem de acesso da app. |
| `./scripts/glpictl.sh staging deploy apply app` | host APP em dual-server local, ou host orquestrador em modo ssh | Instala pacotes da aplicação, publica layout do GLPI fora da web root, configura Nginx + PHP-FPM, aplica template de TLS e configura conectividade da aplicação com o banco. |
| `./scripts/glpictl.sh staging deploy apply monitoring` | host APP (e DB conforme escopo) | Instala e configura exporters e baseline de observabilidade a partir dos valores de runtime. |
| `./scripts/glpictl.sh staging deploy apply backup` | host APP (e DB conforme escopo) | Aplica baseline de backup, política de retenção e artefatos operacionais usados em validação e restore. |
| `./scripts/glpictl.sh staging deploy post-check all` | host atual | Executa validações pós-implantação e checagens de serviço após as etapas mutáveis. |
| `./scripts/glpictl.sh staging tls self-signed` | host APP | Troca o modo TLS para certificado autoassinado, atualiza override de runtime, reaplica caminho da app e valida Nginx antes de recarregar serviço. |
| `./scripts/glpictl.sh staging tls install-provided` | host APP | Valida caminhos de certificado/chave fornecidos, atualiza override e caminhos de destino, reaplica app e recarrega serviço somente após validação de configuração. |
| `./scripts/glpictl.sh staging ops cert check` | host APP | Lê o certificado ativo e alerta quando estiver próximo do vencimento configurado. |
| `./scripts/glpictl.sh staging audit check` | host onde a auditoria operacional será feita | Consolida checagens de permissão, política, runtime e saúde operacional para validação contínua. |
| `bash scripts/release-readiness.sh staging` | host executor com acesso ao repositório | Gera evidências de prontidão e falha apenas quando houver problema técnico crítico de readiness. |

## Decisões de TLS e modo de segurança

O fluxo TLS foi desenhado para três caminhos explícitos: `none`, `self_signed` e `provided`. Você pode começar com `none` em desenvolvimento ou homologação controlada, evoluir para `self_signed` em testes criptografados internos e, depois, mudar para `provided` quando tiver certificado válido. A troca é feita por script, sem edição manual de template Nginx.

A política de segurança é escolhida por execução. `SECURITY_MODE=secure` aplica bloqueios de política. `SECURITY_MODE=permissive` permite continuidade com warning, mas sempre grava quem aceitou o risco, quando e quais políticas foram violadas.

## Arquivos de runtime e significado

Após `deploy check`, os arquivos aparecem em `.runtime/<environment>/`. O `public.runtime.yml` é o baseline não sensível renderizado a partir de `config/<environment>.env`. O `overrides.runtime.yml` guarda alterações operacionais mutáveis, como mudanças de TLS, sem alterar seu baseline público. O `secrets.yml` guarda valores sensíveis coletados em runtime e deve permanecer restrito. O `inventory.runtime.yml` é o contrato efetivo de inventário consumido pelo Ansible em modo local ou ssh. As pastas `state/` e `evidence/` guardam checkpoints e trilhas de auditoria para certificação, troubleshooting e investigação.

Para referência comando a comando, consulte [Referência de Comandos](appendices/command-reference.md). Para detalhes de parâmetros de configuração, consulte [Environment Parameters](../../product/environment-parameters.md) e [Configuration Reference](../../product/configuration-reference.md).

## Validação e troubleshooting

A validação mínima pós-implantação é: página do GLPI acessível, conectividade com DB funcionando, `nginx -t` válido, teste de configuração do PHP-FPM válido e evidências de runtime geradas. Se algo falhar, siga a trilha segura do [Troubleshooting Matrix](appendices/troubleshooting-matrix.md), que cobre dependências ausentes, host role incorreto, material SSH ausente em modo ssh, caminhos TLS inválidos e comportamento por modo de política.

## Apêndices relacionados

- [Referência de Comandos](appendices/command-reference.md)
- [Entradas e Arquivos de Runtime](appendices/runtime-input-reference.md)
- [Modos TLS](appendices/tls-modes.md)
- [Checagens Operacionais](appendices/operational-checks.md)
- [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md)
