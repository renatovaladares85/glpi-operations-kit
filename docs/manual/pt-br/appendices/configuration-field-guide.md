# Guia de Preenchimento do Ambiente (PT-BR)

Este guia explica como preencher `config/<environment>.env` a partir de `config/product.env`. Ele foi escrito para operadores que ainda não conhecem o kit nem a infraestrutura do cliente.

Use este guia antes de executar `deploy check`, `tls check` ou qualquer operação mutável.

## Regra de ouro

- Valores públicos ficam em `config/<environment>.env`.
- `config/product.env` mantém descomentadas apenas as chaves obrigatórias de baseline.
- Chaves não usadas no cenário atual ficam comentadas com exemplo default preenchido.
- Chaves usadas no cenário atual ficam descomentadas com valores reais do ambiente.
- Segredos obrigatórios de deploy atualmente lidos do ambiente são `DATABASE_PASSWORD` (sempre), além de `DATABASE_ROOT_PASSWORD` e `MONITORING_MYSQLD_EXPORTER_PASSWORD` somente quando `DATABASE_DEPLOYMENT_MODE=self_hosted`.
- Nunca coloque certificados privados, tokens, senhas reais ou dumps em Git.
- Exemplo de segredo forte fictício: `DATABASE_PASSWORD=kit-demo-9f4aT2m7Q1x`.

## Como começar

1. Copie o template: `cp config/product.env config/staging.env`.
2. Preencha primeiro identidade, topologia, rede, DB, app, paths e política.
3. Escolha TLS: `none`, `self_signed` ou `provided`.
4. Configure SSO diretamente no GLPI/IdP quando necessário (fora da orquestração do script).
5. Execute `bash scripts/bootstrap-permissions.sh`.
6. Execute `./scripts/glpictl.sh <environment> deploy check all` antes de qualquer `apply`.
   Exemplo: `./scripts/glpictl.sh staging deploy check all`.

## Como coletar informações

| Área | Quem normalmente fornece | O que pedir |
|---|---|---|
| DNS e rede | Infra/rede | FQDN do GLPI, IP/FQDN do host app, IP/FQDN do host DB, portas liberadas, regra APP -> DB. |
| Sistema operacional | Infra/Linux | Usuário operacional, sudo, grupo `glpiops`, shell Linux, pacotes permitidos. |
| Banco | DBA/infra | Nome da base, usuário de aplicação, senha forte, senha root/provisionamento, porta, bind e origem permitida. |
| TLS | Segurança/PKI | Certificado de servidor HTTPS, cadeia completa, chave privada correspondente, FQDN/SAN. |
| SSO (manual na aplicação) | IAM/Azure/Entra ID | URL pública do GLPI, metadados IdP, mapeamento de claims, grupos e regras JIT configurados diretamente no GLPI. |
| Monitoramento | Observabilidade/NOC | Exporters habilitados, labels, thresholds, rotas de alerta e credencial do exporter DB. |
| Backup | Infra/backup | Diretório, retenção, espaço e criptografia externa se aplicável. |

## Identidade do produto e ambiente

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `PRODUCT_NAME` | Nome visível do produto. | Use o nome padrão ou o nome comercial interno do kit. | Deve ser texto simples. |
| `PRODUCT_SLUG` | Identificador curto em minúsculas. | Derive de `PRODUCT_NAME`, usando hífen. | Evite espaços e acentos. |
| `PRODUCT_DEPLOYMENT_LABEL` | Rótulo desta implantação. | Defina algo como `staging-kit` ou `production-kit`. | Deve diferenciar implantações. |
| `CUSTOMER_DISPLAY_NAME` | Nome exibido do cliente/ambiente. | Use nome genérico definido pela política local, sem dados sensíveis. | Não hardcode cliente real em template reutilizável. |
| `CUSTOMER_SHORT_NAME` | Identificador curto do cliente. | Use slug genérico, por exemplo `example-customer`. | Usado em labels e dashboards. |
| `ENVIRONMENT_NAME` | Nome usado na CLI e runtime. | Deve bater com o arquivo: `config/staging.env` usa `staging`. | `./scripts/glpictl.sh staging ...` deve encontrar o arquivo. |
| `ENVIRONMENT_STAGE` | Estágio lógico. | Use `staging`, `production`, `dev` ou equivalente. | Deve refletir o risco operacional. |

