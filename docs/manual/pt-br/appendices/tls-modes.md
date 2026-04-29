# Apêndice: Modos TLS

Modos suportados:

- `none`: HTTP porta `80`, sem redirect para HTTPS.
- `self_signed`: HTTPS porta `443`, redirect `80 -> 443`, certificado autoassinado.
- `provided`: HTTPS porta `443`, redirect `80 -> 443`, certificado/chave fornecidos.

Troca de modo:

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```

Validação:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I http://APP_HOST_OR_IP
curl -kI https://APP_HOST_OR_IP
```
