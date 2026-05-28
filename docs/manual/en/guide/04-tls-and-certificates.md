# 04 - TLS and Certificates

TLS protects credentials and operational data in transit by enabling HTTPS.

This repository supports these modes:

- `TLS_MODE=none`
- `TLS_MODE=self_signed`
- `TLS_MODE=provided`

For production, use `provided` with a valid server certificate and matching private key.

Operational commands:

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh production tls apply provided
./scripts/glpictl.sh production tls post-check
```

Validate result:

```bash
nginx -t
curl -I https://glpi.empresa.example
```

Let\'s Encrypt scope in this phase:

- there is no dedicated, versioned Let\'s Encrypt automation flow in this repository baseline;
- keep the operational baseline limited to repository-supported TLS modes.

Common error and quick action:

- error: provided certificate path invalid
- action: fix file paths in `config/<environment>.env`, run `tls check`, then re-apply

Go next:

- [TLS Modes and Certificate Operations](../appendices/tls-modes.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