## Execução e topologia

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `EXECUTION_MODE` | `local` ou `ssh`. | Use `local` quando cada host executa seus próprios comandos; use `ssh` só se houver orquestração remota permitida. | Em `ssh`, chave e acesso remoto viram obrigatórios. |
| `EXECUTION_HOST_ROLE_DEFAULT` | `app`, `db` ou `all`. | Em single-server use `all`; em dual-server local use `db` no host DB e `app` no host APP. | Evita aplicar etapa no host errado. |
| `TOPOLOGY_MODE` | `single-server` ou `dual-server`. | Confirme se APP e DB ficam no mesmo host ou separados. | Deve combinar com os hosts informados. |
| `DATABASE_DEPLOYMENT_MODE` | `self_hosted` ou `managed`. | Use `self_hosted` quando o host DB é gerenciado por este kit; use `managed` para DB externo como AWS RDS. | `managed` desativa ações de host DB Linux (`deploy apply db`, ops de host DB). |
| `TOPOLOGY_APP_ALIAS` | Alias Ansible do host app. | Use nome curto, por exemplo `app-node`. | Não precisa resolver DNS. |
| `TOPOLOGY_APP_HOST` | IP ou FQDN do host app. | Peça à equipe de rede/infra. | Deve ser alcançável pelo executor no modo `ssh`. |
| `TOPOLOGY_DB_ALIAS` | Alias Ansible do host DB. | Use nome curto, por exemplo `db-node`. | Não precisa resolver DNS. |
| `TOPOLOGY_DB_HOST` | IP ou FQDN do host DB. | Peça à equipe de rede/infra. | Em dual-server deve apontar ao DB real. |

## Rede, SSH e acesso ao banco

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `NETWORK_SSH_USER` | Usuário Linux para SSH. | Peça à equipe Linux; use conta nominal ou operacional definida pela política local. | Necessário só em `EXECUTION_MODE=ssh`. |
| `NETWORK_SSH_PRIVATE_KEY_PATH` | Caminho da chave privada SSH no host executor. | Gere ou solicite chave por ambiente; mantenha permissão `0600`. | Necessário só em `EXECUTION_MODE=ssh`. |
| `NETWORK_DATABASE_APP_ACCESS_HOST` | Origem que receberá grant no DB no modo restricted. | Use o endereço do host APP visto pelo DB. | Exemplo: `NETWORK_DATABASE_APP_ACCESS_HOST=192.0.2.10`. |
| `NETWORK_DATABASE_ACCESS_MODE` | Modo da política de acesso ao DB. | Use `restricted` para modo com allowlist ou `open` para modo sem restrição de origem. | Exemplos: `NETWORK_DATABASE_ACCESS_MODE=restricted` ou `NETWORK_DATABASE_ACCESS_MODE=open`. |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | Lista CSV de origens no modo restricted. | Use hosts separados por vírgula no modo restricted. Mantenha a chave ativa e vazia no modo open. | Exemplo restricted: `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=192.0.2.10,192.0.2.11`. Exemplo open: `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS=`. |

Observação de risco:
`NETWORK_DATABASE_ACCESS_MODE=open` remove restrição de origem tanto no firewall quanto no grant do banco. Use apenas com aceite explícito de risco.

