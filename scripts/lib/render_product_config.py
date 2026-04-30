#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path

import yaml


BASE_REQUIRED_KEYS = {
    "product.name": {
        "purpose": "Defines the product display name.",
        "consumer": "documentation and runtime metadata",
    },
    "customer.display_name": {
        "purpose": "Defines the customer-facing deployment label.",
        "consumer": "documentation, runtime metadata, monitoring labels",
    },
    "environment.name": {
        "purpose": "Defines the target environment name.",
        "consumer": "runtime metadata and script validation",
    },
    "topology.app.alias": {
        "purpose": "Defines the inventory alias for the app host.",
        "consumer": "generated inventory.runtime.yml",
    },
    "topology.app.host": {
        "purpose": "Defines the real app host IP or FQDN.",
        "consumer": "generated inventory.runtime.yml",
    },
    "topology.db.alias": {
        "purpose": "Defines the inventory alias for the db host.",
        "consumer": "generated inventory.runtime.yml",
    },
    "topology.db.host": {
        "purpose": "Defines the real db host IP or FQDN.",
        "consumer": "generated inventory.runtime.yml",
    },
    "glpi.version": {
        "purpose": "Defines the GLPI release version.",
        "consumer": "application role and download URL rendering",
    },
    "glpi.domain": {
        "purpose": "Defines the public GLPI domain or hostname.",
        "consumer": "application role, TLS, smoke tests",
    },
    "database.name": {
        "purpose": "Defines the GLPI database name.",
        "consumer": "database role",
    },
    "database.user": {
        "purpose": "Defines the GLPI database username.",
        "consumer": "database and application connectivity",
    },
    "monitoring.exporters.mysqld.user": {
        "purpose": "Defines the mysqld_exporter username.",
        "consumer": "monitoring role",
    },
    "tls.mode": {
        "purpose": "Defines whether the deployment uses none, self_signed, or provided TLS.",
        "consumer": "application role and TLS workflow",
    },
    "operations.timezone": {
        "purpose": "Defines the timezone for host configuration.",
        "consumer": "base role",
    },
    "resource_profiles.active": {
        "purpose": "Selects the active tuning profile.",
        "consumer": "generated public.runtime.yml",
    },
    "security.sso_enabled": {
        "purpose": "Defines whether SSO policy is currently enabled for the environment.",
        "consumer": "production policy gate checks",
    },
}

SSH_REQUIRED_KEYS = {
    "network.ssh.user": {
        "purpose": "Defines the SSH user for Ansible access.",
        "consumer": "generated inventory.runtime.yml when execution mode is ssh",
    },
    "network.ssh.private_key_path": {
        "purpose": "Defines the SSH private key path for Ansible access.",
        "consumer": "generated inventory.runtime.yml when execution mode is ssh",
    },
}

EXECUTION_MODES = {"local", "ssh"}
HOST_ROLES = {"app", "db", "all"}


def nested_get(data, dotted):
    current = data
    for part in dotted.split("."):
        if not isinstance(current, dict) or part not in current:
            raise KeyError(dotted)
        current = current[part]
    return current


def nested_get_default(data, dotted, default=None):
    try:
        return nested_get(data, dotted)
    except KeyError:
        return default


def fail_missing(path):
    meta = BASE_REQUIRED_KEYS.get(path, SSH_REQUIRED_KEYS.get(path, {}))
    print(f"Missing required config key: {path}", file=sys.stderr)
    if meta:
        print(f"Purpose: {meta['purpose']}", file=sys.stderr)
        print(f"Used by: {meta['consumer']}", file=sys.stderr)
    sys.exit(1)


def require(data, dotted):
    try:
        return nested_get(data, dotted)
    except KeyError:
        fail_missing(dotted)


