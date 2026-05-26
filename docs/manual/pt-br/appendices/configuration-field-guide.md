# Guia de Preenchimento do Ambiente (PT-BR)

Este guia explica como preencher `config/<environment>.env` a partir de `config/product.env`. Ele foi escrito para operadores que ainda não conhecem o kit nem a infraestrutura do cliente.

Use este guia antes de executar `deploy check`, `auth check`, `tls check` ou qualquer operação mutável.

## Regra de ouro

- Valores públicos ficam em `config/<environment>.env`.
- Segredos obrigatórios de deploy atualmente lidos do ambiente são `DATABASE_PASSWORD`, `DATABASE_ROOT_PASSWORD` e `MONITORING_MYSQLD_EXPORTER_PASSWORD`.
- Segredos de autenticação externa devem permanecer somente em `.runtime/<environment>/secrets.yml`, como `auth_saml_x509_certificate`, `ldap_bind_password` e `oidc_client_secret`.
- Nunca coloque certificados privados, tokens, senhas reais ou dumps em Git.
- Em exemplos, substitua valores como `<generate-high-entropy-password>` por segredos aleatórios fortes antes da execução real.

## Como começar

1. Copie o template: `cp config/product.env config/staging.env`.
2. Preencha primeiro identidade, topologia, rede, DB, app, paths e política.
3. Escolha TLS: `none`, `self_signed` ou `provided`.
4. Se houver SSO, preencha `AUTH_*`, `SSO_*` e coloque segredos somente em `.runtime/<environment>/secrets.yml`.
5. Execute `bash scripts/bootstrap-permissions.sh`.
6. Execute `./scripts/glpictl.sh <environment> deploy check all` antes de qualquer `apply`.

## Como coletar informações

| Área | Quem normalmente fornece | O que pedir |
|---|---|---|
| DNS e rede | Infra/rede | FQDN do GLPI, IP/FQDN do host app, IP/FQDN do host DB, portas liberadas, regra APP -> DB. |
| Sistema operacional | Infra/Linux | Usuário operacional, sudo, grupo `glpiops`, shell Linux, pacotes permitidos. |
| Banco | DBA/infra | Nome da base, usuário de aplicação, senha forte, senha root/provisionamento, porta, bind e origem permitida. |
| TLS | Segurança/PKI | Certificado de servidor HTTPS, cadeia completa, chave privada correspondente, FQDN/SAN. |
| SSO | IAM/Azure/Entra ID | URL pública HTTPS, Entity ID, ACS/Reply URL, Logout URL, claims, grupos e certificado público do IdP. |
| Monitoramento | Observabilidade/NOC | Exporters habilitados, labels, thresholds, rotas de alerta e credencial do exporter DB. |
| Backup | Infra/backup | Diretório, retenção, espaço, criptografia externa se aplicável e janela de restore. |

## Identidade do produto e ambiente

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `PRODUCT_NAME` | Nome visível do produto. | Use o nome padrão ou o nome comercial interno do kit. | Deve ser texto simples. |
| `PRODUCT_SLUG` | Identificador curto em minúsculas. | Derive de `PRODUCT_NAME`, usando hífen. | Evite espaços e acentos. |
| `PRODUCT_DEPLOYMENT_LABEL` | Rótulo desta implantação. | Defina algo como `staging-kit` ou `production-kit`. | Deve diferenciar implantações. |
| `CUSTOMER_DISPLAY_NAME` | Nome exibido do cliente/ambiente. | Use nome genérico ou aprovado, sem dados sensíveis. | Não hardcode cliente real em template reutilizável. |
| `CUSTOMER_SHORT_NAME` | Identificador curto do cliente. | Use slug genérico, por exemplo `example-customer`. | Usado em labels e dashboards. |
| `ENVIRONMENT_NAME` | Nome usado na CLI e runtime. | Deve bater com o arquivo: `config/staging.env` usa `staging`. | `./scripts/glpictl.sh staging ...` deve encontrar o arquivo. |
| `ENVIRONMENT_STAGE` | Estágio lógico. | Use `staging`, `production`, `dev` ou equivalente. | Deve refletir o risco operacional. |

