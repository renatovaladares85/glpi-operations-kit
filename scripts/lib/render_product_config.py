#!/usr/bin/env python3
import argparse
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

EXECUTION_MODES = {"local", "ssh"}
HOST_ROLES = {"app", "db", "all"}
TLS_MODES = {"none", "self_signed", "provided"}
WEB_SERVER_TYPES = {"nginx", "apache", "lighttpd"}
GLPI_INSTALLATION_MODES = {"cli", "wizard", "defer"}
TOPOLOGY_MODES = {"single-server", "dual-server"}
DB_ACCESS_MODES = {"restricted", "open"}
DB_DEPLOYMENT_MODES = {"self_hosted", "managed"}
GLPI_TIMEZONE_DB_MODES = {"disabled", "validate", "apply"}
MONITORING_PROFILES = {"minimal", "standard", "full", "external_prometheus", "external_grafana"}
MONITORING_GRAFANA_PUBLIC_MODES = {"disabled", "path", "subdomain"}
DEFAULT_MAILPIT_IMAGE = "axllent/mailpit:v1.30.1"

DEFAULT_GLPI_APP_PACKAGES_DEBIAN = [
    "php-fpm",
    "php-cli",
    "php-curl",
    "php-gd",
    "php-intl",
    "php-mbstring",
    "php-bcmath",
    "php-mysql",
    "php-xml",
    "php-zip",
    "php-bz2",
    "php-apcu",
    "php-ldap",
    "php-imap",
    "php-opcache",
    "php-redis",
    "redis-server",
    "tar",
    "xz-utils",
    "curl",
    "openssl",
    "mariadb-client",
]

DEFAULT_GLPI_APP_PACKAGES_RHEL = [
    "php-fpm",
    "php-cli",
    "php-curl",
    "php-gd",
    "php-intl",
    "php-mbstring",
    "php-bcmath",
    "php-mysqlnd",
    "php-xml",
    "php-zip",
    "php-bz2",
    "php-pecl-apcu",
    "php-ldap",
    "php-imap",
    "php-opcache",
    "php-pecl-redis",
    "redis",
    "tar",
    "xz",
    "curl",
    "openssl",
    "mysql",
]

DEFAULT_GLPI_APP_PACKAGES_BY_FAMILY = {
    "debian": DEFAULT_GLPI_APP_PACKAGES_DEBIAN,
    "rhel": DEFAULT_GLPI_APP_PACKAGES_RHEL,
}

WEB_SERVER_PACKAGES_BY_FAMILY = {
    "debian": {
        "nginx": ["nginx"],
        "apache": ["apache2", "libapache2-mod-fcgid"],
        "lighttpd": ["lighttpd"],
    },
    "rhel": {
        "nginx": ["nginx"],
        "apache": ["httpd"],
        "lighttpd": ["lighttpd"],
    },
}

WEB_SERVER_PACKAGES = WEB_SERVER_PACKAGES_BY_FAMILY["debian"]

PLATFORM_DEFAULTS = {
    "debian": {
        "glpi_data_owner": "www-data",
        "glpi_data_group": "www-data",
        "php_fpm_service": "php8.3-fpm",
        "php_fpm_socket": "/run/php/php8.3-fpm.sock",
        "php_fpm_test_command": "php-fpm8.3 -t",
        "php_ini_fpm_path": "/etc/php/8.3/fpm/conf.d/99-glpi.ini",
        "php_ini_cli_path": "/etc/php/8.3/cli/conf.d/99-glpi.ini",
        "php_fpm_pool_path": "/etc/php/8.3/fpm/pool.d/glpi.conf",
        "php_fpm_default_pool_path": "/etc/php/8.3/fpm/pool.d/www.conf",
        "nginx_conf_available_path": "/etc/nginx/sites-available/glpi.conf",
        "nginx_conf_enabled_path": "/etc/nginx/sites-enabled/glpi.conf",
        "nginx_default_available_path": "/etc/nginx/sites-available/default",
        "nginx_default_enabled_path": "/etc/nginx/sites-enabled/default",
        "nginx_fastcgi_params": "snippets/fastcgi-php.conf",
        "apache_service": "apache2",
        "apache_conf_path": "/etc/apache2/sites-available/glpi.conf",
        "apache_default_conf_path": "/etc/apache2/sites-enabled/000-default.conf",
    },
    "rhel": {
        "glpi_data_owner": "apache",
        "glpi_data_group": "apache",
        "php_fpm_service": "php-fpm",
        "php_fpm_socket": "/run/php-fpm/glpi.sock",
        "php_fpm_test_command": "php-fpm -t",
        "php_ini_fpm_path": "/etc/php.d/99-glpi.ini",
        "php_ini_cli_path": "/etc/php.d/99-glpi.ini",
        "php_fpm_pool_path": "/etc/php-fpm.d/glpi.conf",
        "php_fpm_default_pool_path": "/etc/php-fpm.d/www.conf",
        "nginx_conf_available_path": "/etc/nginx/conf.d/glpi.conf",
        "nginx_conf_enabled_path": "/etc/nginx/conf.d/glpi.conf",
        "nginx_default_available_path": "",
        "nginx_default_enabled_path": "",
        "nginx_fastcgi_params": "fastcgi_params",
        "apache_service": "httpd",
        "apache_conf_path": "/etc/httpd/conf.d/glpi.conf",
        "apache_default_conf_path": "/etc/httpd/conf.d/welcome.conf",
    },
}

WEB_SERVER_SERVICES = {
    "debian": {
        "nginx": "nginx",
        "apache": "apache2",
        "lighttpd": "lighttpd",
    },
    "rhel": {
        "nginx": "nginx",
        "apache": "httpd",
        "lighttpd": "lighttpd",
    },
}

DEFAULT_GLPI_APP_PACKAGES = DEFAULT_GLPI_APP_PACKAGES_DEBIAN

DEFAULT_DATABASE_PACKAGES_BY_FAMILY = {
    "debian": ["mariadb-server", "mariadb-client", "python3-pymysql"],
    "rhel": ["mariadb-server", "mariadb", "python3-PyMySQL"],
}

DEFAULT_DATABASE_PACKAGES = DEFAULT_DATABASE_PACKAGES_BY_FAMILY["debian"]

REQUIRED_PUBLIC_KEYS = {
    "PRODUCT_NAME": {
        "purpose": "Defines the product display name.",
        "consumer": "documentation and runtime metadata",
    },
    "CUSTOMER_DISPLAY_NAME": {
        "purpose": "Defines the customer-facing deployment label.",
        "consumer": "documentation, runtime metadata, monitoring labels",
    },
    "ENVIRONMENT_NAME": {
        "purpose": "Defines the target environment name.",
        "consumer": "runtime metadata and script validation",
    },
    "TOPOLOGY_APP_ALIAS": {
        "purpose": "Defines the inventory alias for the app host.",
        "consumer": "generated inventory.runtime.yml",
    },
    "TOPOLOGY_APP_HOST": {
        "purpose": "Defines the real app host IP or FQDN.",
        "consumer": "generated inventory.runtime.yml",
    },
    "TOPOLOGY_DB_ALIAS": {
        "purpose": "Defines the inventory alias for the db host.",
        "consumer": "generated inventory.runtime.yml",
    },
    "TOPOLOGY_DB_HOST": {
        "purpose": "Defines the real db host IP or FQDN.",
        "consumer": "generated inventory.runtime.yml",
    },
    "GLPI_VERSION": {
        "purpose": "Defines the GLPI release version.",
        "consumer": "application role and download URL rendering",
    },
    "GLPI_DOMAIN": {
        "purpose": "Defines the public GLPI domain or hostname.",
        "consumer": "application role, TLS, smoke tests",
    },
    "WEB_SERVER_TYPE": {
        "purpose": "Defines which GLPI-compatible web server should be configured.",
        "consumer": "application role web server provisioning and templates",
    },
    "WEB_HTTP_PORT": {
        "purpose": "Defines the HTTP listen port for the selected web server.",
        "consumer": "application role web routing checks and templates",
    },
    "WEB_HTTPS_PORT": {
        "purpose": "Defines the HTTPS listen port for the selected web server.",
        "consumer": "application role TLS checks and templates",
    },
    "DATABASE_NAME": {
        "purpose": "Defines the GLPI database name.",
        "consumer": "database role",
    },
    "DATABASE_USER": {
        "purpose": "Defines the GLPI database username.",
        "consumer": "database and application connectivity",
    },
    "DATABASE_PASSWORD": {
        "purpose": "Defines the GLPI database password.",
        "consumer": "runtime secrets materialization and database/application connectivity",
    },
    "DATABASE_ROOT_PASSWORD": {
        "purpose": "Defines the MariaDB root password for provisioning.",
        "consumer": "runtime secrets materialization and database provisioning",
    },
    "MONITORING_MYSQLD_EXPORTER_USER": {
        "purpose": "Defines the mysqld_exporter username.",
        "consumer": "monitoring role",
    },
    "TLS_MODE": {
        "purpose": "Defines whether the deployment uses none, self_signed, or provided TLS.",
        "consumer": "application role and TLS workflow",
    },
    "OPERATIONS_TIMEZONE": {
        "purpose": "Defines the timezone for host configuration.",
        "consumer": "base role",
    },
    "RESOURCE_PROFILE_ACTIVE": {
        "purpose": "Selects the active tuning profile.",
        "consumer": "generated public.runtime.yml",
    },
}

