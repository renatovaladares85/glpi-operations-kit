# Monitoring Standard

## Base stack

- `Prometheus`
- `Grafana`
- `Alertmanager`
- `node_exporter`
- `mysqld_exporter`

## Minimum monitoring scope

- CPU
- RAM
- swap
- disk
- inode
- IO wait
- Nginx availability
- PHP-FPM availability
- MariaDB latency and connections

## Minimum alerts

- disk above 80%
- disk above 90%
- sustained high RAM
- swap in use
- service stopped
- backup failure
