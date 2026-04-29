# Appendix: TLS Modes

## Supported Modes

### `none`

- HTTP on port `80`
- no redirect to HTTPS
- no certificate required
- intended for first staging installation when no certificate is available

### `self_signed`

- HTTPS on port `443`
- redirect from `80` to `443`
- self-signed certificate generated on target host

### `provided`

- HTTPS on port `443`
- redirect from `80` to `443`
- cert/key copied from local operator-provided paths

## Switching Modes

Use `scripts/manage-tls.sh`:

```bash
./scripts/manage-tls.sh disable staging
./scripts/manage-tls.sh self-signed staging
./scripts/manage-tls.sh install-provided staging
./scripts/manage-tls.sh reload staging
```

## Validation Notes

- `provided` mode requires cert and key local files to exist
- app role validates Nginx configuration before service reload
- PHP secure cookie behavior follows effective TLS mode
