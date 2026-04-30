# Apêndice: Modos TLS e Operações de Certificado

## 1. Modos TLS

| Modo | Permitido em `secure` | Permitido em `permissive` | Comportamento |
|---|---|---|---|
| `none` | somente quando `security.require_https=false` e `security.require_tls=false` | sim (com warning/evidência se política exigir TLS/HTTPS) | HTTP na porta 80 |
| `self_signed` | permitido quando `security.require_tls=false` | sim | HTTPS com certificado autoassinado |
| `provided` | sim | sim | HTTPS com certificado fornecido pelo operador |

## 2. Comandos

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

## 3. Fluxo autoassinado

```bash
./scripts/glpictl.sh staging tls self-signed
```

Resultado esperado:

- geração de certificado/chave no host da aplicação
- reaplicação da role da aplicação
- validação de configuração do Nginx

## 4. Fluxo com certificado fornecido

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

## 5. Renovação

```bash
./scripts/glpictl.sh production ops cert check
./scripts/glpictl.sh production ops cert renew
```

Política padrão:

- alerta com 30 dias para expiração
- troca antes do vencimento
- modo `secure` pode exigir `tls.mode=provided` conforme `security.require_tls`
