# 03 - Deploy on Linux (Traditional Stack)

This is the primary path in this repository for GLPI 11.x on Ubuntu with Nginx, PHP-FPM, and MariaDB/MySQL.

Run the sequence in order:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

If your topology is dual-server and execution is local, split the flow.

DB host:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply db
```

APP host:

```bash
./scripts/glpictl.sh staging deploy check all
./scripts/glpictl.sh staging deploy apply app
./scripts/glpictl.sh staging deploy apply monitoring
./scripts/glpictl.sh staging deploy apply backup
./scripts/glpictl.sh staging deploy post-check all
```

Validate service configuration:

```bash
nginx -t
php-fpm8.3 -t
```

What to verify after deployment:

- web service is up;
- PHP-FPM is up;
- application endpoint responds.

Common error and quick action:

- error: ordered execution block
- action: run missing prior step, then retry current step

Go next:

- [04 - TLS and Certificates](04-tls-and-certificates.md)
- [Command Reference](../appendices/command-reference.md)
- [Troubleshooting Matrix](../appendices/troubleshooting-matrix.md)
