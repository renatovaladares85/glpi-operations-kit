# GLPI Operations Kit - Runbook do Operador (PT-BR)

Este manual é para operadores Linux, equipes de DevOps e auditoria que precisam implantar e operar o GLPI com rastreabilidade e repetibilidade. Você não precisa começar lendo todo o código-fonte. Seguindo esta ordem, os scripts geram runtime, validam pré-requisitos e mostram remediações claras quando algo estiver ausente.

Você pode editar o repositório em Windows, mas os comandos operacionais deste runbook devem ser executados em shell Linux nos servidores de destino.

O perfil esperado é administração prática de Ubuntu com `sudo`, uso de shell e execução básica de Ansible. Se a empresa exige login interativo com usuário, senha e 2FA em cada host, o fluxo local por host já cobre esse cenário sem depender de SSH entre servidores.

## Comece por aqui

A primeira ação é preparar a configuração e ajustar permissões. Copie o template do produto para o ambiente:

```bash
cp config/product.env config/staging.env
```

Abra `config/staging.env` e ajuste os valores obrigatórios, incluindo segredos necessários para o deploy. Depois execute:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
```

Não é necessário `export` manual no fluxo normal. O `glpictl` carrega `config/<environment>.env` automaticamente e usa esta precedência:

1. argumentos da CLI;
2. variáveis já existentes no processo (sobrescrita pontual);
3. `config/<environment>.env`;
4. defaults internos.

## Como a execução funciona

O comando canônico é:

```bash
./scripts/glpictl.sh <environment> <deploy|certify|promote|tls|ops|audit> <action> [target] [scope]
```

O domínio define a área operacional (`deploy`, `tls`, `ops`, `audit`, `certify`, `promote`) e `action/target` definem exatamente o que será alterado.

Quando faltar ferramenta obrigatória, como `ansible-playbook` ou `ansible-inventory`, os scripts oferecem instalação guiada em Ubuntu. Se a instalação falhar ou for recusada, a execução para com remediação explícita para retomada no mesmo ponto.

## Execução em single-server e dual-server

No modelo single-server, defina `TOPOLOGY_MODE=single-server` e mantenha `EXECUTION_HOST_ROLE_DEFAULT=all`.

No modelo dual-server, mantenha `TOPOLOGY_MODE=dual-server`. Se a empresa bloquear SSH direto entre servidores, use `EXECUTION_MODE=local`:

1. No host DB: `deploy check all` e `deploy apply db`.
2. No host APP: `deploy check all`, `deploy apply app`, `deploy apply monitoring`, `deploy apply backup` e `deploy post-check all`.

Se SSH remoto for permitido, use `EXECUTION_MODE=ssh`, configure `NETWORK_SSH_USER` e `NETWORK_SSH_PRIVATE_KEY_PATH`, e mantenha a chave privada com modo `0600`.

## Ordem obrigatória de execução

1. `deploy check all`
2. `deploy apply db`
3. `deploy apply app`
4. `deploy apply monitoring`
5. `deploy apply backup`
6. `deploy post-check all`

Quando `SECURITY_REQUIRE_ORDERED_EXECUTION=true` e o modo efetivo é `SECURITY_MODE=secure`, execução fora de ordem é bloqueada. Em `permissive`, continua com warning e evidência obrigatória de risco aceito.

## O que os comandos principais fazem

| Comando | Onde executar | Finalidade operacional |
|---|---|---|
| `./scripts/glpictl.sh staging deploy check all` | host atual | Executa precheck, valida permissões, valida carregamento de config, materializa runtime, valida inventário e contrato de política antes de alterações mutáveis. |
| `./scripts/glpictl.sh staging deploy apply db` | host DB no dual-server local, ou host orquestrador em modo ssh | Instala e aplica hardening no MariaDB, configura parâmetros, provisiona base/usuário/grants do GLPI e aplica restrições de origem de acesso da app. |
| `./scripts/glpictl.sh staging deploy apply app` | host APP no dual-server local, ou host orquestrador em modo ssh | Instala pacotes da aplicação, publica layout GLPI fora da web root, configura web server + PHP-FPM, aplica template TLS e conectividade com banco. |
| `./scripts/glpictl.sh staging deploy apply monitoring` | APP (e DB conforme escopo) | Instala e configura exporters e baseline de observabilidade com base no runtime. |
| `./scripts/glpictl.sh staging deploy apply backup` | APP (e DB conforme escopo) | Aplica baseline de backup, retenção e artefatos operacionais para validação e restore. |
| `./scripts/glpictl.sh staging deploy post-check all` | host atual | Executa validações pós-implantação e checagens de serviço após etapas mutáveis. |
| `./scripts/glpictl.sh staging tls self-signed` | host APP | Ativa TLS autoassinado, atualiza override de runtime, reaplica app e valida web server antes de reload. |
| `./scripts/glpictl.sh staging tls install-provided` | host APP | Valida caminhos de certificado/chave, atualiza override, reaplica app e recarrega serviço após validação de configuração. |
| `./scripts/glpictl.sh staging ops cert check` | host APP | Lê certificado ativo e alerta sobre vencimento próximo. |
| `./scripts/glpictl.sh staging audit check` | host de auditoria operacional | Consolida checagens de permissão, política, runtime e saúde operacional. |
| `bash scripts/release-readiness.sh staging` | host executor com acesso ao repositório | Gera evidências de prontidão e falha apenas em problemas técnicos críticos. |

## Decisões de TLS e modo de segurança

O fluxo TLS possui três modos: `none`, `self_signed` e `provided`. Você pode começar com `none` em desenvolvimento/homologação controlada, evoluir para `self_signed` e depois migrar para `provided` com certificado válido.

A política de segurança é por execução. `SECURITY_MODE=secure` bloqueia violações de política. `SECURITY_MODE=permissive` permite continuidade, mas registra obrigatoriamente quem aceitou o risco, quando e quais políticas foram violadas.

## Arquivos de runtime e significado

Após `deploy check`, os arquivos são criados em `.runtime/<environment>/`:

- `public.runtime.yml`: baseline não sensível renderizado a partir de `config/<environment>.env`.
- `overrides.runtime.yml`: overrides mutáveis (ex.: mudança de TLS) sem alterar baseline público.
- `secrets.yml`: valores sensíveis; deve permanecer restrito.
- `inventory.runtime.yml`: inventário efetivo consumido pelo Ansible.
- `state/` e `evidence/`: checkpoints, relatórios e trilha de auditoria.

## Matriz de acesso da instalação e assets

Durante a fase de instalação, a aplicação deve expor `/` e resolver o fluxo `/install/install.php` sem retorno 404. Os assets referenciados na página de instalação (`.js` e `.css`) precisam estar acessíveis, e os caminhos sensíveis devem continuar bloqueados (`config/`, `files/`, `vendor/`), mesmo com instalador aberto.

Os checks automáticos validam esse contrato para o engine selecionado no host, consultando loopback local com header de host configurado e confirmando respostas bloqueadas para paths sensíveis.

Se `/` abrir e o redirecionamento do instalador falhar, execute novamente `./scripts/glpictl.sh <env> deploy apply app` e valide o template web do engine selecionado. Para Nginx, a compatibilidade com `/install/install.php` está aplicada sem abrir execução PHP ampla fora do roteador.

## Validação e troubleshooting

A validação mínima pós-implantação é: página GLPI acessível, conectividade com DB funcionando, teste de configuração do web server válido, teste de configuração PHP-FPM válido e evidências de runtime geradas.

Se algo falhar, siga [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md), com cenários para dependências ausentes, host role incorreto, material SSH ausente em modo ssh, caminhos TLS inválidos e comportamento por modo de política.

## Apêndices relacionados

- [Referência de Comandos](appendices/command-reference.md)
- [Entradas e Arquivos de Runtime](appendices/runtime-input-reference.md)
- [Modos TLS](appendices/tls-modes.md)
- [Checagens Operacionais](appendices/operational-checks.md)
- [Matriz de Troubleshooting](appendices/troubleshooting-matrix.md)
