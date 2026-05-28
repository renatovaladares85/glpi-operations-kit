# 04 - TLS e Certificados

TLS protege credenciais e dados operacionais durante o tráfego, habilitando HTTPS.

Este repositório suporta:

- `TLS_MODE=none`
- `TLS_MODE=self_signed`
- `TLS_MODE=provided`

Para produção, use `provided` com certificado de servidor válido e chave privada correspondente.

Comandos operacionais:

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh production tls apply provided
./scripts/glpictl.sh production tls post-check
```

Validação:

```bash
nginx -t
curl -I https://glpi.empresa.example
```

Escopo Let\'s Encrypt nesta fase:

- não existe fluxo dedicado, versionado e automatizado de Let\'s Encrypt no baseline atual deste repositório;
- mantenha o baseline operacional apenas nos modos TLS suportados pelo projeto.

Erro comum e ação rápida:

- erro: caminho inválido de certificado fornecido
- ação: corrigir caminhos em `config/<environment>.env`, executar `tls check` e aplicar novamente

Próximo passo:

- [Modos TLS e Operações de Certificado](../appendices/tls-modes.md)
- [Matriz de Troubleshooting](../appendices/troubleshooting-matrix.md)