## Execução e topologia

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `EXECUTION_MODE` | `local` ou `ssh`. | Use `local` quando cada host executa seus próprios comandos; use `ssh` só se houver orquestração remota permitida. | Em `ssh`, chave e acesso remoto viram obrigatórios. |
| `EXECUTION_HOST_ROLE_DEFAULT` | `app`, `db` ou `all`. | Em single-server use `all`; em dual-server local use `db` no host DB e `app` no host APP. | Evita aplicar etapa no host errado. |
| `TOPOLOGY_MODE` | `single-server` ou `dual-server`. | Confirme se APP e DB ficam no mesmo host ou separados. | Deve combinar com os hosts informados. |
| `TOPOLOGY_APP_ALIAS` | Alias Ansible do host app. | Use nome curto, por exemplo `app-node`. | Não precisa resolver DNS. |
| `TOPOLOGY_APP_HOST` | IP ou FQDN do host app. | Peça à equipe de rede/infra. | Deve ser alcançável pelo executor no modo `ssh`. |
| `TOPOLOGY_DB_ALIAS` | Alias Ansible do host DB. | Use nome curto, por exemplo `db-node`. | Não precisa resolver DNS. |
| `TOPOLOGY_DB_HOST` | IP ou FQDN do host DB. | Peça à equipe de rede/infra. | Em dual-server deve apontar ao DB real. |

## Rede, SSH e acesso ao banco

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `NETWORK_SSH_USER` | Usuário Linux para SSH. | Peça à equipe Linux; use conta nominal ou operacional aprovada. | Necessário só em `EXECUTION_MODE=ssh`. |
| `NETWORK_SSH_PRIVATE_KEY_PATH` | Caminho da chave privada SSH no host executor. | Gere ou solicite chave por ambiente; mantenha permissão `0600`. | Necessário só em `EXECUTION_MODE=ssh`. |
| `NETWORK_DATABASE_APP_ACCESS_HOST` | Origem que receberá grant no DB. | Normalmente é o IP/FQDN do APP visto pelo DB. | Deve bater com a origem real da conexão APP -> DB. |
| `NETWORK_DATABASE_ACCESS_MODE` | Modo da política de acesso ao DB. | Use `restricted` para limitar origens ou `open` para permitir qualquer origem. | Quando omitido, o padrão é `restricted`. |
| `NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS` | Lista CSV de origens permitidas usada no modo restricted. | Inclua APP e, se necessário, host de manutenção aprovado. | Não use espaços; exemplo `192.0.2.10,192.0.2.11`. |

Observação de risco:
`NETWORK_DATABASE_ACCESS_MODE=open` remove restrição de origem tanto no firewall quanto no grant do banco. Use apenas com aceite explícito de risco.

## GLPI, web server e PHP

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `GLPI_VERSION` | Versão GLPI alvo. | Use a versão homologada para o projeto, por exemplo `11.0.7` quando essa for a baseline aprovada. | Deve ser compatível com PHP mínimo 8.2. |
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
| `DATABASE_ROOT_PASSWORD` | Senha root/provisionamento MariaDB. | Gere ou solicite ao DBA. | Secret obrigatório; não commitar. |
| `DATABASE_PORT` | Porta TCP do MariaDB/MySQL. | Normalmente `3306`. | Firewall deve permitir origem APP. |
| `DATABASE_BIND_ADDRESS` | Endereço de bind do DB. | Use `0.0.0.0` para escutar em todas as interfaces aprovadas ou IP específico do DB. | Deve combinar com política de firewall. |
| `DATABASE_PACKAGES` | Pacotes DB em CSV. | Mantenha padrão salvo necessidade do SO. | Baseline atual: `mariadb-server,mariadb-client,python3-pymysql`. |

## PHP-FPM e portas web

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `PHP_FPM_SERVICE_NAME` | Nome do serviço PHP-FPM. | Confirme versão instalada no host, exemplo `php8.3-fpm`. | `systemctl status <servico>` deve existir após instalação. |
| `PHP_FPM_SOCKET` | Socket Unix do PHP-FPM. | Confirme padrão da distro/PHP. | Deve bater com o template web. |
| `PHP_FPM_PM` | `static`, `dynamic` ou `ondemand`. | Use `dynamic` salvo requisito específico. | Deve ser aceito pelo PHP-FPM. |
| `NGINX_HTTP_PORT` | Porta HTTP. | Normalmente `80`. | Usada por template Nginx. |
| `NGINX_HTTPS_PORT` | Porta HTTPS. | Normalmente `443`. | Usada por template Nginx. |

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
| `BACKUP_BASE_DIR` | Diretório base de backup no alvo. | Peça path aprovado pela infra; padrão `/var/backups/glpi`. | Deve ter espaço e permissão restrita. |
| `BACKUP_RETENTION_DAYS` | Retenção em dias. | Use política do ambiente, exemplo `14` staging e `30` production. | Inteiro positivo. |

