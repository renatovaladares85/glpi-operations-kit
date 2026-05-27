# Apêndice - Modos TLS e Operações de Certificado (PT-BR)

Este apêndice explica qual modo TLS escolher, que tipo de certificado solicitar, quais arquivos preparar e como validar o fluxo.

## Modos TLS

| Modo | Permitido em `secure` | Permitido em `permissive` | Comportamento |
|---|---|---|---|
| `none` | somente quando `SECURITY_REQUIRE_HTTPS=false` e `SECURITY_REQUIRE_TLS=false` | sim, com warning/evidência quando política exigir TLS/HTTPS | HTTP na porta `WEB_HTTP_PORT`. |
| `self_signed` | permitido quando `SECURITY_REQUIRE_TLS=false` | sim | HTTPS com certificado autoassinado gerado localmente. |
| `provided` | sim | sim | HTTPS com certificado de servidor fornecido pelo operador/CA. |

## Qual certificado solicitar

Para GLPI web, solicite certificado de servidor HTTPS. Não solicite certificado de cliente para este fluxo.

Requisitos recomendados:

| Item | Valor esperado |
|---|---|
| Tipo | Certificado TLS de servidor para HTTPS. |
| Uso estendido | `serverAuth`. |
| CN | FQDN principal, por exemplo `glpi.company.com`. |
| SAN | Deve conter o FQDN usado por `GLPI_DOMAIN` e `SSO_PUBLIC_URL`. Pode conter aliases aprovados. |
| Formato do certificado | PEM, normalmente `.crt` ou `.pem`. |
| Cadeia | Preferir fullchain PEM com certificado do servidor + intermediárias. |
| Chave privada | PEM correspondente ao certificado, protegida, não versionada. |
| Chave de cliente/mTLS | Fora do escopo atual; o kit não automatiza mTLS. |

Se a CA pedir dados para CSR, forneça:

| Campo | O que informar |
|---|---|
| Common Name | FQDN principal do GLPI. |
| Subject Alternative Name | `DNS:glpi.company.com` e aliases aprovados. |
| Organization/Locality/Country | Valores corporativos se a CA exigir. |
| Key usage | Digital Signature e Key Encipherment, conforme perfil da CA. |
| Extended key usage | Server Authentication. |
| Algoritmo | RSA 2048/3072 ou ECDSA P-256, conforme política corporativa. |

## Diferença entre origem local e destino no servidor

| Chave | Significado |
|---|---|
| `TLS_PROVIDED_LOCAL_CERT_PATH` | Arquivo de certificado/fullchain existente no host executor antes da instalação. |
| `TLS_PROVIDED_LOCAL_KEY_PATH` | Arquivo de chave privada existente no host executor antes da instalação. |
| `TLS_CERTIFICATE_PATH` | Caminho final do certificado no host APP, normalmente em `/etc/ssl/certs/`. |
| `TLS_PRIVATE_KEY_PATH` | Caminho final da chave privada no host APP, normalmente em `/etc/ssl/private/`. |

Os arquivos locais são fonte. Os caminhos `TLS_CERTIFICATE_PATH` e `TLS_PRIVATE_KEY_PATH` são destino no servidor.

## Comandos padronizados

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging tls prepare self-signed
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh staging tls prepare provided
./scripts/glpictl.sh staging tls apply provided
./scripts/glpictl.sh staging tls post-check
./scripts/glpictl.sh staging tls rollback
```

## Comandos legados compatíveis

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

## Fluxo `none`

Use apenas em desenvolvimento, laboratório ou ambiente onde a política permite HTTP.

```env
TLS_MODE=none
SECURITY_REQUIRE_TLS=false
SECURITY_REQUIRE_HTTPS=false
```

Validação:

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging deploy post-check all
```

## Fluxo autoassinado

Use para teste controlado quando ainda não existe certificado corporativo.

```env
TLS_MODE=self_signed
TLS_COMMON_NAME=glpi-staging.example.internal
```

Aplicação:

```bash
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh staging tls post-check
```

Resultado esperado:

- certificado/chave gerados no host APP;
- aplicação reconfigurada para HTTPS;
- validação do web server antes de reload;
- evidência em `.runtime/<environment>/evidence/tls/` quando disponível.

## Fluxo com certificado fornecido

Prepare os arquivos no host executor:

```bash
ls -l /secure-transfer/glpi-company-fullchain.pem
ls -l /secure-transfer/glpi-company.key
```

Preencha:

```env
TLS_MODE=provided
TLS_COMMON_NAME=glpi.company.com
TLS_CERTIFICATE_PATH=/etc/ssl/certs/glpi-company-fullchain.pem
TLS_PRIVATE_KEY_PATH=/etc/ssl/private/glpi-company.key
TLS_PROVIDED_LOCAL_CERT_PATH=/secure-transfer/glpi-company-fullchain.pem
TLS_PROVIDED_LOCAL_KEY_PATH=/secure-transfer/glpi-company.key
SECURITY_REQUIRE_TLS=true
SECURITY_REQUIRE_HTTPS=true
```

Aplique:

```bash
./scripts/glpictl.sh production tls check
./scripts/glpictl.sh production tls prepare provided
./scripts/glpictl.sh production tls apply provided
./scripts/glpictl.sh production tls post-check
```

## Validação operacional

Use os checks do kit primeiro:

```bash
./scripts/glpictl.sh production tls post-check
./scripts/glpictl.sh production ops cert check
```

Quando estiver no host APP e o engine for Nginx, também é útil validar manualmente:

```bash
sudo nginx -t
curl -I https://glpi.company.com
```

Para Apache ou lighttpd, use o teste equivalente do serviço selecionado pela empresa.

## Renovação

```bash
./scripts/glpictl.sh production ops cert check
./scripts/glpictl.sh production tls apply provided
./scripts/glpictl.sh production tls post-check
```

Renove antes do alerta configurado em `ALERTING_TLS_EXPIRY_WARNING_DAYS`.

## Rollback

```bash
./scripts/glpictl.sh production tls rollback
```

Rollback restaura metadados/runtime/evidências do domínio TLS conforme snapshot local. Se o certificado foi emitido, revogado ou substituído por equipe externa de PKI, a reversão desse processo deve seguir o procedimento da própria PKI.
