# Appendix: TLS Modes and Certificate Operations

## 1. TLS modes

| Mode | Allowed in secure mode | Allowed in permissive mode | Behavior |
|---|---|---|---|
| `none` | Only when `SECURITY_REQUIRE_HTTPS=false` and `SECURITY_REQUIRE_TLS=false` | Yes (with warning/evidence if policy requires TLS/HTTPS) | HTTP only on port 80 |
| `self_signed` | Allowed when `SECURITY_REQUIRE_TLS=false` | Yes | HTTPS with self-signed certificate |
| `provided` | Yes | Yes | HTTPS with operator-provided valid certificate |

## 2. Mode commands

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

## 3. Self-signed flow (staging/dev)

Use:

```bash
./scripts/glpictl.sh staging tls self-signed
```

Expected behavior:

- self-signed key/cert are generated in target paths
- app role is re-applied
- Nginx config is validated

## 4. Provided certificate flow

Before command, ensure local files exist:

```bash
ls -l /path/to/fullchain.crt
ls -l /path/to/private.key
```

Then:

```bash
./scripts/glpictl.sh production tls install-provided
```

Validation:

```bash
sudo nginx -t
sudo systemctl reload nginx
curl -I https://GLPI_DOMAIN
```

## 5. Renewal checks

```bash
./scripts/glpictl.sh production ops cert check
./scripts/glpictl.sh production ops cert renew
```

Policy:

- warning threshold defaults to 30 days
- replace cert before expiration
- secure mode may require provided certificates based on `SECURITY_REQUIRE_TLS`.