## Monitoramento e alertas

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `MONITORING_NODE_EXPORTER_ENABLED` | `true` ou `false`. | Habilite quando host metrics forem coletadas. | Booleano. |
| `MONITORING_MYSQLD_EXPORTER_ENABLED` | `true` ou `false`. | Habilite quando métricas MariaDB/MySQL forem coletadas. | Booleano. |
| `MONITORING_MYSQLD_EXPORTER_USER` | Usuário SQL do exporter. | Use nome contextual, exemplo `issachar_monitor`. | Evite nomes genéricos. |
| `MONITORING_MYSQLD_EXPORTER_PASSWORD` | Senha do exporter. | Gere segredo aleatório forte. | Secret obrigatório; não commitar. |
| `MONITORING_LABELS_JSON` | Labels em JSON de uma linha. | Defina produto, serviço, cliente e ambiente. | Deve ser JSON objeto válido. |
| `MONITORING_THRESHOLDS_JSON` | Thresholds em JSON de uma linha. | Peça à observabilidade/NOC. | Deve conter números coerentes. |
| `MONITORING_SCRAPE_PROFILES_JSON` | Perfis de coleta em JSON. | Use intervalo e timeout aprovados. | JSON objeto válido, exemplo `{"default":{"interval":"30s","timeout":"10s"}}`. |
| `MONITORING_DASHBOARD_PROFILE` | Nome do perfil de dashboard. | Use padrão `glpi-standard` ou perfil acordado. | Texto simples. |
| `MONITORING_ALERT_ROUTES_JSON` | Roteamento de alertas em JSON. | Peça receiver e escalonamento ao NOC. | JSON objeto válido. |
| `ALERTING_TLS_EXPIRY_WARNING_DAYS` | Dias antes do vencimento TLS para alerta. | Use política de segurança, padrão `30`. | Inteiro positivo. |
| `ALERTING_BACKUP_FAILURE_ENABLED` | `true` ou `false`. | Mantenha `true` salvo exceção formal. | Booleano. |
| `ALERTING_SERVICE_DOWN_ENABLED` | `true` ou `false`. | Mantenha `true` salvo exceção formal. | Booleano. |

## Auth, SSO, LDAP, SAML e OIDC

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `AUTH_MODE` | `local`, `ldap`, `saml` ou `oidc`. | Use `local` para manter login local; use externo só quando IAM aprovar. | `local` não altera comportamento funcional. |
| `AUTH_EXTERNAL_ENABLED` | `true` se houver provedor externo. | Marque conforme decisão IAM. | Deve ser coerente com `AUTH_MODE`. |
| `AUTH_LDAP_ENABLED` | `true` para preparar/validar LDAP. | Use se LDAP for parte da solução. | O kit documenta/prepara; não inventa segredos. |
| `AUTH_SAML_ENABLED` | `true` para preparar/validar SAML. | Use com Entra ID/SAML e plugin manual. | Exige URL pública HTTPS quando aplicável. |
| `AUTH_OIDC_ENABLED` | `true` para preparar/validar OIDC. | Use somente se implementação/plugin OIDC for aprovada fora do kit. | Sem SCIM e sem plugin pago automático. |
| `SSO_PROVIDER` | Nome do provedor. | Exemplo `Azure Entra ID`. | Usado em evidências/checklists. |
| `SSO_PROTOCOL` | `saml`, `oidc`, `ldap` ou rótulo livre. | Normalmente igual ao `AUTH_MODE` externo. | Usado em evidências. |
| `SSO_PUBLIC_URL` | URL pública HTTPS do GLPI. | Peça ao time DNS/rede; exemplo `https://glpi.company.com`. | SAML/OIDC exigem `https://`. |
| `SSO_REQUIRE_PUBLIC_URL` | `true` ou `false`. | Mantenha `true` quando auth externa estiver habilitada. | Bloqueia falta de URL quando necessário. |
| `AUTH_SAML_PLUGIN_EXPECTED` | `true` quando plugin SAML deve existir. | Mantenha `true` em SAML. | O kit só detecta; não instala plugin. |
| `AUTH_SAML_PLUGIN_NAME` | Diretório/nome do plugin. | Padrão `saml`, conforme Marketplace instalado manualmente. | Deve existir no diretório de plugins quando SAML estiver ativo. |
| `AUTH_SAML_ENTITY_ID` | Entity ID do SP. | Deixe vazio para derivar de `SSO_PUBLIC_URL`, ou preencha conforme IAM. | Se vazio, vira `${SSO_PUBLIC_URL}`. |
| `AUTH_SAML_ACS_URL` | Reply/ACS URL. | Deixe vazio para derivar. | Se vazio, vira `${SSO_PUBLIC_URL}/front/saml.php`. |
| `AUTH_SAML_LOGOUT_URL` | Logout URL. | Deixe vazio para derivar. | Se vazio, vira `${SSO_PUBLIC_URL}/front/saml_logout.php`. |
| `AUTH_SAML_NAMEID_FORMAT` | Formato NameID. | Use padrão email se IAM não exigir outro. | Valor padrão é URN de emailAddress. |
| `AUTH_SAML_IDP_ENTITY_ID` | Entity ID do IdP. | Copie dos metadados Entra ID/IdP. | Não é segredo. |
| `AUTH_SAML_IDP_SSO_URL` | URL de login do IdP. | Copie dos metadados Entra ID/IdP. | Deve ser HTTPS. |
| `AUTH_SAML_IDP_SLO_URL` | URL de logout do IdP. | Copie se o IdP fornecer. | Pode ficar vazio se não usado. |
| `AUTH_SAML_CLAIM_EMAIL` | Nome do claim de email. | Defina conforme mapeamento IAM. | Exemplo `email`. |
| `AUTH_SAML_CLAIM_USERNAME` | Nome do claim de usuário. | Defina conforme IAM. | Exemplo `username`. |
| `AUTH_SAML_CLAIM_FIRSTNAME` | Claim de primeiro nome. | Defina conforme IAM. | Exemplo `firstname`. |
| `AUTH_SAML_CLAIM_LASTNAME` | Claim de sobrenome. | Defina conforme IAM. | Exemplo `lastname`. |
| `AUTH_SAML_CLAIM_GROUPS` | Claim de grupos. | Defina conforme IAM. | Exemplo `groups`. |
| `AUTH_JIT_ENABLED` | `true` para indicar provisionamento JIT no checklist. | Use conforme política GLPI/IAM. | Evidência, não remove login local. |
| `AUTH_DEFAULT_PROFILE` | Perfil GLPI padrão. | Exemplo `Self-Service`. | Deve existir/ser configurado no GLPI se usado. |
| `AUTH_GROUP_ADMIN` | Grupo IAM para admins GLPI. | Peça ao IAM. | Exemplo `GLPI-Admins`. |
| `AUTH_GROUP_TECHNICIAN` | Grupo IAM para técnicos. | Peça ao IAM. | Exemplo `GLPI-Technicians`. |
| `AUTH_GROUP_USER` | Grupo IAM para usuários. | Peça ao IAM. | Exemplo `GLPI-Users`. |

