# Apêndice - Modos TLS e Operações de Certificado (PT-BR)

## Modos TLS

| Modo | Permitido em `secure` | Permitido em `permissive` | Comportamento |
|---|---|---|---|
| `none` | somente quando `SECURITY_REQUIRE_HTTPS=false` e `SECURITY_REQUIRE_TLS=false` | sim (com warning/evidência quando política exigir TLS/HTTPS) | HTTP na porta 80 |
| `self_signed` | permitido quando `SECURITY_REQUIRE_TLS=false` | sim | HTTPS com certificado autoassinado |
| `provided` | sim | sim | HTTPS com certificado fornecido pelo operador |

## Comandos

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

## Fluxo autoassinado

```bash
./scripts/glpictl.sh staging tls self-signed
```

Resultado esperado:

- gera certificado/chave no host da aplicação
- reaplica a role da aplicação
- valida a configuração do Nginx antes do reload

## Fluxo com certificado fornecido

Pré-validação local:

```bash
ls -l /path/to/fullchain.crt
ls -l /path/to/private.key
```

Aplicação:

```bash
./scripts/glpictl.sh production tls install-provided
```

Validação:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I https://GLPI_DOMAIN
```

## Renovação

```bash
./scripts/glpictl.sh production ops cert check
./scripts/glpictl.sh production ops cert renew
```

Política padrão:

- alerta com 30 dias para expiração
- troca antes do vencimento
- modo `secure` pode exigir `TLS_MODE=provided`, conforme `SECURITY_REQUIRE_TLS`