SSH_REQUIRED_KEYS = {
    "NETWORK_SSH_USER": {
        "purpose": "Defines the SSH user for Ansible access.",
        "consumer": "generated inventory.runtime.yml when execution mode is ssh",
    },
    "NETWORK_SSH_PRIVATE_KEY_PATH": {
        "purpose": "Defines the SSH private key path for Ansible access.",
        "consumer": "generated inventory.runtime.yml when execution mode is ssh",
    },
}

DOTTED_KEY_MAP = {
    "product.name": "PRODUCT_NAME",
    "product.slug": "PRODUCT_SLUG",
    "product.deployment_label": "PRODUCT_DEPLOYMENT_LABEL",
    "customer.display_name": "CUSTOMER_DISPLAY_NAME",
    "customer.short_name": "CUSTOMER_SHORT_NAME",
    "environment.name": "ENVIRONMENT_NAME",
    "environment.stage": "ENVIRONMENT_STAGE",
    "execution.mode": "EXECUTION_MODE",
    "execution.host_role_default": "EXECUTION_HOST_ROLE_DEFAULT",
    "topology.mode": "TOPOLOGY_MODE",
    "topology.app.alias": "TOPOLOGY_APP_ALIAS",
    "topology.app.host": "TOPOLOGY_APP_HOST",
    "topology.db.alias": "TOPOLOGY_DB_ALIAS",
    "topology.db.host": "TOPOLOGY_DB_HOST",
    "network.ssh.user": "NETWORK_SSH_USER",
    "network.ssh.private_key_path": "NETWORK_SSH_PRIVATE_KEY_PATH",
    "network.database.app_access_host": "NETWORK_DATABASE_APP_ACCESS_HOST",
    "network.database.access_mode": "NETWORK_DATABASE_ACCESS_MODE",
    "network.database.allowed_source_hosts": "NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS",
    "glpi.version": "GLPI_VERSION",
    "glpi.domain": "GLPI_DOMAIN",
    "glpi.installation_mode": "GLPI_INSTALLATION_MODE",
    "glpi.wizard_reset_config_db": "GLPI_WIZARD_RESET_CONFIG_DB",
    "web.server_type": "WEB_SERVER_TYPE",
    "glpi.upload_max_filesize": "GLPI_UPLOAD_MAX_FILESIZE",
    "glpi.post_max_size": "GLPI_POST_MAX_SIZE",
    "glpi.memory_limit": "GLPI_MEMORY_LIMIT",
    "glpi.max_execution_time": "GLPI_MAX_EXECUTION_TIME",
    "glpi.opcache_memory_consumption": "GLPI_OPCACHE_MEMORY_CONSUMPTION",
    "glpi.cron_schedule": "GLPI_CRON_SCHEDULE",
    "glpi.filesystem.owner": "GLPI_FILESYSTEM_OWNER",
    "glpi.filesystem.group": "GLPI_FILESYSTEM_GROUP",
    "glpi.app_packages": "GLPI_APP_PACKAGES",
    "glpi.redis.cache_prefix": "GLPI_REDIS_CACHE_PREFIX",
    "glpi.redis.session_locking": "GLPI_REDIS_SESSION_LOCKING",
    "glpi.redis.maxmemory": "GLPI_REDIS_MAXMEMORY",
    "glpi.redis.maxmemory_policy": "GLPI_REDIS_MAXMEMORY_POLICY",
    "database.name": "DATABASE_NAME",
    "database.user": "DATABASE_USER",
    "database.port": "DATABASE_PORT",
    "database.bind_address": "DATABASE_BIND_ADDRESS",
    "database.packages": "DATABASE_PACKAGES",
    "database.deployment_mode": "DATABASE_DEPLOYMENT_MODE",
    "database.compatibility_policy": "DATABASE_COMPATIBILITY_POLICY",
    "database.compatibility_justification": "DATABASE_COMPATIBILITY_JUSTIFICATION",
    "database.compatibility_require_interactive_confirmation": "DATABASE_COMPATIBILITY_REQUIRE_INTERACTIVE_CONFIRMATION",
    "database.compatibility_assume_yes": "DATABASE_COMPATIBILITY_ASSUME_YES",
    "database.unsupported_prod_override": "DATABASE_UNSUPPORTED_PROD_OVERRIDE",
    "php_fpm.service_name": "PHP_FPM_SERVICE_NAME",
    "php_fpm.socket": "PHP_FPM_SOCKET",
    "php_fpm.pm": "PHP_FPM_PM",
    "web.http_port": "WEB_HTTP_PORT",
    "web.https_port": "WEB_HTTPS_PORT",
    "tls.mode": "TLS_MODE",
    "tls.common_name": "TLS_COMMON_NAME",
    "tls.certificate_path": "TLS_CERTIFICATE_PATH",
    "tls.private_key_path": "TLS_PRIVATE_KEY_PATH",
    "tls.provided_local_cert_path": "TLS_PROVIDED_LOCAL_CERT_PATH",
    "tls.provided_local_key_path": "TLS_PROVIDED_LOCAL_KEY_PATH",
    "backup.base_dir": "BACKUP_BASE_DIR",
    "backup.retention_days": "BACKUP_RETENTION_DAYS",
    "monitoring.profile": "MONITORING_PROFILE",
    "monitoring.prometheus.enabled": "MONITORING_PROMETHEUS_ENABLED",
    "monitoring.prometheus.bind_host": "MONITORING_PROMETHEUS_BIND_HOST",
    "monitoring.prometheus.port": "MONITORING_PROMETHEUS_PORT",
    "monitoring.prometheus.retention_time": "MONITORING_PROMETHEUS_RETENTION_TIME",
    "monitoring.prometheus.retention_size": "MONITORING_PROMETHEUS_RETENTION_SIZE",
    "monitoring.grafana.enabled": "MONITORING_GRAFANA_ENABLED",
    "monitoring.grafana.admin_user": "MONITORING_GRAFANA_ADMIN_USER",
    "monitoring.grafana.bind_host": "MONITORING_GRAFANA_BIND_HOST",
    "monitoring.grafana.port": "MONITORING_GRAFANA_PORT",
    "monitoring.grafana.public_mode": "MONITORING_GRAFANA_PUBLIC_MODE",
    "monitoring.grafana.public_path": "MONITORING_GRAFANA_PUBLIC_PATH",
    "monitoring.grafana.public_fqdn": "MONITORING_GRAFANA_PUBLIC_FQDN",
    "monitoring.grafana.domain": "MONITORING_GRAFANA_DOMAIN",
    "monitoring.grafana.require_auth": "MONITORING_GRAFANA_REQUIRE_AUTH",
    "monitoring.grafana.require_https": "MONITORING_GRAFANA_REQUIRE_HTTPS",
    "monitoring.exporters.bind_host": "MONITORING_EXPORTER_BIND_HOST",
    "monitoring.exporters.allowed_source_hosts": "MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS",
    "monitoring.exporters.node.enabled": "MONITORING_NODE_EXPORTER_ENABLED",
    "monitoring.exporters.mysqld.enabled": "MONITORING_MYSQLD_EXPORTER_ENABLED",
    "monitoring.exporters.mysqld.user": "MONITORING_MYSQLD_EXPORTER_USER",
    "monitoring.exporters.nginx.enabled": "MONITORING_NGINX_EXPORTER_ENABLED",
    "monitoring.exporters.php_fpm.enabled": "MONITORING_PHP_FPM_EXPORTER_ENABLED",
    "monitoring.exporters.blackbox.enabled": "MONITORING_BLACKBOX_EXPORTER_ENABLED",
    "monitoring.blackbox.targets": "MONITORING_BLACKBOX_TARGETS_JSON",
    "monitoring.glpi_custom_metrics.enabled": "MONITORING_GLPI_CUSTOM_METRICS_ENABLED",
    "monitoring.glpi_custom_metrics.interval_seconds": "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS",
    "monitoring.glpi_custom_metrics.db_user": "MONITORING_GLPI_METRICS_DB_USER",
    "monitoring.glpi_backup_freshness.enabled": "MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED",
    "monitoring.glpi_backup_freshness.max_age_hours": "MONITORING_GLPI_BACKUP_MAX_AGE_HOURS",
    "monitoring.labels": "MONITORING_LABELS_JSON",
    "monitoring.thresholds": "MONITORING_THRESHOLDS_JSON",
    "monitoring.scrape_profiles": "MONITORING_SCRAPE_PROFILES_JSON",
    "monitoring.dashboard_profile": "MONITORING_DASHBOARD_PROFILE",
    "monitoring.alert_routes": "MONITORING_ALERT_ROUTES_JSON",
    "alerting.alertmanager.enabled": "ALERTMANAGER_ENABLED",
    "alerting.alertmanager.bind_host": "MONITORING_ALERTMANAGER_BIND_HOST",
    "alerting.alertmanager.port": "MONITORING_ALERTMANAGER_PORT",
    "alerting.tls_expiry_warning_days": "ALERTING_TLS_EXPIRY_WARNING_DAYS",
    "alerting.backup_failure_enabled": "ALERTING_BACKUP_FAILURE_ENABLED",
    "alerting.service_down_enabled": "ALERTING_SERVICE_DOWN_ENABLED",
    "security.allow_insecure_non_production": "SECURITY_ALLOW_INSECURE_NON_PRODUCTION",
    "security.require_tls": "SECURITY_REQUIRE_TLS",
    "security.require_tls_in_production": "SECURITY_REQUIRE_TLS",
    "security.require_https": "SECURITY_REQUIRE_HTTPS",
    "security.require_https_in_production": "SECURITY_REQUIRE_HTTPS",
    "security.require_promotion_gate": "SECURITY_REQUIRE_PROMOTION_GATE",
    "security.require_ordered_execution": "SECURITY_REQUIRE_ORDERED_EXECUTION",
    "paths.glpi_release_root": "PATH_GLPI_RELEASE_ROOT",
    "paths.glpi_install_dir": "PATH_GLPI_INSTALL_DIR",
    "paths.glpi_config_dir": "PATH_GLPI_CONFIG_DIR",
    "paths.glpi_var_dir": "PATH_GLPI_VAR_DIR",
    "paths.glpi_plugin_dir": "PATH_GLPI_PLUGIN_DIR",
    "paths.glpi_log_dir": "PATH_GLPI_LOG_DIR",
    "operations.timezone": "OPERATIONS_TIMEZONE",
    "operations.glpi_timezone_support_enabled": "GLPI_TIMEZONE_SUPPORT_ENABLED",
    "operations.glpi_timezone_db_mode": "GLPI_TIMEZONE_DB_MODE",
    "operations.glpi_timezone_db_legacy_grant": "GLPI_TIMEZONE_DB_LEGACY_GRANT",
    "operations.glpi_cron_schedule": "OPERATIONS_GLPI_CRON_SCHEDULE",
    "operations.required_ops_group": "OPERATIONS_REQUIRED_OPS_GROUP",
    "operations.security_mode_default": "OPERATIONS_SECURITY_MODE_DEFAULT",
    "email.mailpit.enabled": "EMAIL_MAILPIT_ENABLED",
    "email.mailpit.image": "EMAIL_MAILPIT_IMAGE",
    "email.mailpit.ui_path": "EMAIL_MAILPIT_UI_PATH",
    "email.mailpit.ui_bind_host": "EMAIL_MAILPIT_UI_BIND_HOST",
    "email.mailpit.ui_internal_port": "EMAIL_MAILPIT_UI_INTERNAL_PORT",
    "email.mailpit.smtp_bind_host": "EMAIL_MAILPIT_SMTP_BIND_HOST",
    "email.mailpit.smtp_port": "EMAIL_MAILPIT_SMTP_PORT",
    "email.mailpit.max_messages": "EMAIL_MAILPIT_MAX_MESSAGES",
    "resource_profiles.active": "RESOURCE_PROFILE_ACTIVE",
}