## GLPI, web server e PHP

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `GLPI_VERSION` | Versão GLPI alvo. | Use a versão homologada para o projeto, por exemplo `11.0.7` quando essa for a baseline aceita no projeto. | Deve ser compatível com PHP mínimo 8.2. |
| `GLPI_DOMAIN` | Hostname usado para acessar o GLPI. | Peça o FQDN ao time de DNS. | Deve existir no certificado quando TLS estiver ativo. |
| `WEB_SERVER_TYPE` | `nginx`, `apache` ou `lighttpd`. | Escolha conforme padrão do ambiente. O kit Linux não automatiza IIS. | Só um engine web deve estar ativo no host. |
| `GLPI_UPLOAD_MAX_FILESIZE` | Limite de upload PHP. | Defina conforme anexos esperados. | Use sintaxe PHP, por exemplo `32M` ou `128M`. |
| `GLPI_POST_MAX_SIZE` | Limite de POST PHP. | Deve ser igual ou maior que upload. | Use sintaxe PHP. |
| `GLPI_MEMORY_LIMIT` | Memória máxima PHP. | Ajuste conforme perfil de uso. | Use `512M` como baseline seguro inicial. |
| `GLPI_MAX_EXECUTION_TIME` | Tempo máximo de execução PHP. | Aumente se importações forem longas. | Inteiro em segundos. |
| `GLPI_OPCACHE_MEMORY_CONSUMPTION` | Memória OPcache em MB. | Ajuste conforme tamanho do ambiente. | Inteiro, exemplo `192`. |
| `GLPI_CRON_SCHEDULE` | Agenda cron GLPI. | Use padrão de 5 minutos se não houver política diferente. | Precisa estar entre aspas por conter espaços. |
| `GLPI_FILESYSTEM_OWNER` | Dono dos diretórios graváveis. | Normalmente o usuário do web server, como `www-data`. | Deve existir no host. |
| `GLPI_FILESYSTEM_GROUP` | Grupo dos diretórios graváveis. | Normalmente `www-data`. | Deve existir no host. |
| `GLPI_APP_PACKAGES` | Lista CSV de pacotes app ou vazio. | Deixe vazio para o renderer escolher por `WEB_SERVER_TYPE`; preencha só se a equipe assumir override total. | Override manual precisa incluir todos os pacotes necessários. |

## Banco de dados

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `DATABASE_NAME` | Nome da base/schema GLPI. | Defina com DBA; exemplo `glpi_operational`. | Use identificador SQL simples. |
| `DATABASE_USER` | Usuário SQL do GLPI. | Defina com DBA; prefira nome contextual não óbvio, exemplo `nehemiah_glpi`. | Evite `admin`, `root`, `glpi`. |
| `DATABASE_PASSWORD` | Senha do usuário SQL do GLPI. | Gere segredo aleatório forte. | Secret obrigatório; não commitar. |
| `DATABASE_ROOT_PASSWORD` | Senha root/provisionamento MariaDB. | Gere ou solicite ao DBA. | Obrigatório quando `DATABASE_DEPLOYMENT_MODE=self_hosted`; não commitar. |
| `DATABASE_PORT` | Porta TCP do MariaDB/MySQL. | Normalmente `3306`. | Firewall deve permitir origem APP. |
| `DATABASE_BIND_ADDRESS` | Endereço de bind do DB. | Use `0.0.0.0` para escutar em todas as interfaces necessárias ou IP específico do DB. | Deve combinar com política de firewall. |
| `DATABASE_PACKAGES` | Pacotes DB em CSV. | Mantenha padrão salvo necessidade do SO. | Baseline atual: `mariadb-server,mariadb-client,python3-pymysql`. |

## PHP-FPM e portas web

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `PHP_FPM_SERVICE_NAME` | Nome do serviço PHP-FPM. | Confirme versão instalada no host, exemplo `php8.3-fpm`. | Exemplo de validação: `systemctl status php8.3-fpm`. |
| `PHP_FPM_SOCKET` | Socket Unix do PHP-FPM. | Confirme padrão da distro/PHP. | Deve bater com o template web. |
| `PHP_FPM_PM` | `static`, `dynamic` ou `ondemand`. | Use `dynamic` salvo requisito específico. | Deve ser aceito pelo PHP-FPM. |
| `WEB_HTTP_PORT` | Porta HTTP. | Normalmente `80`. | Usada pelo template do web server selecionado (`nginx`, `apache` ou `lighttpd`). |
| `WEB_HTTPS_PORT` | Porta HTTPS. | Normalmente `443`. | Usada pelo template do web server selecionado (`nginx`, `apache` ou `lighttpd`). |

## TLS e certificados

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `TLS_MODE` | `none`, `self_signed` ou `provided`. | Use `provided` para produção; `self_signed` só para teste/controlado; `none` só quando política permitir. | Política `SECURITY_REQUIRE_*` pode bloquear. |
| `TLS_COMMON_NAME` | FQDN principal do certificado. | Use o host público do GLPI, normalmente igual a `GLPI_DOMAIN`. | Deve estar também no SAN do certificado moderno. |
| `TLS_CERTIFICATE_PATH` | Caminho final do certificado no host APP. | Defina path seguro, exemplo `/etc/ssl/certs/glpi-example.crt`. | É destino no servidor, não origem local. |
| `TLS_PRIVATE_KEY_PATH` | Caminho final da chave privada no host APP. | Defina path protegido, exemplo `/etc/ssl/private/glpi-example.key`. | Chave deve ser restrita e fora do webroot. |
| `TLS_PROVIDED_LOCAL_CERT_PATH` | Arquivo local de origem do certificado/cadeia. | Preencha no fluxo `provided` com fullchain PEM recebido da CA. | O arquivo deve existir no host executor. |
| `TLS_PROVIDED_LOCAL_KEY_PATH` | Arquivo local de origem da chave privada. | Preencha no fluxo `provided` com chave correspondente ao certificado. | O arquivo deve existir e não pode ser chave pública. |

