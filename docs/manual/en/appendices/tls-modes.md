# Appendix - TLS Modes and Certificate Operations (EN)

This appendix explains which TLS mode to choose, what certificate type to request, which files to prepare, and how to validate the flow.

## TLS modes

| Mode | Allowed in `secure` | Allowed in `permissive` | Behavior |
|---|---|---|---|
| `none` | only when `SECURITY_REQUIRE_HTTPS=false` and `SECURITY_REQUIRE_TLS=false` | yes, with warning/evidence if policy requires TLS/HTTPS | HTTP on `WEB_HTTP_PORT`. |
| `self_signed` | allowed when `SECURITY_REQUIRE_TLS=false` | yes | HTTPS with locally generated self-signed certificate. |
| `provided` | yes | yes | HTTPS with operator/CA-provided server certificate. |

## Which certificate to request

For GLPI web, request an HTTPS server certificate. Do not request a client certificate for this flow.

Recommended requirements:

| Item | Expected value |
|---|---|
| Type | TLS server certificate for HTTPS. |
| Extended usage | `serverAuth`. |
| CN | Main FQDN, e.g. `glpi.company.com`. |
| SAN | Must include the FQDN used by `GLPI_DOMAIN`. May include aliases defined by local policy. |
| Certificate format | PEM, usually `.crt` or `.pem`. |
| Chain | Prefer fullchain PEM with server certificate + intermediates. |
| Private key | Matching PEM private key, protected, never versioned. |
| Client key/mTLS | Out of current scope; the kit does not automate mTLS. |

If the CA asks for CSR data, provide:

| Field | What to provide |
|---|---|
| Common Name | Main GLPI FQDN. |
| Subject Alternative Name | `DNS:glpi.company.com` and aliases defined by local policy. |
| Organization/Locality/Country | Corporate values if required by CA. |
| Key usage | Digital Signature and Key Encipherment, according to CA profile. |
| Extended key usage | Server Authentication. |
| Algorithm | RSA 2048/3072 or ECDSA P-256, according to corporate policy. |

## Local source versus server destination

| Key | Meaning |
|---|---|
| `TLS_PROVIDED_LOCAL_CERT_PATH` | Certificate/fullchain file that exists on the execution host before installation. |
| `TLS_PROVIDED_LOCAL_KEY_PATH` | Private key file that exists on the execution host before installation. |
| `TLS_CERTIFICATE_PATH` | Final certificate path on APP host, usually under `/etc/ssl/certs/`. |
| `TLS_PRIVATE_KEY_PATH` | Final private key path on APP host, usually under `/etc/ssl/private/`. |

Local files are sources. `TLS_CERTIFICATE_PATH` and `TLS_PRIVATE_KEY_PATH` are server destinations.

## Standardized commands

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging tls prepare self-signed
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh staging tls prepare provided
./scripts/glpictl.sh staging tls apply provided
./scripts/glpictl.sh staging tls post-check
./scripts/glpictl.sh staging tls rollback
```

## Compatible legacy commands

```bash
./scripts/glpictl.sh staging tls disable
./scripts/glpictl.sh staging tls self-signed
./scripts/glpictl.sh staging tls install-provided
./scripts/glpictl.sh staging tls reload
```

## `none` flow

Use only in development, lab, or an environment where policy allows HTTP.

```env
TLS_MODE=none
SECURITY_REQUIRE_TLS=false
SECURITY_REQUIRE_HTTPS=false
```

Validation:

```bash
./scripts/glpictl.sh staging tls check
./scripts/glpictl.sh staging deploy post-check all
```

## Self-signed flow

Use for controlled testing when no corporate certificate exists yet.

```env
TLS_MODE=self_signed
TLS_COMMON_NAME=glpi-staging.example.internal
```

Apply:

```bash
./scripts/glpictl.sh staging tls apply self-signed
./scripts/glpictl.sh staging tls post-check
```

Expected result:

- certificate/key generated on APP host with `serverAuth` and DNS SANs derived
  from `TLS_COMMON_NAME` and `GLPI_DOMAIN`, without duplicates;
- repeated runs preserve a valid certificate; identity changes, key mismatch, or
  expiration create backups and renew it;
- application reconfigured for HTTPS;
- web server configuration validated before reload;
- evidence under `.runtime/<environment>/evidence/tls/` when available.

## Provided certificate flow

Prepare files on the execution host:

```bash
ls -l /secure-transfer/glpi-company-fullchain.pem
ls -l /secure-transfer/glpi-company.key
```

Fill:

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

Apply:

```bash
./scripts/glpictl.sh production tls check
./scripts/glpictl.sh production tls prepare provided
./scripts/glpictl.sh production tls apply provided
./scripts/glpictl.sh production tls post-check
```

## Operational validation

Use kit checks first:

```bash
./scripts/glpictl.sh production tls post-check
./scripts/glpictl.sh production ops cert check
```

On the APP host, validate the selected engine. Apache examples with fictional values:

```bash
# Debian/Ubuntu
sudo apachectl configtest
sudo apachectl -M | grep ssl

# Rocky/RHEL-like
sudo apachectl configtest
sudo httpd -M | grep ssl
sudo httpd -S

sudo ss -lntp | grep ':443'
curl -vk --resolve glpi.example.internal:443:127.0.0.1 https://glpi.example.internal/
openssl s_client -connect 127.0.0.1:443 -servername glpi.example.internal </dev/null 2>/dev/null |
  openssl x509 -noout -subject -issuer -dates -ext subjectAltName
```

For Nginx or Lighttpd, use the equivalent configtest for the selected engine.

## Reverse proxy with an HTTPS backend

The kit does not configure the external proxy. It must preserve `Host`, use the
same FQDN for SNI, forward `X-Forwarded-Proto`, `X-Forwarded-Host`,
`X-Forwarded-Port`, and the `X-Forwarded-For` chain, and trust the backend
certificate/CA specifically. Do not disable TLS validation globally.

Because proxy-to-Apache traffic also uses HTTPS, GLPI receives a real TLS
connection. No documented GLPI 11.0.8 setting was found that justifies automating
a trusted-proxy list in this project.

## Renewal

```bash
./scripts/glpictl.sh production ops cert check
./scripts/glpictl.sh production tls apply provided
./scripts/glpictl.sh production tls post-check
```

Renew before the warning threshold configured by `ALERTING_TLS_EXPIRY_WARNING_DAYS`.

## Rollback

```bash
./scripts/glpictl.sh production tls rollback
```

Rollback restores local TLS domain metadata/runtime/evidence according to the local snapshot. If the certificate was issued, revoked, or replaced by an external PKI team, that reversal must follow the PKI team's own procedure.
