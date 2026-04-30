# Apendice: Configuracao do Produto e Segredos Runtime

## Visao geral

O produto agora usa:

- configuracao publica em `config/<environment>.yml`
- segredos runtime em `.runtime/<environment>/secrets.yml`

Arquivos runtime gerados:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/overrides.runtime.yml`

Precedencia de merge:

- `public.runtime.yml -> overrides.runtime.yml -> secrets.yml`

## O que fica no config publico

Exemplos:

- nome do cliente
- hosts ou IPs de app/db
- usuario SSH e caminho da chave
- versao do GLPI
- dominio
- modo TLS
- nome do banco e usuario do banco
- usuario do exporter de monitoracao
- defaults de backup e monitoracao
- perfil de tuning

## O que fica nos segredos runtime

- `glpi_db_password`
- `glpi_db_root_password`
- `mysqld_exporter_password`

## Caminho manual sem script

Se os scripts nao puderem ser usados, crie:

- `.runtime/<environment>/inventory.runtime.yml`
- `.runtime/<environment>/public.runtime.yml`
- `.runtime/<environment>/overrides.runtime.yml`
- `.runtime/<environment>/secrets.yml`

A fonte recomendada para os valores publicos continua sendo `config/<environment>.yml`.
