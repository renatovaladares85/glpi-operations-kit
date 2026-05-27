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
AUTH_MODES = {"local", "ldap", "saml", "oidc"}
TOPOLOGY_MODES = {"single-server", "dual-server"}
DB_ACCESS_MODES = {"restricted", "open"}

DEFAULT_GLPI_APP_PACKAGES = [
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
    "tar",
    "xz-utils",
    "curl",
    "openssl",
    "mariadb-client",
]

WEB_SERVER_PACKAGES = {
    "nginx": ["nginx"],
    "apache": ["apache2", "libapache2-mod-fcgid"],
    "lighttpd": ["lighttpd"],
}

DEFAULT_DATABASE_PACKAGES = ["mariadb-server", "mariadb-client", "python3-pymysql"]

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
    "MONITORING_MYSQLD_EXPORTER_PASSWORD": {
        "purpose": "Defines the mysqld_exporter password.",
        "consumer": "runtime secrets materialization and monitoring role",
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
    "SECURITY_SSO_ENABLED": {
        "purpose": "Defines whether SSO policy is currently enabled for the environment.",
        "consumer": "policy checks",
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
    "database.name": "DATABASE_NAME",
    "database.user": "DATABASE_USER",
    "database.port": "DATABASE_PORT",
    "database.bind_address": "DATABASE_BIND_ADDRESS",
    "database.packages": "DATABASE_PACKAGES",
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
    "monitoring.exporters.node.enabled": "MONITORING_NODE_EXPORTER_ENABLED",
    "monitoring.exporters.mysqld.enabled": "MONITORING_MYSQLD_EXPORTER_ENABLED",
    "monitoring.exporters.mysqld.user": "MONITORING_MYSQLD_EXPORTER_USER",
    "monitoring.labels": "MONITORING_LABELS_JSON",
    "monitoring.thresholds": "MONITORING_THRESHOLDS_JSON",
    "monitoring.scrape_profiles": "MONITORING_SCRAPE_PROFILES_JSON",
    "monitoring.dashboard_profile": "MONITORING_DASHBOARD_PROFILE",
    "monitoring.alert_routes": "MONITORING_ALERT_ROUTES_JSON",
    "alerting.tls_expiry_warning_days": "ALERTING_TLS_EXPIRY_WARNING_DAYS",
    "alerting.backup_failure_enabled": "ALERTING_BACKUP_FAILURE_ENABLED",
    "alerting.service_down_enabled": "ALERTING_SERVICE_DOWN_ENABLED",
    "auth.mode": "AUTH_MODE",
    "auth.external_enabled": "AUTH_EXTERNAL_ENABLED",
    "auth.ldap_enabled": "AUTH_LDAP_ENABLED",
    "auth.saml_enabled": "AUTH_SAML_ENABLED",
    "auth.oidc_enabled": "AUTH_OIDC_ENABLED",
    "sso.provider": "SSO_PROVIDER",
    "sso.protocol": "SSO_PROTOCOL",
    "sso.public_url": "SSO_PUBLIC_URL",
    "sso.require_public_url": "SSO_REQUIRE_PUBLIC_URL",
    "auth.saml_plugin_expected": "AUTH_SAML_PLUGIN_EXPECTED",
    "auth.saml_plugin_name": "AUTH_SAML_PLUGIN_NAME",
    "auth.saml_entity_id": "AUTH_SAML_ENTITY_ID",
    "auth.saml_acs_url": "AUTH_SAML_ACS_URL",
    "auth.saml_logout_url": "AUTH_SAML_LOGOUT_URL",
    "auth.saml_nameid_format": "AUTH_SAML_NAMEID_FORMAT",
    "auth.saml_idp_entity_id": "AUTH_SAML_IDP_ENTITY_ID",
    "auth.saml_idp_sso_url": "AUTH_SAML_IDP_SSO_URL",
    "auth.saml_idp_slo_url": "AUTH_SAML_IDP_SLO_URL",
    "auth.saml_claim_email": "AUTH_SAML_CLAIM_EMAIL",
    "auth.saml_claim_username": "AUTH_SAML_CLAIM_USERNAME",
    "auth.saml_claim_firstname": "AUTH_SAML_CLAIM_FIRSTNAME",
    "auth.saml_claim_lastname": "AUTH_SAML_CLAIM_LASTNAME",
    "auth.saml_claim_groups": "AUTH_SAML_CLAIM_GROUPS",
    "auth.jit_enabled": "AUTH_JIT_ENABLED",
    "auth.default_profile": "AUTH_DEFAULT_PROFILE",
    "auth.group_admin": "AUTH_GROUP_ADMIN",
    "auth.group_technician": "AUTH_GROUP_TECHNICIAN",
    "auth.group_user": "AUTH_GROUP_USER",
    "security.sso_enabled": "SECURITY_SSO_ENABLED",
    "security.allow_insecure_non_production": "SECURITY_ALLOW_INSECURE_NON_PRODUCTION",
    "security.require_tls": "SECURITY_REQUIRE_TLS",
    "security.require_tls_in_production": "SECURITY_REQUIRE_TLS",
    "security.require_https": "SECURITY_REQUIRE_HTTPS",
    "security.require_https_in_production": "SECURITY_REQUIRE_HTTPS",
    "security.require_sso": "SECURITY_REQUIRE_SSO",
    "security.require_sso_in_production": "SECURITY_REQUIRE_SSO",
    "security.require_promotion_gate": "SECURITY_REQUIRE_PROMOTION_GATE",
    "security.require_ordered_execution": "SECURITY_REQUIRE_ORDERED_EXECUTION",
    "paths.glpi_release_root": "PATH_GLPI_RELEASE_ROOT",
    "paths.glpi_install_dir": "PATH_GLPI_INSTALL_DIR",
    "paths.glpi_config_dir": "PATH_GLPI_CONFIG_DIR",
    "paths.glpi_var_dir": "PATH_GLPI_VAR_DIR",
    "paths.glpi_plugin_dir": "PATH_GLPI_PLUGIN_DIR",
    "paths.glpi_log_dir": "PATH_GLPI_LOG_DIR",
    "operations.timezone": "OPERATIONS_TIMEZONE",
    "operations.glpi_cron_schedule": "OPERATIONS_GLPI_CRON_SCHEDULE",
    "operations.required_ops_group": "OPERATIONS_REQUIRED_OPS_GROUP",
    "operations.security_mode_default": "OPERATIONS_SECURITY_MODE_DEFAULT",
    "resource_profiles.active": "RESOURCE_PROFILE_ACTIVE",
}

BOOL_KEYS = {
    "MONITORING_NODE_EXPORTER_ENABLED",
    "MONITORING_MYSQLD_EXPORTER_ENABLED",
    "ALERTING_BACKUP_FAILURE_ENABLED",
    "ALERTING_SERVICE_DOWN_ENABLED",
    "AUTH_EXTERNAL_ENABLED",
    "AUTH_LDAP_ENABLED",
    "AUTH_SAML_ENABLED",
    "AUTH_OIDC_ENABLED",
    "SSO_REQUIRE_PUBLIC_URL",
    "AUTH_SAML_PLUGIN_EXPECTED",
    "AUTH_JIT_ENABLED",
    "SECURITY_SSO_ENABLED",
    "SECURITY_ALLOW_INSECURE_NON_PRODUCTION",
    "SECURITY_REQUIRE_TLS",
    "SECURITY_REQUIRE_HTTPS",
    "SECURITY_REQUIRE_SSO",
    "SECURITY_REQUIRE_PROMOTION_GATE",
    "SECURITY_REQUIRE_ORDERED_EXECUTION",
}

TRUE_VALUES = {"1", "true", "yes", "on"}
FALSE_VALUES = {"0", "false", "no", "off"}


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


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


def profile_value(values: dict, profile_name: str, suffix: str, default: str) -> str:
    key = f"RESOURCE_PROFILE_{profile_name.upper()}_{suffix}"
    return read_value(values, key, default)


def ensure_required_keys(values: dict, execution_mode: str) -> None:
    for key in REQUIRED_PUBLIC_KEYS:
        require_value(values, key)
    if execution_mode == "ssh":
        for key in SSH_REQUIRED_KEYS:
            require_value(values, key)


def validate_no_legacy_web_port_keys(values: dict) -> None:
    if "NGINX_HTTP_PORT" in values or "NGINX_HTTPS_PORT" in values:
        fail(
            "Legacy keys detected: NGINX_HTTP_PORT/NGINX_HTTPS_PORT. "
            "Migrate to WEB_HTTP_PORT/WEB_HTTPS_PORT."
        )


def validate_url(value: str, *, https_only: bool = False) -> bool:
    raw = (value or "").strip()
    if not raw:
        return False
    parsed = urlparse(raw)
    if https_only and parsed.scheme != "https":
        return False
    if not https_only and parsed.scheme not in {"http", "https"}:
        return False
    return bool(parsed.netloc)


def validate_feature_contract(values: dict, execution_mode: str) -> None:
    topology_mode = read_value(values, "TOPOLOGY_MODE", "dual-server").strip().lower() or "dual-server"
    if topology_mode not in TOPOLOGY_MODES:
        fail("TOPOLOGY_MODE must be one of: single-server, dual-server.")

    db_access_mode = read_value(values, "NETWORK_DATABASE_ACCESS_MODE", "restricted").strip().lower() or "restricted"
    if db_access_mode not in DB_ACCESS_MODES:
        fail("NETWORK_DATABASE_ACCESS_MODE must be one of: restricted, open.")

    tls_mode = require_value(values, "TLS_MODE").strip().lower()
    if tls_mode not in TLS_MODES:
        fail("TLS_MODE must be one of: none, self_signed, provided.")

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

    auth_mode = read_value(values, "AUTH_MODE", "local").strip().lower() or "local"
    if auth_mode not in AUTH_MODES:
        fail("AUTH_MODE must be one of: local, ldap, saml, oidc.")

    auth_external_enabled = as_bool(read_value(values, "AUTH_EXTERNAL_ENABLED", "false"), False)
    auth_ldap_enabled = as_bool(read_value(values, "AUTH_LDAP_ENABLED", "false"), False)
    auth_saml_enabled = as_bool(read_value(values, "AUTH_SAML_ENABLED", "false"), False)
    auth_oidc_enabled = as_bool(read_value(values, "AUTH_OIDC_ENABLED", "false"), False)
    sso_require_public_url = as_bool(read_value(values, "SSO_REQUIRE_PUBLIC_URL", "true"), True)

    auth_requires_external = auth_external_enabled or auth_mode != "local" or auth_ldap_enabled or auth_saml_enabled or auth_oidc_enabled
    auth_requires_https = auth_mode in {"saml", "oidc"} or auth_saml_enabled or auth_oidc_enabled

    if auth_requires_external:
        require_value(values, "AUTH_MODE")
        if sso_require_public_url:
            sso_public_url = require_value(values, "SSO_PUBLIC_URL").strip()
            if not validate_url(sso_public_url):
                fail("SSO_PUBLIC_URL must be a valid http:// or https:// URL when external auth is enabled.")

    if auth_requires_https:
        sso_public_url = require_value(values, "SSO_PUBLIC_URL").strip()
        if not validate_url(sso_public_url, https_only=True):
            fail("SSO_PUBLIC_URL must be a valid https:// URL when SAML/OIDC is enabled.")
        if tls_mode == "none":
            fail("TLS_MODE must not be 'none' when SAML/OIDC is enabled.")

    if auth_mode == "saml" or auth_saml_enabled:
        auth_saml_plugin_expected = as_bool(read_value(values, "AUTH_SAML_PLUGIN_EXPECTED", "true"), True)
        if auth_saml_plugin_expected:
            require_value(values, "AUTH_SAML_PLUGIN_NAME")

    security_require_sso = as_bool(read_value(values, "SECURITY_REQUIRE_SSO", "false"), False)
    security_sso_enabled = as_bool(require_value(values, "SECURITY_SSO_ENABLED"), False)
    if security_require_sso and not security_sso_enabled:
        fail("SECURITY_REQUIRE_SSO=true requires SECURITY_SSO_ENABLED=true.")


def build_public_runtime(values: dict, execution_mode: str, host_role: str) -> dict:
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

    app_packages_value = read_value(values, "GLPI_APP_PACKAGES", "").strip()
    if app_packages_value:
        app_packages = as_list(app_packages_value, DEFAULT_GLPI_APP_PACKAGES)
    else:
        app_packages = WEB_SERVER_PACKAGES[web_server_type] + DEFAULT_GLPI_APP_PACKAGES

    if web_server_type == "apache":
        app_packages.append("libapache2-mod-php8.3")

    public_runtime = {
        "product_name": require_value(values, "PRODUCT_NAME"),
        "product_slug": read_value(values, "PRODUCT_SLUG", "glpi-operations-kit"),
        "customer_display_name": require_value(values, "CUSTOMER_DISPLAY_NAME"),
        "customer_short_name": read_value(values, "CUSTOMER_SHORT_NAME", "example-customer"),
        "environment_name": environment_name,
        "environment_stage": read_value(values, "ENVIRONMENT_STAGE", environment_name),
        "execution_mode": execution_mode,
        "execution_host_role": host_role,
        "topology_mode": read_value(values, "TOPOLOGY_MODE", "dual-server"),
        "glpi_version": glpi_version,
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
        "glpi_data_owner": read_value(values, "GLPI_FILESYSTEM_OWNER", "www-data"),
        "glpi_data_group": read_value(values, "GLPI_FILESYSTEM_GROUP", "www-data"),
        "glpi_php_fpm_service": read_value(values, "PHP_FPM_SERVICE_NAME", "php8.3-fpm"),
        "glpi_php_fpm_socket": read_value(values, "PHP_FPM_SOCKET", "/run/php/php8.3-fpm.sock"),
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
        "glpi_backup_retention_days": as_int(read_value(values, "BACKUP_RETENTION_DAYS", "14"), 14),
        "node_exporter_enabled": as_bool(read_value(values, "MONITORING_NODE_EXPORTER_ENABLED", "true"), True),
        "mysqld_exporter_enabled": as_bool(read_value(values, "MONITORING_MYSQLD_EXPORTER_ENABLED", "true"), True),
        "mysqld_exporter_user": require_value(values, "MONITORING_MYSQLD_EXPORTER_USER"),
        "monitoring_labels": as_json_object(read_value(values, "MONITORING_LABELS_JSON", "{}"), {}),
        "monitoring_thresholds": as_json_object(read_value(values, "MONITORING_THRESHOLDS_JSON", "{}"), {}),
        "monitoring_scrape_profiles": as_json_object(
            read_value(values, "MONITORING_SCRAPE_PROFILES_JSON", '{"default":{"interval":"30s","timeout":"10s"}}'),
            {"default": {"interval": "30s", "timeout": "10s"}},
        ),
        "monitoring_dashboard_profile": read_value(values, "MONITORING_DASHBOARD_PROFILE", "glpi-standard"),
        "monitoring_alert_routes": as_json_object(read_value(values, "MONITORING_ALERT_ROUTES_JSON", "{}"), {}),
        "alert_tls_expiry_warning_days": as_int(read_value(values, "ALERTING_TLS_EXPIRY_WARNING_DAYS", "30"), 30),
        "auth_mode": read_value(values, "AUTH_MODE", "local").strip().lower() or "local",
        "auth_external_enabled": as_bool(read_value(values, "AUTH_EXTERNAL_ENABLED", "false"), False),
        "auth_ldap_enabled": as_bool(read_value(values, "AUTH_LDAP_ENABLED", "false"), False),
        "auth_saml_enabled": as_bool(read_value(values, "AUTH_SAML_ENABLED", "false"), False),
        "auth_oidc_enabled": as_bool(read_value(values, "AUTH_OIDC_ENABLED", "false"), False),
        "sso_provider": read_value(values, "SSO_PROVIDER", ""),
        "sso_protocol": read_value(values, "SSO_PROTOCOL", ""),
        "sso_public_url": read_value(values, "SSO_PUBLIC_URL", ""),
        "sso_require_public_url": as_bool(read_value(values, "SSO_REQUIRE_PUBLIC_URL", "true"), True),
        "auth_saml_plugin_expected": as_bool(read_value(values, "AUTH_SAML_PLUGIN_EXPECTED", "true"), True),
        "auth_saml_plugin_name": read_value(values, "AUTH_SAML_PLUGIN_NAME", "saml"),
        "auth_saml_entity_id": read_value(values, "AUTH_SAML_ENTITY_ID", ""),
        "auth_saml_acs_url": read_value(values, "AUTH_SAML_ACS_URL", ""),
        "auth_saml_logout_url": read_value(values, "AUTH_SAML_LOGOUT_URL", ""),
        "auth_saml_nameid_format": read_value(
            values,
            "AUTH_SAML_NAMEID_FORMAT",
            "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress",
        ),
        "auth_saml_idp_entity_id": read_value(values, "AUTH_SAML_IDP_ENTITY_ID", ""),
        "auth_saml_idp_sso_url": read_value(values, "AUTH_SAML_IDP_SSO_URL", ""),
        "auth_saml_idp_slo_url": read_value(values, "AUTH_SAML_IDP_SLO_URL", ""),
        "auth_saml_claim_email": read_value(values, "AUTH_SAML_CLAIM_EMAIL", "email"),
        "auth_saml_claim_username": read_value(values, "AUTH_SAML_CLAIM_USERNAME", "username"),
        "auth_saml_claim_firstname": read_value(values, "AUTH_SAML_CLAIM_FIRSTNAME", "firstname"),
        "auth_saml_claim_lastname": read_value(values, "AUTH_SAML_CLAIM_LASTNAME", "lastname"),
        "auth_saml_claim_groups": read_value(values, "AUTH_SAML_CLAIM_GROUPS", "groups"),
        "auth_jit_enabled": as_bool(read_value(values, "AUTH_JIT_ENABLED", "true"), True),
        "auth_default_profile": read_value(values, "AUTH_DEFAULT_PROFILE", "Self-Service"),
        "auth_group_admin": read_value(values, "AUTH_GROUP_ADMIN", "GLPI-Admins"),
        "auth_group_technician": read_value(values, "AUTH_GROUP_TECHNICIAN", "GLPI-Technicians"),
        "auth_group_user": read_value(values, "AUTH_GROUP_USER", "GLPI-Users"),
        "security_sso_enabled": as_bool(require_value(values, "SECURITY_SSO_ENABLED"), False),
        "security_allow_insecure_non_production": as_bool(read_value(values, "SECURITY_ALLOW_INSECURE_NON_PRODUCTION", "true"), True),
        "security_require_tls": as_bool(read_value(values, "SECURITY_REQUIRE_TLS", "false"), False),
        "security_require_https": as_bool(read_value(values, "SECURITY_REQUIRE_HTTPS", "false"), False),
        "security_require_sso": as_bool(read_value(values, "SECURITY_REQUIRE_SSO", "false"), False),
        "security_require_promotion_gate": as_bool(read_value(values, "SECURITY_REQUIRE_PROMOTION_GATE", "false"), False),
        "security_require_ordered_execution": as_bool(read_value(values, "SECURITY_REQUIRE_ORDERED_EXECUTION", "true"), True),
        "operations_security_mode_default": read_value(values, "OPERATIONS_SECURITY_MODE_DEFAULT", "secure"),
        "mariadb_bind_address": read_value(values, "DATABASE_BIND_ADDRESS", "0.0.0.0"),
        "mariadb_port": as_int(read_value(values, "DATABASE_PORT", "3306"), 3306),
        "mariadb_version_packages": as_list(read_value(values, "DATABASE_PACKAGES", ""), DEFAULT_DATABASE_PACKAGES),
        "mariadb_innodb_buffer_pool_size": profile_value(values, active_profile_name, "MARIADB_INNODB_BUFFER_POOL_SIZE", "2G"),
        "mariadb_max_connections": as_int(profile_value(values, active_profile_name, "MARIADB_MAX_CONNECTIONS", "80"), 80),
        "mariadb_tmp_table_size": profile_value(values, active_profile_name, "MARIADB_TMP_TABLE_SIZE", "128M"),
        "mariadb_max_heap_table_size": profile_value(values, active_profile_name, "MARIADB_MAX_HEAP_TABLE_SIZE", "128M"),
        "mariadb_slow_query_log": as_int(profile_value(values, active_profile_name, "MARIADB_SLOW_QUERY_LOG", "1"), 1),
        "mariadb_long_query_time": as_int(profile_value(values, active_profile_name, "MARIADB_LONG_QUERY_TIME", "2"), 2),
        "timezone_name": require_value(values, "OPERATIONS_TIMEZONE"),
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


def build_inventory(values: dict, execution_mode: str, host_role: str) -> dict:
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
                "ansible_user": require_value(values, "NETWORK_SSH_USER"),
                "ansible_ssh_private_key_file": os.path.expanduser(require_value(values, "NETWORK_SSH_PRIVATE_KEY_PATH")),
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
        fail("python3-yaml support is required. Install the Ubuntu package python3-yaml.")

    execution_mode, host_role = resolve_execution_contract(values)
    ensure_required_keys(values, execution_mode)
    validate_feature_contract(values, execution_mode)

    result = build_public_runtime(values, execution_mode, host_role) if args.mode == "public-runtime" else build_inventory(values, execution_mode, host_role)
    yaml.safe_dump(result, sys.stdout, sort_keys=False, default_flow_style=False)


if __name__ == "__main__":
    main()