Para certificado `provided`, solicite um certificado de servidor HTTPS, não de cliente. O certificado deve conter `serverAuth`, FQDN em SAN, cadeia completa em PEM e chave privada PEM correspondente. mTLS/client certificate não é automatizado pelo kit atual.

## Backup

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `BACKUP_BASE_DIR` | Diretório base de backup no alvo. | Peça à infra o path definido pela política local; padrão `/var/backups/glpi`. | Deve ter espaço e permissão restrita. |
| `BACKUP_RETENTION_DAYS` | Retenção em dias. | Use a política local do ambiente/projeto. | Inteiro positivo. |

## Monitoramento e alertas

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `MONITORING_NODE_EXPORTER_ENABLED` | `true` ou `false`. | Habilite quando host metrics forem coletadas. | Booleano. |
| `MONITORING_MYSQLD_EXPORTER_ENABLED` | `true` ou `false`. | Habilite quando métricas MariaDB/MySQL forem coletadas. | Booleano. |
| `MONITORING_MYSQLD_EXPORTER_USER` | Usuário SQL do exporter. | Use nome contextual, exemplo `issachar_monitor`. | Evite nomes genéricos. |
| `MONITORING_MYSQLD_EXPORTER_PASSWORD` | Senha do exporter. | Gere segredo aleatório forte. | Obrigatório quando `DATABASE_DEPLOYMENT_MODE=self_hosted`; não commitar. |
| `MONITORING_LABELS_JSON` | Labels em JSON de uma linha. | Defina produto, serviço, cliente e ambiente. | Deve ser JSON objeto válido. |
| `MONITORING_THRESHOLDS_JSON` | Thresholds em JSON de uma linha. | Peça à observabilidade/NOC. | Deve conter números coerentes. |
| `MONITORING_SCRAPE_PROFILES_JSON` | Perfis de coleta em JSON. | Use intervalo e timeout definidos pela política local. | JSON objeto válido, exemplo `{"default":{"interval":"30s","timeout":"10s"}}`. |
| `MONITORING_DASHBOARD_PROFILE` | Nome do perfil de dashboard. | Use padrão `glpi-standard` ou perfil acordado. | Texto simples. |
| `MONITORING_ALERT_ROUTES_JSON` | Roteamento de alertas em JSON. | Peça receiver e escalonamento ao NOC. | JSON objeto válido. |
| `ALERTING_TLS_EXPIRY_WARNING_DAYS` | Dias antes do vencimento TLS para alerta. | Use política de segurança, padrão `30`. | Inteiro positivo. |
| `ALERTING_BACKUP_FAILURE_ENABLED` | `true` ou `false`. | Mantenha `true` salvo exceção formal. | Booleano. |
| `ALERTING_SERVICE_DOWN_ENABLED` | `true` ou `false`. | Mantenha `true` salvo exceção formal. | Booleano. |

## Política e segurança operacional

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `SECURITY_ALLOW_INSECURE_NON_PRODUCTION` | Exceção para ambiente não produtivo. | Use conforme política interna. | Não substitui `SECURITY_MODE`. |
| `SECURITY_REQUIRE_TLS` | Exigir `TLS_MODE=provided`. | Ative quando compliance exigir certificado válido. | Em `secure`, pode bloquear. |
| `SECURITY_REQUIRE_HTTPS` | Exigir HTTPS. | Ative quando HTTP não for aceitável. | Aceita `self_signed` ou `provided`, conforme política. |
| `SECURITY_REQUIRE_PROMOTION_GATE` | Exigir gate de promoção. | Use em fluxo staging -> production. | Exige artefato de certificação. |
| `SECURITY_REQUIRE_ORDERED_EXECUTION` | Exigir ordem de deploy. | Mantenha `true` salvo exceção. | Bloqueia ordem incorreta em `secure`. |
| `OPERATIONS_ASSUME_DB_APPLIED` | Confirmar DB já aplicado em outro host. | Use no host APP em dual-server local quando DB foi aplicado separadamente. | Afeta validação de ordem. |