def resolve_execution_contract(config):
    mode = os.getenv("GLPI_EXECUTION_MODE", "").strip() or nested_get_default(config, "execution.mode", "local")
    role = os.getenv("GLPI_HOST_ROLE", "").strip() or nested_get_default(config, "execution.host_role_default", "all")

    if mode not in EXECUTION_MODES:
        print(f"Invalid execution mode '{mode}'. Allowed: {sorted(EXECUTION_MODES)}", file=sys.stderr)
        sys.exit(1)
    if role not in HOST_ROLES:
        print(f"Invalid host role '{role}'. Allowed: {sorted(HOST_ROLES)}", file=sys.stderr)
        sys.exit(1)
    return mode, role


def build_public_runtime(config, execution_mode, host_role):
    active_profile_name = require(config, "resource_profiles.active")
    profiles = require(config, "resource_profiles.profiles")
    if active_profile_name not in profiles:
        print(
            f"Missing resource profile '{active_profile_name}' under resource_profiles.profiles.",
            file=sys.stderr,
        )
        sys.exit(1)
    active = profiles[active_profile_name]
    php = active.get("php_fpm", {})
    mariadb = active.get("mariadb", {})
    monitoring = config.get("monitoring", {})
    alerting = config.get("alerting", {})

    glpi_version = require(config, "glpi.version")
    glpi_domain = require(config, "glpi.domain")
    tls_mode = require(config, "tls.mode")
    glpi_use_tls = tls_mode != "none"

    ssh_key_path = os.path.expanduser(nested_get_default(config, "network.ssh.private_key_path", ""))
    public_runtime = {
        "product_name": require(config, "product.name"),
        "product_slug": nested_get_default(config, "product.slug", "glpi-operations-kit"),
        "customer_display_name": require(config, "customer.display_name"),
        "customer_short_name": nested_get_default(config, "customer.short_name", "example-customer"),
        "environment_name": require(config, "environment.name"),
        "environment_stage": nested_get_default(config, "environment.stage", require(config, "environment.name")),
        "execution_mode": execution_mode,
        "execution_host_role": host_role,
        "topology_mode": nested_get_default(config, "topology.mode", "dual-server"),
        "glpi_version": glpi_version,
        "glpi_download_url": f"https://github.com/glpi-project/glpi/releases/download/{glpi_version}/glpi-{glpi_version}.tgz",
        "glpi_release_root": nested_get_default(config, "paths.glpi_release_root", "/usr/share"),
        "glpi_release_dir": f"{nested_get_default(config, 'paths.glpi_release_root', '/usr/share')}/glpi-{glpi_version}",
        "glpi_install_dir": nested_get_default(config, "paths.glpi_install_dir", "/usr/share/glpi"),
        "glpi_config_dir": nested_get_default(config, "paths.glpi_config_dir", "/etc/glpi"),
        "glpi_var_dir": nested_get_default(config, "paths.glpi_var_dir", "/var/lib/glpi/files"),
        "glpi_plugin_dir": nested_get_default(config, "paths.glpi_plugin_dir", "/var/lib/glpi/plugins"),
        "glpi_log_dir": nested_get_default(config, "paths.glpi_log_dir", "/var/log/glpi"),
        "glpi_backup_base_dir": nested_get_default(config, "backup.base_dir", "/var/backups/glpi"),
        "glpi_domain": glpi_domain,
        "glpi_use_tls": glpi_use_tls,
        "glpi_tls_mode": tls_mode,
        "glpi_tls_common_name": nested_get_default(config, "tls.common_name", glpi_domain),
        "glpi_tls_certificate_path": nested_get_default(config, "tls.certificate_path", f"/etc/ssl/certs/{require(config, 'environment.name')}.crt"),
        "glpi_tls_certificate_key_path": nested_get_default(config, "tls.private_key_path", f"/etc/ssl/private/{require(config, 'environment.name')}.key"),
        "glpi_tls_provided_local_cert_path": os.path.expanduser(nested_get_default(config, "tls.provided_local_cert_path", "")) if nested_get_default(config, "tls.provided_local_cert_path", "") else "",
        "glpi_tls_provided_local_key_path": os.path.expanduser(nested_get_default(config, "tls.provided_local_key_path", "")) if nested_get_default(config, "tls.provided_local_key_path", "") else "",
        "glpi_data_owner": nested_get_default(config, "glpi.filesystem.owner", "www-data"),
        "glpi_data_group": nested_get_default(config, "glpi.filesystem.group", "www-data"),
        "glpi_php_fpm_service": nested_get_default(config, "php_fpm.service_name", "php8.3-fpm"),
        "glpi_php_fpm_socket": nested_get_default(config, "php_fpm.socket", "/run/php/php8.3-fpm.sock"),
        "glpi_app_packages": nested_get_default(
            config,
            "glpi.app_packages",
            [
                "nginx",
                "php-fpm",
                "php-cli",
                "php-curl",
                "php-gd",
                "php-intl",
                "php-mbstring",
                "php-mysql",
                "php-xml",
                "php-zip",
                "php-bz2",
                "php-apcu",
                "php-ldap",
                "php-imap",
                "php-opcache",
                "php-redis",
                "tar",
                "xz-utils",
                "curl",
                "openssl",
            ],
        ),
        "glpi_upload_max_filesize": nested_get_default(config, "glpi.upload_max_filesize", "32M"),
        "glpi_post_max_size": nested_get_default(config, "glpi.post_max_size", "32M"),
        "glpi_memory_limit": nested_get_default(config, "glpi.memory_limit", "512M"),
        "glpi_max_execution_time": nested_get_default(config, "glpi.max_execution_time", 120),
        "glpi_opcache_memory_consumption": nested_get_default(config, "glpi.opcache_memory_consumption", 192),
        "glpi_pm": nested_get_default(config, "php_fpm.pm", "dynamic"),
        "glpi_pm_max_children": nested_get_default(php, "max_children", 20),
        "glpi_pm_start_servers": nested_get_default(php, "start_servers", 4),
        "glpi_pm_min_spare_servers": nested_get_default(php, "min_spare_servers", 2),
        "glpi_pm_max_spare_servers": nested_get_default(php, "max_spare_servers", 6),
        "glpi_pm_max_requests": nested_get_default(php, "max_requests", 500),
        "glpi_cron_schedule": nested_get_default(config, "operations.glpi_cron_schedule", "*/5 * * * *"),
        "glpi_backup_retention_days": nested_get_default(config, "backup.retention_days", 14),
        "node_exporter_enabled": nested_get_default(monitoring, "exporters.node.enabled", True),
        "mysqld_exporter_enabled": nested_get_default(monitoring, "exporters.mysqld.enabled", True),
        "mysqld_exporter_user": require(config, "monitoring.exporters.mysqld.user"),
        "monitoring_labels": nested_get_default(monitoring, "labels", {}),
        "monitoring_thresholds": nested_get_default(monitoring, "thresholds", {}),
        "monitoring_scrape_profiles": nested_get_default(monitoring, "scrape_profiles", {}),
        "monitoring_dashboard_profile": nested_get_default(monitoring, "dashboard_profile", "glpi-standard"),
        "monitoring_alert_routes": nested_get_default(monitoring, "alert_routes", {}),
        "alert_tls_expiry_warning_days": nested_get_default(alerting, "tls_expiry_warning_days", 30),
        "security_sso_enabled": require(config, "security.sso_enabled"),
        "security_allow_insecure_non_production": nested_get_default(config, "security.allow_insecure_non_production", True),
        "security_require_tls": nested_get_default(
            config,
            "security.require_tls",
            nested_get_default(config, "security.require_tls_in_production", False),
        ),
        "security_require_https": nested_get_default(
            config,
            "security.require_https",
            nested_get_default(config, "security.require_https_in_production", False),
        ),
        "security_require_sso": nested_get_default(
            config,
            "security.require_sso",
            nested_get_default(config, "security.require_sso_in_production", False),
        ),
        "security_require_promotion_gate": nested_get_default(config, "security.require_promotion_gate", False),
        "security_require_ordered_execution": nested_get_default(config, "security.require_ordered_execution", True),
        "operations_security_mode_default": nested_get_default(config, "operations.security_mode_default", "secure"),
        "mariadb_bind_address": nested_get_default(config, "database.bind_address", "0.0.0.0"),
        "mariadb_port": nested_get_default(config, "database.port", 3306),
        "mariadb_version_packages": nested_get_default(
            config,
            "database.packages",
            ["mariadb-server", "mariadb-client", "python3-pymysql"],
        ),
        "mariadb_innodb_buffer_pool_size": nested_get_default(mariadb, "innodb_buffer_pool_size", "2G"),
        "mariadb_max_connections": nested_get_default(mariadb, "max_connections", 80),
        "mariadb_tmp_table_size": nested_get_default(mariadb, "tmp_table_size", "128M"),
        "mariadb_max_heap_table_size": nested_get_default(mariadb, "max_heap_table_size", "128M"),
        "mariadb_slow_query_log": nested_get_default(mariadb, "slow_query_log", 1),
        "mariadb_long_query_time": nested_get_default(mariadb, "long_query_time", 2),
        "timezone_name": require(config, "operations.timezone"),
        "db_allowed_source_hosts": nested_get_default(config, "network.database.allowed_source_hosts", [require(config, "topology.app.host")]),
        "glpi_db_app_access_host": nested_get_default(config, "network.database.app_access_host", require(config, "topology.app.host")),
        "glpi_db_name": require(config, "database.name"),
        "glpi_db_user": require(config, "database.user"),
        "resource_profile_name": active_profile_name,
        "ssh_key_path_resolved": ssh_key_path,
    }
    return public_runtime