## Política e segurança operacional

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `SECURITY_SSO_ENABLED` | Estado real de SSO. | `true` só quando SSO estiver efetivamente pronto. | Usado por policy checks. |
| `SECURITY_ALLOW_INSECURE_NON_PRODUCTION` | Exceção para ambiente não produtivo. | Use conforme política interna. | Não substitui `SECURITY_MODE`. |
| `SECURITY_REQUIRE_TLS` | Exigir `TLS_MODE=provided`. | Ative quando compliance exigir certificado válido. | Em `secure`, pode bloquear. |
| `SECURITY_REQUIRE_HTTPS` | Exigir HTTPS. | Ative quando HTTP não for aceitável. | Aceita `self_signed` ou `provided`, conforme política. |
| `SECURITY_REQUIRE_SSO` | Exigir SSO. | Ative quando login externo for obrigatório. | Depende de `SECURITY_SSO_ENABLED=true`. |
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
| `PATH_GLPI_PLUGIN_DIR` | Diretório de plugins. | Padrão `/var/lib/glpi/plugins`. | Plugin SAML manual deve ser detectável aqui quando aplicável. |
| `PATH_GLPI_LOG_DIR` | Diretório de logs GLPI. | Padrão `/var/log/glpi`. | Deve ficar fora do webroot. |

## Operações

| Chave | O que colocar | Como obter ou definir | Validação comum |
|---|---|---|---|
| `OPERATIONS_TIMEZONE` | Timezone IANA. | Exemplo `America/Sao_Paulo`. | Use valor de `timedatectl list-timezones`. |
| `OPERATIONS_GLPI_CRON_SCHEDULE` | Agenda cron operacional. | Normalmente igual a `GLPI_CRON_SCHEDULE`. | Precisa estar entre aspas. |
| `OPERATIONS_REQUIRED_OPS_GROUP` | Grupo Linux dos operadores. | Padrão `glpiops`. | Operador deve pertencer ao grupo. |
| `OPERATIONS_SECURITY_MODE_DEFAULT` | `secure` ou `permissive`. | Use `secure` por padrão. | `permissive` exige justificativa. |
| `OPERATIONS_PERMISSIVE_JUSTIFICATION` | Justificativa para permissive. | Preencha só quando permissive for necessário e aprovado. | Deve explicar risco aceito. |

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
./scripts/glpictl.sh staging auth check
./scripts/glpictl.sh staging tls check
```

Se algum check falhar, corrija o valor indicado antes de executar `apply`.