## Paths GLPI

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `PATH_GLPI_RELEASE_ROOT` | Raiz de extração do release. | Padrão `/usr/share`. | Deve existir/criar com permissão adequada. |
| `PATH_GLPI_INSTALL_DIR` | Diretório de instalação GLPI. | Padrão `/usr/share/glpi`. | Webroot deve apontar para `public` dentro dele. |
| `PATH_GLPI_CONFIG_DIR` | Diretório de config fora do webroot. | Padrão `/etc/glpi`. | Nunca expor via web. |
| `PATH_GLPI_VAR_DIR` | Diretório de dados/files fora do webroot. | Padrão `/var/lib/glpi/files`. | Deve ser gravável pelo usuário web. |
| `PATH_GLPI_PLUGIN_DIR` | Diretório de plugins. | Padrão `/var/lib/glpi/plugins`. | Plugins manuais devem ser instalados e validados diretamente no GLPI quando aplicável. |
| `PATH_GLPI_LOG_DIR` | Diretório de logs GLPI. | Padrão `/var/log/glpi`. | Deve ficar fora do webroot. |

## Operações

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `OPERATIONS_TIMEZONE` | Timezone IANA. | Exemplo `America/Sao_Paulo`. | Use valor de `timedatectl list-timezones`. |
| `GLPI_TIMEZONE_SUPPORT_ENABLED` | Habilita o fluxo de readiness de timezone do GLPI. | `true` para habilitar checks/aplicação de timezone em PHP + BD. | Padrão `false`. |
| `GLPI_TIMEZONE_DB_MODE` | Controla o fluxo de timezone na camada de BD. | `disabled`, `validate`, `apply`. | Em BD gerenciado, padrão efetivo é validate quando o suporte está habilitado. |
| `GLPI_TIMEZONE_DB_LEGACY_GRANT` | Grant legado opcional para listagem de timezone no BD. | `true` apenas para compatibilidade antiga. | Padrão `false` (recomendado para GLPI moderno). |
| `OPERATIONS_GLPI_CRON_SCHEDULE` | Agenda cron operacional. | Normalmente igual a `GLPI_CRON_SCHEDULE`. | Precisa estar entre aspas. |
| `OPERATIONS_REQUIRED_OPS_GROUP` | Grupo Linux dos operadores. | Padrão `glpiops`. | Operador deve pertencer ao grupo. |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | `secure` ou `permissive`. | Use `secure` por padrão. | `permissive` exige justificativa. |
| `OPERATIONS_PERMISSIVE_JUSTIFICATION` | Justificativa para permissive. | Preencha só quando permissive for necessário e autorizado pela política local. | Deve explicar risco aceito. |

## Perfis de recurso

`RESOURCE_PROFILE_ACTIVE` escolhe `small`, `medium` ou `large`. Os valores abaixo ajustam PHP-FPM e MariaDB para cada família. Altere somente com base em capacidade do host, volume de usuários, orientação DBA/infra ou teste de carga.