BOOL_KEYS = {
    "MONITORING_PROMETHEUS_ENABLED",
    "MONITORING_GRAFANA_ENABLED",
    "MONITORING_GRAFANA_REQUIRE_AUTH",
    "MONITORING_GRAFANA_REQUIRE_HTTPS",
    "MONITORING_NODE_EXPORTER_ENABLED",
    "MONITORING_MYSQLD_EXPORTER_ENABLED",
    "MONITORING_NGINX_EXPORTER_ENABLED",
    "MONITORING_PHP_FPM_EXPORTER_ENABLED",
    "MONITORING_BLACKBOX_EXPORTER_ENABLED",
    "MONITORING_GLPI_CUSTOM_METRICS_ENABLED",
    "MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED",
    "ALERTMANAGER_ENABLED",
    "ALERTING_BACKUP_FAILURE_ENABLED",
    "ALERTING_SERVICE_DOWN_ENABLED",
    "SECURITY_ALLOW_INSECURE_NON_PRODUCTION",
    "SECURITY_REQUIRE_TLS",
    "SECURITY_REQUIRE_HTTPS",
    "SECURITY_REQUIRE_PROMOTION_GATE",
    "SECURITY_REQUIRE_ORDERED_EXECUTION",
    "GLPI_TIMEZONE_SUPPORT_ENABLED",
    "GLPI_TIMEZONE_DB_LEGACY_GRANT",
    "EMAIL_MAILPIT_ENABLED",
}

TRUE_VALUES = {"1", "true", "yes", "on"}
FALSE_VALUES = {"0", "false", "no", "off"}


def read_os_release(os_release_path=None) -> dict:
    path = os_release_path or Path(os.environ.get("GLPI_OS_RELEASE_FILE", "/etc/os-release"))
    if not path.is_file():
        return {}
    values = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')
    return values


def detect_platform_family(os_release=None) -> str:
    release = os_release if os_release is not None else read_os_release()
    distro_id = release.get("ID", "").lower()
    id_like = set(release.get("ID_LIKE", "").lower().split())
    if distro_id in {"ubuntu", "debian"} or {"ubuntu", "debian"} & id_like:
        return "debian"
    if distro_id in {"rocky", "rhel", "almalinux", "centos"} or {"rhel", "centos"} & id_like:
        return "rhel"
    return "debian"


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def fail_config_check(message: str, correction: str) -> None:
    fail(
        f"Configuration check failed: {message}\n"
        f"Correction required: {correction}\n"
        "Update config/<environment>.env and rerun the check before continuing."
    )


