# Apêndice: Modos TLS e Operações de Certificado

## 1. Modos TLS

| Modo | Permitido em staging/dev | Permitido em produção | Comportamento |
|---|---|---|---|
| `none` | Sim (quando política permitir) | Não | somente HTTP na porta 80 |
| `self_signed` | Sim | Não | HTTPS com certificado autoassinado |
| `provided` | Sim | Sim (obrigatório) | HTTPS com certificado válido fornecido |

## 2. Comandos de modo

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

## 3. Fluxo autoassinado (staging/dev)

```bash
./scripts/glpictl.sh staging tls self-signed
```

Resultado esperado:

- geração de certificado/chave no host da aplicação;
- reaplicação da role da aplicação;
- validação da configuração do Nginx.

## 4. Fluxo com certificado válido (produção obrigatório)

Antes do comando:

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

Política:

- alerta padrão com 30 dias para expiração;
- troca antes do vencimento.