| Chave | O que controla | Formato |
|---|---|---|
| `RESOURCE_PROFILE_ACTIVE` | Perfil ativo renderizado para runtime. | `small`, `medium`, `large` |
| `RESOURCE_PROFILE_SMALL_PHP_MAX_CHILDREN` | Máximo de workers PHP no perfil small. | inteiro |
| `RESOURCE_PROFILE_SMALL_PHP_START_SERVERS` | Workers PHP iniciais no perfil small. | inteiro |
| `RESOURCE_PROFILE_SMALL_PHP_MIN_SPARE_SERVERS` | Mínimo de workers ociosos no perfil small. | inteiro |
| `RESOURCE_PROFILE_SMALL_PHP_MAX_SPARE_SERVERS` | Máximo de workers ociosos no perfil small. | inteiro |
| `RESOURCE_PROFILE_SMALL_PHP_MAX_REQUESTS` | Reciclagem de worker PHP no perfil small. | inteiro |
| `RESOURCE_PROFILE_SMALL_MARIADB_INNODB_BUFFER_POOL_SIZE` | Buffer pool MariaDB no perfil small. | tamanho, ex. `2G` |
| `RESOURCE_PROFILE_SMALL_MARIADB_MAX_CONNECTIONS` | Conexões MariaDB no perfil small. | inteiro |
| `RESOURCE_PROFILE_SMALL_MARIADB_TMP_TABLE_SIZE` | Tamanho de tabela temporária no perfil small. | tamanho |
| `RESOURCE_PROFILE_SMALL_MARIADB_MAX_HEAP_TABLE_SIZE` | Heap table no perfil small. | tamanho |
| `RESOURCE_PROFILE_SMALL_MARIADB_SLOW_QUERY_LOG` | Slow query log no perfil small. | `0` ou `1` |
| `RESOURCE_PROFILE_SMALL_MARIADB_LONG_QUERY_TIME` | Tempo para slow query no perfil small. | segundos |
| `RESOURCE_PROFILE_MEDIUM_PHP_MAX_CHILDREN` | Máximo de workers PHP no perfil medium. | inteiro |
| `RESOURCE_PROFILE_MEDIUM_PHP_START_SERVERS` | Workers PHP iniciais no perfil medium. | inteiro |
| `RESOURCE_PROFILE_MEDIUM_PHP_MIN_SPARE_SERVERS` | Mínimo de workers ociosos no perfil medium. | inteiro |
| `RESOURCE_PROFILE_MEDIUM_PHP_MAX_SPARE_SERVERS` | Máximo de workers ociosos no perfil medium. | inteiro |
| `RESOURCE_PROFILE_MEDIUM_PHP_MAX_REQUESTS` | Reciclagem de worker PHP no perfil medium. | inteiro |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_INNODB_BUFFER_POOL_SIZE` | Buffer pool MariaDB no perfil medium. | tamanho, ex. `8G` |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_MAX_CONNECTIONS` | Conexões MariaDB no perfil medium. | inteiro |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_TMP_TABLE_SIZE` | Tamanho de tabela temporária no perfil medium. | tamanho |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_MAX_HEAP_TABLE_SIZE` | Heap table no perfil medium. | tamanho |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_SLOW_QUERY_LOG` | Slow query log no perfil medium. | `0` ou `1` |
| `RESOURCE_PROFILE_MEDIUM_MARIADB_LONG_QUERY_TIME` | Tempo para slow query no perfil medium. | segundos |
| `RESOURCE_PROFILE_LARGE_PHP_MAX_CHILDREN` | Máximo de workers PHP no perfil large. | inteiro |
| `RESOURCE_PROFILE_LARGE_PHP_START_SERVERS` | Workers PHP iniciais no perfil large. | inteiro |
| `RESOURCE_PROFILE_LARGE_PHP_MIN_SPARE_SERVERS` | Mínimo de workers ociosos no perfil large. | inteiro |
| `RESOURCE_PROFILE_LARGE_PHP_MAX_SPARE_SERVERS` | Máximo de workers ociosos no perfil large. | inteiro |
| `RESOURCE_PROFILE_LARGE_PHP_MAX_REQUESTS` | Reciclagem de worker PHP no perfil large. | inteiro |
| `RESOURCE_PROFILE_LARGE_MARIADB_INNODB_BUFFER_POOL_SIZE` | Buffer pool MariaDB no perfil large. | tamanho, ex. `24G` |
| `RESOURCE_PROFILE_LARGE_MARIADB_MAX_CONNECTIONS` | Conexões MariaDB no perfil large. | inteiro |
| `RESOURCE_PROFILE_LARGE_MARIADB_TMP_TABLE_SIZE` | Tamanho de tabela temporária no perfil large. | tamanho |
| `RESOURCE_PROFILE_LARGE_MARIADB_MAX_HEAP_TABLE_SIZE` | Heap table no perfil large. | tamanho |
| `RESOURCE_PROFILE_LARGE_MARIADB_SLOW_QUERY_LOG` | Slow query log no perfil large. | `0` ou `1` |
| `RESOURCE_PROFILE_LARGE_MARIADB_LONG_QUERY_TIME` | Tempo para slow query no perfil large. | segundos |

## Validação antes da instalação

Execute nesta ordem:

```bash
bash scripts/bootstrap-permissions.sh
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging tls check
```

Se algum check falhar, corrija o valor indicado antes de executar `apply`.