def build_inventory(config, execution_mode, host_role):
    environment_name = require(config, "environment.name")
    app_alias = require(config, "topology.app.alias")
    app_host = require(config, "topology.app.host")
    db_alias = require(config, "topology.db.alias")
    db_host = require(config, "topology.db.host")
    topology_mode = nested_get_default(config, "topology.mode", "dual-server")

    if execution_mode == "local":
        children = {}
        include_app = topology_mode == "single-server" or host_role in {"app", "all"}
        include_db = topology_mode == "single-server" or host_role in {"db", "all"}

        if include_app:
            children["glpi_app"] = {
                "hosts": {
                    app_alias: {
                        "ansible_connection": "local",
                        "ansible_host": "127.0.0.1",
                    }
                }
            }
        if include_db:
            children["glpi_db"] = {
                "hosts": {
                    db_alias: {
                        "ansible_connection": "local",
                        "ansible_host": "127.0.0.1",
                    }
                }
            }
        return {
            "all": {
                "vars": {
                    "environment_name": environment_name,
                },
                "children": children,
            }
        }

    return {
        "all": {
            "vars": {
                "ansible_user": require(config, "network.ssh.user"),
                "ansible_ssh_private_key_file": os.path.expanduser(require(config, "network.ssh.private_key_path")),
                "environment_name": environment_name,
            },
            "children": {
                "glpi_app": {
                    "hosts": {
                        app_alias: {
                            "ansible_host": app_host,
                        }
                    }
                },
                "glpi_db": {
                    "hosts": {
                        db_alias: {
                            "ansible_host": db_host,
                        }
                    }
                },
            },
        }
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--mode", choices=["public-runtime", "inventory"], required=True)
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.is_file():
        print(f"Missing configuration file: {config_path}", file=sys.stderr)
        sys.exit(1)

    with config_path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}

    execution_mode, host_role = resolve_execution_contract(data)

    for key in BASE_REQUIRED_KEYS:
        require(data, key)
    if execution_mode == "ssh":
        for key in SSH_REQUIRED_KEYS:
            require(data, key)

    result = (
        build_public_runtime(data, execution_mode, host_role)
        if args.mode == "public-runtime"
        else build_inventory(data, execution_mode, host_role)
    )
    yaml.safe_dump(result, sys.stdout, sort_keys=False, default_flow_style=False)


if __name__ == "__main__":
    main()