def parse_env_file(config_path: Path) -> dict:
    if not config_path.is_file():
        fail(f"Missing configuration file: {config_path}")

    values = {}
    for line_number, raw_line in enumerate(config_path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            fail(f"Invalid config line {line_number}: expected KEY=value format.")
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            fail(f"Invalid config line {line_number}: empty key.")
        if value.startswith(("'", '"')) and value.endswith(("'", '"')) and len(value) >= 2:
            value = value[1:-1]
        values[key] = value
    return values


def env_key_from_query(query: str) -> str:
    if query in DOTTED_KEY_MAP:
        return DOTTED_KEY_MAP[query]
    if query.isupper() and "_" in query:
        return query
    translated = query.replace(".", "_").replace("-", "_").upper()
    return translated


def as_bool(value: str, default: bool) -> bool:
    normalized = (value or "").strip().lower()
    if normalized in TRUE_VALUES:
        return True
    if normalized in FALSE_VALUES:
        return False
    return default


def as_int(value: str, default: int) -> int:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return default


def as_list(value: str, default: list) -> list:
    raw = (value or "").strip()
    if not raw:
        return list(default)
    if raw.startswith("["):
        try:
            loaded = json.loads(raw)
            if isinstance(loaded, list):
                return loaded
            fail("List value must be a JSON array when using bracket syntax.")
        except json.JSONDecodeError as exc:
            fail(f"Invalid JSON list value: {exc}")
    return [entry.strip() for entry in raw.split(",") if entry.strip()]


def normalize_http_path(value: str, default: str, key_name: str = "EMAIL_MAILPIT_UI_PATH") -> str:
    path = (value or "").strip() or default
    if not path.startswith("/"):
        fail(f"{key_name} must start with '/'.")
    if path == "/":
        fail(f"{key_name} cannot be '/'.")
    if path != "/" and path.endswith("/"):
        path = path.rstrip("/")
    return path


def as_json_object(value: str, default: dict) -> dict:
    raw = (value or "").strip()
    if not raw:
        return dict(default)
    try:
        loaded = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON object value: {exc}")
    if not isinstance(loaded, dict):
        fail("Expected JSON object for map-based configuration field.")
    return loaded


def as_json_array(value: str, default: list) -> list:
    raw = (value or "").strip()
    if not raw:
        return list(default)
    try:
        loaded = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON array value: {exc}")
    if not isinstance(loaded, list):
        fail("Expected JSON array for list-based configuration field.")
    return loaded


def validate_integer_port(values: dict, key: str, default: str) -> int:
    raw_value = read_value(values, key, default).strip()
    if raw_value and not raw_value.isdigit():
        fail_config_check(f"{key} must be an integer.", f"Set {key} to a valid TCP port number between 1 and 65535.")
    port = as_int(raw_value or default, as_int(default, 0))
    if not (1 <= port <= 65535):
        fail_config_check(f"{key} must be between 1 and 65535.", f"Adjust {key} to a free TCP port in the valid range.")
    return port


def is_loopback_bind(bind_host: str) -> bool:
    normalized = (bind_host or "").strip().lower()
    return normalized in {"127.0.0.1", "localhost", "::1"}


def is_blocked_public_bind(bind_host: str) -> bool:
    normalized = (bind_host or "").strip().lower()
    return normalized in {"", "0.0.0.0", "::", "*", "any", "all"}


def validate_restricted_source_list(sources: list[str], key_name: str) -> None:
    blocked = {"0.0.0.0/0", "::/0", "any", "all", "*", "0.0.0.0", "::"}
    for source in sources:
        if str(source).strip().lower() in blocked:
            fail_config_check(
                f"{key_name} contains a broad source entry: {source}",
                f"Replace {key_name} with explicit Prometheus source IPs or hostnames.",
            )


def validate_http_url_list(urls: list, key_name: str) -> list[str]:
    normalized_urls = []
    for raw_url in urls:
        url = str(raw_url).strip()
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            fail_config_check(
                f"{key_name} contains an invalid target: {url}",
                f"Use only explicit http:// or https:// URLs in {key_name}.",
            )
        normalized_urls.append(url)
    return normalized_urls


def read_value(values: dict, key: str, default: str = "") -> str:
    return str(values.get(key, default))


def require_value(values: dict, key: str) -> str:
    value = read_value(values, key, "")
    if value.strip():
        return value
    metadata = REQUIRED_PUBLIC_KEYS.get(key) or SSH_REQUIRED_KEYS.get(key, {})
    print(f"Missing required config key: {key}", file=sys.stderr)
    if metadata:
        print(f"Purpose: {metadata['purpose']}", file=sys.stderr)
        print(f"Used by: {metadata['consumer']}", file=sys.stderr)
    sys.exit(1)


def resolve_execution_contract(values: dict) -> tuple[str, str]:
    mode = (os.getenv("GLPI_EXECUTION_MODE", "").strip() or read_value(values, "EXECUTION_MODE", "local").strip() or "local")
    role = (os.getenv("GLPI_HOST_ROLE", "").strip() or read_value(values, "EXECUTION_HOST_ROLE_DEFAULT", "all").strip() or "all")

    if mode not in EXECUTION_MODES:
        fail(f"Invalid execution mode '{mode}'. Allowed: {sorted(EXECUTION_MODES)}")
    if role not in HOST_ROLES:
        fail(f"Invalid host role '{role}'. Allowed: {sorted(HOST_ROLES)}")
    return mode, role


def resolve_database_deployment_mode(values: dict) -> str:
    mode = read_value(values, "DATABASE_DEPLOYMENT_MODE", "self_hosted").strip().lower() or "self_hosted"
    if mode not in DB_DEPLOYMENT_MODES:
        fail("DATABASE_DEPLOYMENT_MODE must be one of: self_hosted, managed.")
    return mode


def profile_value(values: dict, profile_name: str, suffix: str, default: str) -> str:
    key = f"RESOURCE_PROFILE_{profile_name.upper()}_{suffix}"
    return read_value(values, key, default)


def ensure_required_keys(values: dict, execution_mode: str, db_deployment_mode: str) -> None:
    for key in REQUIRED_PUBLIC_KEYS:
        if db_deployment_mode == "managed" and key == "DATABASE_ROOT_PASSWORD":
            continue
        require_value(values, key)
    if execution_mode == "ssh":
        for key in SSH_REQUIRED_KEYS:
            require_value(values, key)


def validate_no_legacy_web_port_keys(values: dict) -> None:
    if "NGINX_HTTP_PORT" in values or "NGINX_HTTPS_PORT" in values:
        fail_config_check(
            "Legacy keys detected: NGINX_HTTP_PORT/NGINX_HTTPS_PORT. "
            "Migrate to WEB_HTTP_PORT/WEB_HTTPS_PORT.",
            "Remove NGINX_HTTP_PORT/NGINX_HTTPS_PORT and set WEB_HTTP_PORT/WEB_HTTPS_PORT instead.",
        )


def validate_feature_contract(values: dict, execution_mode: str, db_deployment_mode: str) -> None:
    topology_mode = read_value(values, "TOPOLOGY_MODE", "dual-server").strip().lower() or "dual-server"
    if topology_mode not in TOPOLOGY_MODES:
        fail("TOPOLOGY_MODE must be one of: single-server, dual-server.")

    db_access_mode = read_value(values, "NETWORK_DATABASE_ACCESS_MODE", "restricted").strip().lower() or "restricted"
    if db_access_mode not in DB_ACCESS_MODES:
        fail("NETWORK_DATABASE_ACCESS_MODE must be one of: restricted, open.")

    if db_deployment_mode not in DB_DEPLOYMENT_MODES:
        fail("DATABASE_DEPLOYMENT_MODE must be one of: self_hosted, managed.")
    timezone_db_mode = read_value(values, "GLPI_TIMEZONE_DB_MODE", "disabled").strip().lower() or "disabled"
    if timezone_db_mode not in GLPI_TIMEZONE_DB_MODES:
        fail("GLPI_TIMEZONE_DB_MODE must be one of: disabled, validate, apply.")

    tls_mode = require_value(values, "TLS_MODE").strip().lower()
    if tls_mode not in TLS_MODES:
        fail("TLS_MODE must be one of: none, self_signed, provided.")

    web_server_type = read_value(values, "WEB_SERVER_TYPE", "nginx").strip().lower() or "nginx"
    if web_server_type not in WEB_SERVER_TYPES:
        fail_config_check("WEB_SERVER_TYPE must be one of: nginx, apache, lighttpd.", "Set WEB_SERVER_TYPE to nginx, apache, or lighttpd.")

    redis_session_locking = read_value(values, "GLPI_REDIS_SESSION_LOCKING", "0").strip() or "0"
    if redis_session_locking not in {"0", "1"}:
        fail_config_check(
            "GLPI_REDIS_SESSION_LOCKING must be 0 or 1.",
            "Use GLPI_REDIS_SESSION_LOCKING=0 for the default non-locking session mode, or 1 to enable phpredis session locking.",
        )

    monitoring_profile = read_value(values, "MONITORING_PROFILE", "minimal").strip().lower() or "minimal"
    if monitoring_profile not in MONITORING_PROFILES:
        fail_config_check(
            "MONITORING_PROFILE must be one of: minimal, standard, full, external_prometheus, external_grafana.",
            "Set MONITORING_PROFILE to the deployment profile that matches the enabled monitoring components.",
        )

    prometheus_enabled = as_bool(read_value(values, "MONITORING_PROMETHEUS_ENABLED", "false"), False)
    grafana_enabled = as_bool(read_value(values, "MONITORING_GRAFANA_ENABLED", "false"), False)
    node_exporter_enabled = as_bool(read_value(values, "MONITORING_NODE_EXPORTER_ENABLED", "true"), True)
    nginx_exporter_enabled = as_bool(read_value(values, "MONITORING_NGINX_EXPORTER_ENABLED", "false"), False)
    php_fpm_exporter_enabled = as_bool(read_value(values, "MONITORING_PHP_FPM_EXPORTER_ENABLED", "false"), False)
    blackbox_exporter_enabled = as_bool(read_value(values, "MONITORING_BLACKBOX_EXPORTER_ENABLED", "true"), True)
    mysqld_exporter_enabled = as_bool(read_value(values, "MONITORING_MYSQLD_EXPORTER_ENABLED", "false"), False)
    alertmanager_enabled = as_bool(read_value(values, "ALERTMANAGER_ENABLED", "false"), False)
    glpi_custom_metrics_enabled = as_bool(read_value(values, "MONITORING_GLPI_CUSTOM_METRICS_ENABLED", "false"), False)
    backup_freshness_enabled = as_bool(read_value(values, "MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED", "false"), False)
    grafana_require_auth = as_bool(read_value(values, "MONITORING_GRAFANA_REQUIRE_AUTH", "true"), True)
    grafana_require_https = as_bool(read_value(values, "MONITORING_GRAFANA_REQUIRE_HTTPS", "true"), True)
    grafana_public_mode = read_value(values, "MONITORING_GRAFANA_PUBLIC_MODE", "disabled").strip().lower() or "disabled"
    if grafana_public_mode not in MONITORING_GRAFANA_PUBLIC_MODES:
        fail_config_check(
            "MONITORING_GRAFANA_PUBLIC_MODE must be one of: disabled, path, subdomain.",
            "Set MONITORING_GRAFANA_PUBLIC_MODE to disabled, path, or subdomain.",
        )

    if "MONITORING_EXPORTER_BIND_HOST" in values and not read_value(values, "MONITORING_EXPORTER_BIND_HOST", "").strip():
        fail_config_check(
            "MONITORING_EXPORTER_BIND_HOST cannot be empty when configured.",
            "Set MONITORING_EXPORTER_BIND_HOST=127.0.0.1 or another explicit private bind address.",
        )
    exporter_bind_host = read_value(values, "MONITORING_EXPORTER_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1"
    exporter_allowed_sources = as_list(read_value(values, "MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS", ""), [])
    validate_restricted_source_list(exporter_allowed_sources, "MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS")
    exporter_enabled = (
        node_exporter_enabled
        or mysqld_exporter_enabled
        or nginx_exporter_enabled
        or php_fpm_exporter_enabled
        or blackbox_exporter_enabled
    )

    if exporter_enabled and is_blocked_public_bind(exporter_bind_host):
        fail_config_check(
            f"MONITORING_EXPORTER_BIND_HOST cannot be public or wildcard: {exporter_bind_host}",
            "Set MONITORING_EXPORTER_BIND_HOST=127.0.0.1 or a specific private interface address.",
        )

    if db_deployment_mode == "managed" and mysqld_exporter_enabled:
        fail_config_check(
            "MONITORING_MYSQLD_EXPORTER_ENABLED=true is not supported with DATABASE_DEPLOYMENT_MODE=managed "
            "in this project phase.",
            "Use DATABASE_DEPLOYMENT_MODE=self_hosted for this project, or disable MONITORING_MYSQLD_EXPORTER_ENABLED.",
        )

    if nginx_exporter_enabled and web_server_type != "nginx":
        fail_config_check(
            "MONITORING_NGINX_EXPORTER_ENABLED=true requires WEB_SERVER_TYPE=nginx.",
            "Set WEB_SERVER_TYPE=nginx or disable MONITORING_NGINX_EXPORTER_ENABLED.",
        )

    if exporter_enabled and not is_loopback_bind(exporter_bind_host) and not exporter_allowed_sources:
        fail_config_check(
            "MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS is required when exporters bind outside loopback.",
            "Prefer MONITORING_EXPORTER_BIND_HOST=127.0.0.1. If private-network scraping is required, set MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS to the Prometheus source hosts.",
        )

    if alertmanager_enabled:
        fail_config_check(
            "ALERTMANAGER_ENABLED=true is reserved for a later phase.",
            "Set ALERTMANAGER_ENABLED=false until the Alertmanager Ansible tasks/templates are implemented.",
        )

    if monitoring_profile == "minimal" and (
        mysqld_exporter_enabled
        or nginx_exporter_enabled
        or php_fpm_exporter_enabled
        or glpi_custom_metrics_enabled
        or backup_freshness_enabled
    ):
        fail_config_check(
            "MONITORING_PROFILE=minimal allows node_exporter, blackbox_exporter, and optional Grafana only.",
            "Use MONITORING_PROFILE=standard or full for app/db exporters and GLPI functional metrics.",
        )
    if monitoring_profile == "minimal" and not node_exporter_enabled:
        fail_config_check(
            "MONITORING_PROFILE=minimal requires MONITORING_NODE_EXPORTER_ENABLED=true.",
            "Enable MONITORING_NODE_EXPORTER_ENABLED or choose a profile that does not require node exporter.",
        )
    if monitoring_profile == "minimal" and not blackbox_exporter_enabled:
        fail_config_check(
            "MONITORING_PROFILE=minimal requires MONITORING_BLACKBOX_EXPORTER_ENABLED=true.",
            "Enable MONITORING_BLACKBOX_EXPORTER_ENABLED or choose a profile that does not require blackbox.",
        )
    if backup_freshness_enabled and not glpi_custom_metrics_enabled:
        fail_config_check(
            "MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED=true requires MONITORING_GLPI_CUSTOM_METRICS_ENABLED=true.",
            "Enable MONITORING_GLPI_CUSTOM_METRICS_ENABLED or disable backup freshness monitoring.",
        )
    if glpi_custom_metrics_enabled and db_deployment_mode != "self_hosted":
        fail_config_check(
            "MONITORING_GLPI_CUSTOM_METRICS_ENABLED=true requires DATABASE_DEPLOYMENT_MODE=self_hosted in this phase.",
            "Use DATABASE_DEPLOYMENT_MODE=self_hosted or disable GLPI custom metrics.",
        )
    if monitoring_profile == "standard" and (
        not prometheus_enabled
        or not grafana_enabled
        or not node_exporter_enabled
        or not mysqld_exporter_enabled
        or not nginx_exporter_enabled
        or not php_fpm_exporter_enabled
        or not blackbox_exporter_enabled
    ):
        fail_config_check(
            "MONITORING_PROFILE=standard requires Prometheus, Grafana, node, mysqld, nginx, php-fpm, and blackbox exporters enabled.",
            "Enable the standard monitoring component toggles, or choose MONITORING_PROFILE=minimal.",
        )
    if monitoring_profile == "full" and (
        not prometheus_enabled
        or not grafana_enabled
        or not node_exporter_enabled
        or not mysqld_exporter_enabled
        or not nginx_exporter_enabled
        or not php_fpm_exporter_enabled
        or not blackbox_exporter_enabled
        or not glpi_custom_metrics_enabled
        or not backup_freshness_enabled
    ):
        fail_config_check(
            "MONITORING_PROFILE=full requires standard monitoring plus GLPI functional metrics and backup freshness.",
            "Enable all standard component toggles plus MONITORING_GLPI_CUSTOM_METRICS_ENABLED and MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED.",
        )
    if monitoring_profile == "external_prometheus" and (prometheus_enabled or grafana_enabled):
        fail_config_check(
            "MONITORING_PROFILE=external_prometheus requires local Prometheus/Grafana disabled.",
            "Set MONITORING_PROMETHEUS_ENABLED=false and MONITORING_GRAFANA_ENABLED=false for external Prometheus mode.",
        )
    if monitoring_profile == "external_grafana" and (not prometheus_enabled or grafana_enabled):
        fail_config_check(
            "MONITORING_PROFILE=external_grafana requires local Prometheus enabled and local Grafana disabled.",
            "Set MONITORING_PROMETHEUS_ENABLED=true and MONITORING_GRAFANA_ENABLED=false.",
        )

    prometheus_port = validate_integer_port(values, "MONITORING_PROMETHEUS_PORT", "9090")
    grafana_port = validate_integer_port(values, "MONITORING_GRAFANA_PORT", "3000")
    alertmanager_port = validate_integer_port(values, "MONITORING_ALERTMANAGER_PORT", "9093")
    web_http_port = validate_integer_port(values, "WEB_HTTP_PORT", "80")
    web_https_port = validate_integer_port(values, "WEB_HTTPS_PORT", "443")
    declared_ports = {
        "WEB_HTTP_PORT": web_http_port,
        "WEB_HTTPS_PORT": web_https_port,
    }
    if prometheus_enabled:
        declared_ports["MONITORING_PROMETHEUS_PORT"] = prometheus_port
    if grafana_enabled:
        declared_ports["MONITORING_GRAFANA_PORT"] = grafana_port
    if alertmanager_enabled:
        declared_ports["MONITORING_ALERTMANAGER_PORT"] = alertmanager_port
    seen_ports = {}
    for key, port in declared_ports.items():
        if port in seen_ports:
            fail_config_check(
                f"{key} conflicts with {seen_ports[port]} on port {port}.",
                f"Change {key} or {seen_ports[port]} to a different free port.",
            )
        seen_ports[port] = key

    grafana_public_path = normalize_http_path(
        read_value(values, "MONITORING_GRAFANA_PUBLIC_PATH", "/monitoring"),
        "/monitoring",
        "MONITORING_GRAFANA_PUBLIC_PATH",
    )
    email_mailpit_path = normalize_http_path(read_value(values, "EMAIL_MAILPIT_UI_PATH", "/mailpit"), "/mailpit")
    if grafana_public_path == email_mailpit_path:
        fail_config_check(
            "MONITORING_GRAFANA_PUBLIC_PATH conflicts with EMAIL_MAILPIT_UI_PATH.",
            "Set MONITORING_GRAFANA_PUBLIC_PATH and EMAIL_MAILPIT_UI_PATH to different URL paths.",
        )

    grafana_public_fqdn = read_value(
        values,
        "MONITORING_GRAFANA_PUBLIC_FQDN",
        read_value(values, "MONITORING_GRAFANA_DOMAIN", ""),
    ).strip()
    if grafana_public_mode == "path" and grafana_public_fqdn:
        fail_config_check(
            "MONITORING_GRAFANA_PUBLIC_MODE=path cannot also set a Grafana public FQDN.",
            "Clear MONITORING_GRAFANA_PUBLIC_FQDN/MONITORING_GRAFANA_DOMAIN or use MONITORING_GRAFANA_PUBLIC_MODE=subdomain.",
        )
    if grafana_public_mode != "disabled" and not grafana_enabled:
        fail_config_check(
            "MONITORING_GRAFANA_PUBLIC_MODE requires MONITORING_GRAFANA_ENABLED=true.",
            "Enable MONITORING_GRAFANA_ENABLED or set MONITORING_GRAFANA_PUBLIC_MODE=disabled.",
        )
    if grafana_public_mode != "disabled" and not grafana_require_auth:
        fail_config_check(
            "External Grafana publication requires MONITORING_GRAFANA_REQUIRE_AUTH=true.",
            "Set MONITORING_GRAFANA_REQUIRE_AUTH=true before publishing Grafana.",
        )
    if grafana_public_mode != "disabled" and grafana_require_https and tls_mode == "none":
        fail_config_check(
            "External Grafana publication requires HTTPS.",
            "Set TLS_MODE=self_signed or TLS_MODE=provided, or disable MONITORING_GRAFANA_REQUIRE_HTTPS only for an accepted non-production risk.",
        )
    if grafana_public_mode == "subdomain" and not grafana_public_fqdn:
        fail_config_check(
            "MONITORING_GRAFANA_PUBLIC_FQDN is required when MONITORING_GRAFANA_PUBLIC_MODE=subdomain.",
            "Set MONITORING_GRAFANA_PUBLIC_FQDN to the monitoring FQDN or use MONITORING_GRAFANA_PUBLIC_MODE=path.",
        )

    blackbox_targets = validate_http_url_list(
        as_json_array(read_value(values, "MONITORING_BLACKBOX_TARGETS_JSON", "[]"), []),
        "MONITORING_BLACKBOX_TARGETS_JSON",
    )
    if blackbox_exporter_enabled and not blackbox_targets:
        default_scheme = "https" if tls_mode != "none" else "http"
        blackbox_targets = [f"{default_scheme}://{require_value(values, 'GLPI_DOMAIN').strip()}/"]

    custom_interval = as_int(read_value(values, "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS", "300"), 300)
    if custom_interval < 60:
        fail_config_check(
            "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS must be at least 60.",
            "Use a collection interval of 60 seconds or higher; 300 is the recommended default.",
        )
    if custom_interval > 3600:
        fail_config_check(
            "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS cannot be greater than 3600 in this phase.",
            "Use an interval between 60 and 3600 seconds; 300 is the recommended default.",
        )
    if custom_interval % 60 != 0:
        fail_config_check(
            "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS must be a multiple of 60.",
            "Use a cron-compatible interval such as 60, 300, 600, or 900 seconds.",
        )
    backup_max_age = as_int(read_value(values, "MONITORING_GLPI_BACKUP_MAX_AGE_HOURS", "24"), 24)
    if backup_max_age < 1:
        fail_config_check(
            "MONITORING_GLPI_BACKUP_MAX_AGE_HOURS must be at least 1.",
            "Set MONITORING_GLPI_BACKUP_MAX_AGE_HOURS to a positive number of hours.",
        )

    if execution_mode == "ssh":
        ssh_key_path = os.path.expanduser(require_value(values, "NETWORK_SSH_PRIVATE_KEY_PATH").strip())
        if not Path(ssh_key_path).is_file():
            fail(f"NETWORK_SSH_PRIVATE_KEY_PATH is not available or is not a file: {ssh_key_path}")

    if tls_mode == "provided":
        local_cert_path = os.path.expanduser(require_value(values, "TLS_PROVIDED_LOCAL_CERT_PATH").strip())
        local_key_path = os.path.expanduser(require_value(values, "TLS_PROVIDED_LOCAL_KEY_PATH").strip())
        if not Path(local_cert_path).is_file():
            fail(f"TLS_PROVIDED_LOCAL_CERT_PATH is not available or is not a file: {local_cert_path}")
        if not Path(local_key_path).is_file():
            fail(f"TLS_PROVIDED_LOCAL_KEY_PATH is not available or is not a file: {local_key_path}")

    normalize_http_path(read_value(values, "EMAIL_MAILPIT_UI_PATH", "/mailpit"), "/mailpit")
    for key in ("EMAIL_MAILPIT_UI_INTERNAL_PORT", "EMAIL_MAILPIT_SMTP_PORT", "EMAIL_MAILPIT_MAX_MESSAGES"):
        raw_value = read_value(values, key, "").strip()
        if raw_value and not raw_value.isdigit():
            fail(f"{key} must be an integer.")
    ui_port = as_int(read_value(values, "EMAIL_MAILPIT_UI_INTERNAL_PORT", "8025"), 8025)
    smtp_port = as_int(read_value(values, "EMAIL_MAILPIT_SMTP_PORT", "1025"), 1025)
    if not (1 <= ui_port <= 65535):
        fail("EMAIL_MAILPIT_UI_INTERNAL_PORT must be between 1 and 65535.")
    if not (1 <= smtp_port <= 65535):
        fail("EMAIL_MAILPIT_SMTP_PORT must be between 1 and 65535.")
    if ui_port == smtp_port:
        fail("EMAIL_MAILPIT_UI_INTERNAL_PORT and EMAIL_MAILPIT_SMTP_PORT must be different.")


def build_public_runtime(values: dict, execution_mode: str, host_role: str, db_deployment_mode: str) -> dict:
    active_profile_name = require_value(values, "RESOURCE_PROFILE_ACTIVE").strip().lower()
    if active_profile_name not in {"small", "medium", "large"}:
        fail("RESOURCE_PROFILE_ACTIVE must be one of: small, medium, large.")

    glpi_version = require_value(values, "GLPI_VERSION").strip()
    glpi_domain = require_value(values, "GLPI_DOMAIN").strip()
    tls_mode = require_value(values, "TLS_MODE").strip()
    if tls_mode not in TLS_MODES:
        fail("TLS_MODE must be one of: none, self_signed, provided.")
    web_server_type = read_value(values, "WEB_SERVER_TYPE", "nginx").strip().lower() or "nginx"
    if web_server_type not in WEB_SERVER_TYPES:
        fail("WEB_SERVER_TYPE must be one of: nginx, apache, lighttpd.")
    glpi_installation_mode = read_value(values, "GLPI_INSTALLATION_MODE", "cli").strip().lower() or "cli"
    if glpi_installation_mode not in GLPI_INSTALLATION_MODES:
        fail("GLPI_INSTALLATION_MODE must be one of: cli, wizard, defer.")
    glpi_wizard_reset_config_db = as_bool(read_value(values, "GLPI_WIZARD_RESET_CONFIG_DB", "false"), False)
    platform_family = detect_platform_family()
    platform_defaults = PLATFORM_DEFAULTS[platform_family]
    web_server_packages = WEB_SERVER_PACKAGES_BY_FAMILY[platform_family]
    default_app_packages = DEFAULT_GLPI_APP_PACKAGES_BY_FAMILY[platform_family]
    default_database_packages = DEFAULT_DATABASE_PACKAGES_BY_FAMILY[platform_family]

    environment_name = require_value(values, "ENVIRONMENT_NAME").strip()
    release_root = read_value(values, "PATH_GLPI_RELEASE_ROOT", "/usr/share").strip() or "/usr/share"
    ssh_key_path = os.path.expanduser(read_value(values, "NETWORK_SSH_PRIVATE_KEY_PATH", "").strip())

    app_host = require_value(values, "TOPOLOGY_APP_HOST")
    db_access_mode = read_value(values, "NETWORK_DATABASE_ACCESS_MODE", "restricted").strip().lower() or "restricted"
    if db_access_mode not in {"restricted", "open"}:
        fail("NETWORK_DATABASE_ACCESS_MODE must be one of: restricted, open.")
    db_app_access_host = read_value(values, "NETWORK_DATABASE_APP_ACCESS_HOST", app_host).strip() or app_host
    db_allowed_hosts_raw = read_value(values, "NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS", "").strip()
    restricted_db_sources = as_list(
        db_allowed_hosts_raw,
        [app_host],
    )
    if db_access_mode == "open" and db_allowed_hosts_raw:
        fail("When NETWORK_DATABASE_ACCESS_MODE=open, use NETWORK_DATABASE_ALLOWED_SOURCE_HOSTS= (empty value).")
    db_grant_host = db_app_access_host if db_access_mode == "restricted" else "%"
    db_firewall_open = db_access_mode == "open"
    db_firewall_sources = [] if db_firewall_open else restricted_db_sources
    environment_stage = read_value(values, "ENVIRONMENT_STAGE", environment_name).strip() or environment_name
    database_compatibility_policy = read_value(values, "DATABASE_COMPATIBILITY_POLICY", "block").strip().lower() or "block"
    if database_compatibility_policy not in {"block", "warn", "defer"}:
        fail("DATABASE_COMPATIBILITY_POLICY must be one of: block, warn, defer.")
    database_compatibility_justification = read_value(values, "DATABASE_COMPATIBILITY_JUSTIFICATION", "").strip()
    database_compatibility_require_interactive_confirmation = as_bool(
        read_value(values, "DATABASE_COMPATIBILITY_REQUIRE_INTERACTIVE_CONFIRMATION", "true"),
        True,
    )
    database_compatibility_assume_yes = as_bool(
        read_value(values, "DATABASE_COMPATIBILITY_ASSUME_YES", "false"),
        False,
    )
    database_unsupported_prod_override = as_bool(
        read_value(values, "DATABASE_UNSUPPORTED_PROD_OVERRIDE", "false"),
        False,
    )

    app_packages_value = read_value(values, "GLPI_APP_PACKAGES", "").strip()
    if app_packages_value:
        app_packages = as_list(app_packages_value, default_app_packages)
    else:
        app_packages = web_server_packages[web_server_type] + default_app_packages

    default_blackbox_target = f"{'https' if tls_mode != 'none' else 'http'}://{glpi_domain}/"
    blackbox_exporter_enabled = as_bool(read_value(values, "MONITORING_BLACKBOX_EXPORTER_ENABLED", "true"), True)
    monitoring_blackbox_targets = validate_http_url_list(
        as_json_array(
            read_value(values, "MONITORING_BLACKBOX_TARGETS_JSON", json.dumps([default_blackbox_target])),
            [default_blackbox_target],
        ),
        "MONITORING_BLACKBOX_TARGETS_JSON",
    )
    if blackbox_exporter_enabled and not monitoring_blackbox_targets:
        monitoring_blackbox_targets = [default_blackbox_target]

    public_runtime = {
        "product_name": require_value(values, "PRODUCT_NAME"),
        "product_slug": read_value(values, "PRODUCT_SLUG", "glpi-operations-kit"),
        "customer_display_name": require_value(values, "CUSTOMER_DISPLAY_NAME"),
        "customer_short_name": read_value(values, "CUSTOMER_SHORT_NAME", "example-customer"),
        "environment_name": environment_name,
        "environment_stage": environment_stage,
        "execution_mode": execution_mode,
        "execution_host_role": host_role,
        "platform_family": platform_family,
        "topology_mode": read_value(values, "TOPOLOGY_MODE", "dual-server"),
        "database_deployment_mode": db_deployment_mode,
        "database_compatibility_policy": database_compatibility_policy,
        "database_compatibility_justification": database_compatibility_justification,
        "database_compatibility_require_interactive_confirmation": database_compatibility_require_interactive_confirmation,
        "database_compatibility_assume_yes": database_compatibility_assume_yes,
        "database_unsupported_prod_override": database_unsupported_prod_override,
        "glpi_version": glpi_version,
        "glpi_installation_mode": glpi_installation_mode,
        "glpi_wizard_reset_config_db": glpi_wizard_reset_config_db,
        "glpi_download_url": f"https://github.com/glpi-project/glpi/releases/download/{glpi_version}/glpi-{glpi_version}.tgz",
        "glpi_release_root": release_root,
        "glpi_release_dir": f"{release_root}/glpi-{glpi_version}",
        "glpi_install_dir": read_value(values, "PATH_GLPI_INSTALL_DIR", "/usr/share/glpi"),
        "glpi_config_dir": read_value(values, "PATH_GLPI_CONFIG_DIR", "/etc/glpi"),
        "glpi_var_dir": read_value(values, "PATH_GLPI_VAR_DIR", "/var/lib/glpi/files"),
        "glpi_plugin_dir": read_value(values, "PATH_GLPI_PLUGIN_DIR", "/var/lib/glpi/plugins"),
        "glpi_log_dir": read_value(values, "PATH_GLPI_LOG_DIR", "/var/log/glpi"),
        "glpi_backup_base_dir": read_value(values, "BACKUP_BASE_DIR", "/var/backups/glpi"),
        "glpi_domain": glpi_domain,
        "glpi_app_host": app_host,
        "glpi_db_host": require_value(values, "TOPOLOGY_DB_HOST"),
        "glpi_web_server_type": web_server_type,
        "glpi_use_tls": tls_mode != "none",
        "glpi_tls_mode": tls_mode,
        "glpi_tls_common_name": read_value(values, "TLS_COMMON_NAME", glpi_domain),
        "glpi_tls_certificate_path": read_value(values, "TLS_CERTIFICATE_PATH", f"/etc/ssl/certs/{environment_name}.crt"),
        "glpi_tls_certificate_key_path": read_value(values, "TLS_PRIVATE_KEY_PATH", f"/etc/ssl/private/{environment_name}.key"),
        "glpi_tls_provided_local_cert_path": os.path.expanduser(read_value(values, "TLS_PROVIDED_LOCAL_CERT_PATH", "").strip())
        if read_value(values, "TLS_PROVIDED_LOCAL_CERT_PATH", "").strip()
        else "",
        "glpi_tls_provided_local_key_path": os.path.expanduser(read_value(values, "TLS_PROVIDED_LOCAL_KEY_PATH", "").strip())
        if read_value(values, "TLS_PROVIDED_LOCAL_KEY_PATH", "").strip()
        else "",
        "glpi_data_owner": read_value(values, "GLPI_FILESYSTEM_OWNER", platform_defaults["glpi_data_owner"]),
        "glpi_data_group": read_value(values, "GLPI_FILESYSTEM_GROUP", platform_defaults["glpi_data_group"]),
        "glpi_php_fpm_service": read_value(values, "PHP_FPM_SERVICE_NAME", platform_defaults["php_fpm_service"]),
        "glpi_php_fpm_socket": read_value(values, "PHP_FPM_SOCKET", platform_defaults["php_fpm_socket"]),
        "glpi_php_fpm_test_command": platform_defaults["php_fpm_test_command"],
        "glpi_php_ini_fpm_path": platform_defaults["php_ini_fpm_path"],
        "glpi_php_ini_cli_path": platform_defaults["php_ini_cli_path"],
        "glpi_php_fpm_pool_path": platform_defaults["php_fpm_pool_path"],
        "glpi_php_fpm_default_pool_path": platform_defaults["php_fpm_default_pool_path"],
        "glpi_nginx_conf_available_path": platform_defaults["nginx_conf_available_path"],
        "glpi_nginx_conf_enabled_path": platform_defaults["nginx_conf_enabled_path"],
        "glpi_nginx_default_available_path": platform_defaults["nginx_default_available_path"],
        "glpi_nginx_default_enabled_path": platform_defaults["nginx_default_enabled_path"],
        "glpi_nginx_fastcgi_params": platform_defaults["nginx_fastcgi_params"],
        "glpi_web_service": WEB_SERVER_SERVICES[platform_family][web_server_type],
        "glpi_apache_service": platform_defaults["apache_service"],
        "glpi_apache_conf_path": platform_defaults["apache_conf_path"],
        "glpi_apache_default_conf_path": platform_defaults["apache_default_conf_path"],
        "web_http_port": as_int(require_value(values, "WEB_HTTP_PORT"), 80),
        "web_https_port": as_int(require_value(values, "WEB_HTTPS_PORT"), 443),
        "glpi_app_packages": app_packages,
        "glpi_upload_max_filesize": read_value(values, "GLPI_UPLOAD_MAX_FILESIZE", "32M"),
        "glpi_post_max_size": read_value(values, "GLPI_POST_MAX_SIZE", "32M"),
        "glpi_memory_limit": read_value(values, "GLPI_MEMORY_LIMIT", "512M"),
        "glpi_max_execution_time": as_int(read_value(values, "GLPI_MAX_EXECUTION_TIME", "120"), 120),
        "glpi_opcache_memory_consumption": as_int(read_value(values, "GLPI_OPCACHE_MEMORY_CONSUMPTION", "192"), 192),
        "glpi_pm": read_value(values, "PHP_FPM_PM", "dynamic"),
        "glpi_pm_max_children": as_int(profile_value(values, active_profile_name, "PHP_MAX_CHILDREN", "20"), 20),
        "glpi_pm_start_servers": as_int(profile_value(values, active_profile_name, "PHP_START_SERVERS", "4"), 4),
        "glpi_pm_min_spare_servers": as_int(profile_value(values, active_profile_name, "PHP_MIN_SPARE_SERVERS", "2"), 2),
        "glpi_pm_max_spare_servers": as_int(profile_value(values, active_profile_name, "PHP_MAX_SPARE_SERVERS", "6"), 6),
        "glpi_pm_max_requests": as_int(profile_value(values, active_profile_name, "PHP_MAX_REQUESTS", "500"), 500),
        "glpi_cron_schedule": read_value(values, "OPERATIONS_GLPI_CRON_SCHEDULE", read_value(values, "GLPI_CRON_SCHEDULE", "*/5 * * * *")),
        "glpi_redis_cache_prefix": read_value(values, "GLPI_REDIS_CACHE_PREFIX", "").strip(),
        "glpi_redis_session_locking": read_value(values, "GLPI_REDIS_SESSION_LOCKING", "0").strip() or "0",
        "glpi_redis_maxmemory": read_value(values, "GLPI_REDIS_MAXMEMORY", "").strip(),
        "glpi_redis_maxmemory_policy": read_value(values, "GLPI_REDIS_MAXMEMORY_POLICY", "").strip(),
        "glpi_backup_retention_days": as_int(read_value(values, "BACKUP_RETENTION_DAYS", "14"), 14),
        "monitoring_profile": read_value(values, "MONITORING_PROFILE", "minimal").strip().lower() or "minimal",
        "monitoring_prometheus_enabled": as_bool(read_value(values, "MONITORING_PROMETHEUS_ENABLED", "false"), False),
        "monitoring_prometheus_bind_host": read_value(values, "MONITORING_PROMETHEUS_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1",
        "monitoring_prometheus_port": as_int(read_value(values, "MONITORING_PROMETHEUS_PORT", "9090"), 9090),
        "monitoring_prometheus_retention_time": read_value(values, "MONITORING_PROMETHEUS_RETENTION_TIME", "15d").strip() or "15d",
        "monitoring_prometheus_retention_size": read_value(values, "MONITORING_PROMETHEUS_RETENTION_SIZE", "4GB").strip() or "4GB",
        "monitoring_grafana_enabled": as_bool(read_value(values, "MONITORING_GRAFANA_ENABLED", "false"), False),
        "monitoring_grafana_admin_user": read_value(values, "MONITORING_GRAFANA_ADMIN_USER", "daniel_monitor").strip() or "daniel_monitor",
        "monitoring_grafana_bind_host": read_value(values, "MONITORING_GRAFANA_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1",
        "monitoring_grafana_port": as_int(read_value(values, "MONITORING_GRAFANA_PORT", "3000"), 3000),
        "monitoring_grafana_public_mode": read_value(values, "MONITORING_GRAFANA_PUBLIC_MODE", "disabled").strip().lower() or "disabled",
        "monitoring_grafana_public_path": normalize_http_path(
            read_value(values, "MONITORING_GRAFANA_PUBLIC_PATH", "/monitoring"),
            "/monitoring",
            "MONITORING_GRAFANA_PUBLIC_PATH",
        ),
        "monitoring_grafana_public_fqdn": read_value(
            values,
            "MONITORING_GRAFANA_PUBLIC_FQDN",
            read_value(values, "MONITORING_GRAFANA_DOMAIN", ""),
        ).strip(),
        "monitoring_grafana_domain": read_value(values, "MONITORING_GRAFANA_DOMAIN", "").strip(),
        "monitoring_grafana_require_auth": as_bool(read_value(values, "MONITORING_GRAFANA_REQUIRE_AUTH", "true"), True),
        "monitoring_grafana_require_https": as_bool(read_value(values, "MONITORING_GRAFANA_REQUIRE_HTTPS", "true"), True),
        "monitoring_grafana_anonymous_enabled": False,
        "monitoring_exporter_bind_host": read_value(values, "MONITORING_EXPORTER_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1",
        "monitoring_exporter_allowed_source_hosts": as_list(read_value(values, "MONITORING_EXPORTER_ALLOWED_SOURCE_HOSTS", ""), []),
        "node_exporter_enabled": as_bool(read_value(values, "MONITORING_NODE_EXPORTER_ENABLED", "true"), True),
        "mysqld_exporter_enabled": as_bool(read_value(values, "MONITORING_MYSQLD_EXPORTER_ENABLED", "false"), False),
        "mysqld_exporter_user": require_value(values, "MONITORING_MYSQLD_EXPORTER_USER"),
        "nginx_exporter_enabled": as_bool(read_value(values, "MONITORING_NGINX_EXPORTER_ENABLED", "false"), False),
        "php_fpm_exporter_enabled": as_bool(read_value(values, "MONITORING_PHP_FPM_EXPORTER_ENABLED", "false"), False),
        "blackbox_exporter_enabled": blackbox_exporter_enabled,
        "monitoring_blackbox_targets": monitoring_blackbox_targets,
        "monitoring_glpi_custom_metrics_enabled": as_bool(read_value(values, "MONITORING_GLPI_CUSTOM_METRICS_ENABLED", "false"), False),
        "monitoring_glpi_custom_metrics_interval_seconds": as_int(read_value(values, "MONITORING_GLPI_CUSTOM_METRICS_INTERVAL_SECONDS", "300"), 300),
        "monitoring_glpi_metrics_db_user": read_value(values, "MONITORING_GLPI_METRICS_DB_USER", "amos_metrics").strip() or "amos_metrics",
        "monitoring_glpi_backup_freshness_enabled": as_bool(read_value(values, "MONITORING_GLPI_BACKUP_FRESHNESS_ENABLED", "false"), False),
        "monitoring_glpi_backup_max_age_hours": as_int(read_value(values, "MONITORING_GLPI_BACKUP_MAX_AGE_HOURS", "24"), 24),
        "monitoring_labels": as_json_object(read_value(values, "MONITORING_LABELS_JSON", "{}"), {}),
        "monitoring_thresholds": as_json_object(read_value(values, "MONITORING_THRESHOLDS_JSON", "{}"), {}),
        "monitoring_scrape_profiles": as_json_object(
            read_value(values, "MONITORING_SCRAPE_PROFILES_JSON", '{"default":{"interval":"30s","timeout":"10s"}}'),
            {"default": {"interval": "30s", "timeout": "10s"}},
        ),
        "monitoring_dashboard_profile": read_value(values, "MONITORING_DASHBOARD_PROFILE", "glpi-standard"),
        "monitoring_alert_routes": as_json_object(read_value(values, "MONITORING_ALERT_ROUTES_JSON", "{}"), {}),
        "alertmanager_enabled": as_bool(read_value(values, "ALERTMANAGER_ENABLED", "false"), False),
        "alertmanager_bind_host": read_value(values, "MONITORING_ALERTMANAGER_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1",
        "alertmanager_port": as_int(read_value(values, "MONITORING_ALERTMANAGER_PORT", "9093"), 9093),
        "alert_tls_expiry_warning_days": as_int(read_value(values, "ALERTING_TLS_EXPIRY_WARNING_DAYS", "30"), 30),
        "security_allow_insecure_non_production": as_bool(read_value(values, "SECURITY_ALLOW_INSECURE_NON_PRODUCTION", "true"), True),
        "security_require_tls": as_bool(read_value(values, "SECURITY_REQUIRE_TLS", "false"), False),
        "security_require_https": as_bool(read_value(values, "SECURITY_REQUIRE_HTTPS", "false"), False),
        "security_require_promotion_gate": as_bool(read_value(values, "SECURITY_REQUIRE_PROMOTION_GATE", "false"), False),
        "security_require_ordered_execution": as_bool(read_value(values, "SECURITY_REQUIRE_ORDERED_EXECUTION", "true"), True),
        "operations_security_mode_default": read_value(values, "OPERATIONS_SECURITY_MODE_DEFAULT", "secure"),
        "email_mailpit_enabled": as_bool(read_value(values, "EMAIL_MAILPIT_ENABLED", "false"), False),
        "email_mailpit_image": read_value(values, "EMAIL_MAILPIT_IMAGE", DEFAULT_MAILPIT_IMAGE).strip() or DEFAULT_MAILPIT_IMAGE,
        "email_mailpit_ui_path": normalize_http_path(read_value(values, "EMAIL_MAILPIT_UI_PATH", "/mailpit"), "/mailpit"),
        "email_mailpit_ui_bind_host": read_value(values, "EMAIL_MAILPIT_UI_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1",
        "email_mailpit_ui_internal_port": as_int(read_value(values, "EMAIL_MAILPIT_UI_INTERNAL_PORT", "8025"), 8025),
        "email_mailpit_smtp_bind_host": read_value(values, "EMAIL_MAILPIT_SMTP_BIND_HOST", "127.0.0.1").strip() or "127.0.0.1",
        "email_mailpit_smtp_port": as_int(read_value(values, "EMAIL_MAILPIT_SMTP_PORT", "1025"), 1025),
        "email_mailpit_max_messages": as_int(read_value(values, "EMAIL_MAILPIT_MAX_MESSAGES", "1000"), 1000),
        "email_mailpit_remote_base_dir": "/opt/glpi-mailpit",
        "email_mailpit_compose_project": "glpi-mailpit",
        "email_mailpit_container_name": "mailpit",
        "mariadb_bind_address": read_value(values, "DATABASE_BIND_ADDRESS", "0.0.0.0"),
        "mariadb_port": as_int(read_value(values, "DATABASE_PORT", "3306"), 3306),
        "mariadb_version_packages": as_list(read_value(values, "DATABASE_PACKAGES", ""), default_database_packages),
        "mariadb_innodb_buffer_pool_size": profile_value(values, active_profile_name, "MARIADB_INNODB_BUFFER_POOL_SIZE", "2G"),
        "mariadb_max_connections": as_int(profile_value(values, active_profile_name, "MARIADB_MAX_CONNECTIONS", "80"), 80),
        "mariadb_tmp_table_size": profile_value(values, active_profile_name, "MARIADB_TMP_TABLE_SIZE", "128M"),
        "mariadb_max_heap_table_size": profile_value(values, active_profile_name, "MARIADB_MAX_HEAP_TABLE_SIZE", "128M"),
        "mariadb_slow_query_log": as_int(profile_value(values, active_profile_name, "MARIADB_SLOW_QUERY_LOG", "1"), 1),
        "mariadb_long_query_time": as_int(profile_value(values, active_profile_name, "MARIADB_LONG_QUERY_TIME", "2"), 2),
        "timezone_name": require_value(values, "OPERATIONS_TIMEZONE"),
        "glpi_timezone_support_enabled": as_bool(read_value(values, "GLPI_TIMEZONE_SUPPORT_ENABLED", "false"), False),
        "glpi_timezone_db_mode": read_value(values, "GLPI_TIMEZONE_DB_MODE", "disabled").strip().lower() or "disabled",
        "glpi_timezone_db_legacy_grant": as_bool(read_value(values, "GLPI_TIMEZONE_DB_LEGACY_GRANT", "false"), False),
        "db_access_mode": db_access_mode,
        "db_grant_host": db_grant_host,
        "db_firewall_open": db_firewall_open,
        "db_firewall_sources": db_firewall_sources,
        "db_allowed_source_hosts": list(db_firewall_sources),
        "glpi_db_app_access_host": db_app_access_host,
        "glpi_db_name": require_value(values, "DATABASE_NAME"),
        "glpi_db_user": require_value(values, "DATABASE_USER"),
        "resource_profile_name": active_profile_name,
        "ssh_key_path_resolved": ssh_key_path,
    }
    return public_runtime


def build_inventory(values: dict, execution_mode: str, host_role: str, db_deployment_mode: str) -> dict:
    environment_name = require_value(values, "ENVIRONMENT_NAME")
    app_alias = require_value(values, "TOPOLOGY_APP_ALIAS")
    app_host = require_value(values, "TOPOLOGY_APP_HOST")
    db_alias = require_value(values, "TOPOLOGY_DB_ALIAS")
    db_host = require_value(values, "TOPOLOGY_DB_HOST")
    topology_mode = read_value(values, "TOPOLOGY_MODE", "dual-server")

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
        if include_db and db_deployment_mode != "managed":
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

    children = {
        "glpi_app": {
            "hosts": {
                app_alias: {
                    "ansible_host": app_host,
                }
            }
        },
    }
    if db_deployment_mode != "managed":
        children["glpi_db"] = {
            "hosts": {
                db_alias: {
                    "ansible_host": db_host,
                }
            }
        }

    return {
        "all": {
            "vars": {
                "ansible_user": require_value(values, "NETWORK_SSH_USER"),
                "ansible_ssh_private_key_file": os.path.expanduser(require_value(values, "NETWORK_SSH_PRIVATE_KEY_PATH")),
                "environment_name": environment_name,
            },
            "children": children,
        }
    }


def emit_scalar_for_get(values: dict, query: str) -> None:
    env_key = env_key_from_query(query)
    value = values.get(env_key, "")
    if env_key in BOOL_KEYS:
        normalized = str(value).strip().lower()
        if normalized in TRUE_VALUES:
            print("true")
            return
        if normalized in FALSE_VALUES:
            print("false")
            return
    print(value)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--mode", choices=["public-runtime", "inventory", "get"], required=True)
    parser.add_argument("--key")
    args = parser.parse_args()

    config_path = Path(args.config)
    values = parse_env_file(config_path)
    validate_no_legacy_web_port_keys(values)

    if args.mode == "get":
        if not args.key:
            fail("--key is required when mode=get.")
        emit_scalar_for_get(values, args.key)
        return

    try:
        import yaml
    except ModuleNotFoundError:
        fail("python3-yaml support is required. Install the OS Python YAML package.")

    execution_mode, host_role = resolve_execution_contract(values)
    db_deployment_mode = resolve_database_deployment_mode(values)
    ensure_required_keys(values, execution_mode, db_deployment_mode)
    validate_feature_contract(values, execution_mode, db_deployment_mode)

    result = build_public_runtime(values, execution_mode, host_role, db_deployment_mode) if args.mode == "public-runtime" else build_inventory(values, execution_mode, host_role, db_deployment_mode)
    yaml.safe_dump(result, sys.stdout, sort_keys=False, default_flow_style=False)


if __name__ == "__main__":
    main()
