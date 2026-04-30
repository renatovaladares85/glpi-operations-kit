# GLPI Product Monitoring Blueprint

## Purpose

This blueprint defines the standard monitoring and alerting model for the reusable GLPI deployment product.

It establishes:

- default exporters
- default labels
- threshold catalog
- capacity profile mapping
- future Prometheus/Grafana/Alertmanager integration contract

## Default Exporters

- `node_exporter`
  - purpose: CPU, RAM, swap, disk, inode, load, filesystem
  - target hosts: app and db
- `mysqld_exporter`
  - purpose: MariaDB health, latency, connections, replication-ready metrics
  - target hosts: db only

## Standard Labels

Configured under `monitoring.labels`.

Required label set:

- `product`
- `service`
- `customer`
- `environment`

Recommended future labels:

- `role`
- `region`
- `owner_team`
- `criticality`

## Threshold Catalog

Configured under `monitoring.thresholds`.

Minimum thresholds:

- CPU warning: `80%`
- CPU critical: `90%`
- memory warning: `80%`
- memory critical: `90%`
- disk warning: `80%`
- disk critical: `90%`
- TLS expiry warning: `30 days`

Operational alerts:

- GLPI app unreachable
- MariaDB unreachable
- backup failed
- swap in use
- sustained IO pressure

## Scrape Profiles

Configured under `monitoring.scrape_profiles`.

Default profile:

- scrape interval: `30s`
- scrape timeout: `10s`

Recommended future profiles:

- `standard`
- `high-frequency`
- `low-overhead`

## Dashboard Profile

Configured under `monitoring.dashboard_profile`.

Recommended default:

- `glpi-standard`

Expected future dashboard groups:

- host health
- GLPI application health
- MariaDB performance
- backup status
- certificate expiry

## Alert Routing Model

Configured under `monitoring.alert_routes`.

Minimum routing metadata:

- `default_receiver`
- `escalation_policy`

Recommended future routing expansion:

- customer operations team
- infrastructure on-call
- security escalation path

## Capacity Profile Mapping

Capacity profiles are selected under `resource_profiles.active`.

Expected mapping:

- `small`
  - staging-sized environments
  - reduced PHP-FPM worker count
  - smaller MariaDB buffer pool
- `medium`
  - mid-sized environments
  - balanced worker count and DB memory
- `large`
  - production-sized environments
  - higher PHP-FPM concurrency
  - larger MariaDB memory footprint

## Prometheus Integration Contract

Future Prometheus implementation should:

- discover app and db targets from rendered product metadata
- scrape exporters according to `monitoring.scrape_profiles`
- attach labels from `monitoring.labels`
- evaluate rules derived from `monitoring.thresholds`

## Grafana Integration Contract

Future Grafana implementation should:

- choose dashboards by `monitoring.dashboard_profile`
- filter customer/environment via standard labels
- visualize host, app, db, backup, and certificate status

## Alertmanager Integration Contract

Future Alertmanager implementation should:

- map routes from `monitoring.alert_routes`
- group alerts by customer, environment, and role
- use threshold metadata from the product configuration

## Product Improvement Notes

- current repository already deploys exporters
- central Prometheus/Grafana/Alertmanager deployment is still blueprint-level
- next implementation step should convert this blueprint into reusable Ansible roles or stack deployment profiles
