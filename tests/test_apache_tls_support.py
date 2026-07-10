import unittest
import importlib.util
from pathlib import Path

from jinja2 import Environment, StrictUndefined


REPO_ROOT = Path(__file__).resolve().parents[1]
APACHE_TEMPLATE = REPO_ROOT / "ansible/roles/app/templates/apache-glpi.conf.j2"
APP_TASKS = REPO_ROOT / "ansible/roles/app/tasks/main.yml"
BASE_TASKS = REPO_ROOT / "ansible/roles/base/tasks/main.yml"
RENDERER = REPO_ROOT / "scripts/lib/render_product_config.py"
GLPICTL = REPO_ROOT / "scripts/glpictl.sh"


class ApacheTlsSupportTest(unittest.TestCase):
    def render_apache(self, tls_mode: str, platform_family: str = "rhel") -> str:
        template = Environment(
            undefined=StrictUndefined,
            keep_trailing_newline=True,
            autoescape=False,
        ).from_string(APACHE_TEMPLATE.read_text(encoding="utf-8"))
        return template.render(
            platform_family=platform_family,
            web_http_port=80,
            web_https_port=443,
            glpi_tls_mode=tls_mode,
            glpi_domain="glpi.example.internal",
            glpi_app_host="192.0.2.10",
            glpi_install_dir="/usr/share/glpi",
            glpi_php_fpm_socket="/run/php-fpm/glpi.sock",
            glpi_log_dir="/var/log/glpi",
            glpi_tls_certificate_path="/etc/ssl/certs/example.crt",
            glpi_tls_certificate_key_path="/etc/ssl/private/example.key",
        )

    def test_apache_none_renders_http_only(self):
        rendered = self.render_apache("none")
        self.assertIn("<VirtualHost *:80>", rendered)
        self.assertIn("DocumentRoot /usr/share/glpi/public", rendered)
        self.assertNotIn("<VirtualHost *:443>", rendered)
        self.assertNotIn("SSLEngine on", rendered)
        self.assertNotIn("Redirect permanent", rendered)

    def test_apache_self_signed_renders_redirect_and_https(self):
        rendered = self.render_apache("self_signed")
        self.assertIn("Redirect permanent / https://glpi.example.internal/", rendered)
        self.assertIn("<VirtualHost *:443>", rendered)
        self.assertIn("SSLEngine on", rendered)
        self.assertIn("SSLCertificateFile /etc/ssl/certs/example.crt", rendered)
        self.assertIn("SSLCertificateKeyFile /etc/ssl/private/example.key", rendered)
        self.assertEqual(rendered.count("DocumentRoot /usr/share/glpi/public"), 1)

    def test_apache_provided_uses_same_https_contract(self):
        rendered = self.render_apache("provided")
        self.assertIn("<VirtualHost *:443>", rendered)
        self.assertIn('SetHandler "proxy:unix:/run/php-fpm/glpi.sock|fcgi://localhost/"', rendered)
        self.assertIn("HTTP_AUTHORIZATION", rendered)
        self.assertIn("[QSA,L]", rendered)

    def test_debian_apache_does_not_duplicate_default_listen_directives(self):
        rendered = self.render_apache("self_signed", platform_family="debian")
        self.assertNotIn("Listen 443", rendered)
        self.assertIn("<VirtualHost *:443>", rendered)

    def test_rocky_apache_tls_listens_on_https_port(self):
        rendered = self.render_apache("self_signed", platform_family="rhel")
        self.assertIn("Listen 443 https", rendered)

    def test_rocky_mod_ssl_is_conditional_and_manual_override_is_checked(self):
        renderer = RENDERER.read_text(encoding="utf-8")
        self.assertIn('web_server_type == "apache" and tls_mode != "none"', renderer)
        self.assertIn('app_packages.append("mod_ssl")', renderer)
        self.assertIn('required_web_packages.append("mod_ssl")', renderer)
        self.assertIn("GLPI_APP_PACKAGES is missing mandatory packages", renderer)

    def test_san_dns_validation_rejects_ip_addresses(self):
        spec = importlib.util.spec_from_file_location("render_product_config_tls", RENDERER)
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        self.assertTrue(renderer.is_dns_name("glpi.example.internal"))
        self.assertFalse(renderer.is_dns_name("192.0.2.10"))
        self.assertFalse(renderer.is_dns_name("2001:db8::10"))

    def test_debian_ssl_module_is_enabled_only_for_tls(self):
        tasks = APP_TASKS.read_text(encoding="utf-8")
        self.assertIn("a2enmod rewrite proxy proxy_fcgi setenvif{% if glpi_tls_mode != 'none' %} ssl{% endif %}", tasks)

    def test_self_signed_certificate_has_san_eku_and_content_idempotency(self):
        tasks = APP_TASKS.read_text(encoding="utf-8")
        self.assertIn('-addext "subjectAltName=${san_ext}"', tasks)
        self.assertIn('-addext "extendedKeyUsage=serverAuth"', tasks)
        self.assertIn("CERTIFICATE_UNCHANGED", tasks)
        self.assertIn("CERTIFICATE_GENERATED", tasks)
        self.assertIn("actual_csv", tasks)
        self.assertIn("cert_pub", tasks)
        self.assertNotIn('creates: "{{ glpi_tls_certificate_path }}"', tasks)

    def test_certificate_regeneration_creates_backups_and_permissions(self):
        tasks = APP_TASKS.read_text(encoding="utf-8")
        self.assertIn('cp -a "$cert" "${cert}.bak.${timestamp}"', tasks)
        self.assertIn('cp -a "$key" "${key}.bak.${timestamp}"', tasks)
        self.assertIn('install -o root -g root -m 0644', tasks)
        self.assertIn('install -o root -g root -m 0600', tasks)

    def test_rocky_default_ssl_vhost_is_backed_up_and_disabled(self):
        tasks = APP_TASKS.read_text(encoding="utf-8")
        self.assertIn("Back up Rocky default SSL virtual host", tasks)
        self.assertIn('dest: "{{ glpi_apache_ssl_default_conf_path }}.glpi-disabled"', tasks)
        self.assertIn("Disable Rocky default SSL virtual host", tasks)

    def test_tls_common_name_precedence_is_preserved_by_cli(self):
        script = GLPICTL.read_text(encoding="utf-8")
        section = script[
            script.index("execute_tls_legacy_apply()") : script.index("run_tls_web_server_postcheck()")
        ]
        self.assertIn('read_effective_runtime_value "glpi_tls_common_name"', section)
        self.assertIn('read_product_config_value "$ENVIRONMENT" "tls.common_name"', section)
        self.assertIn('tls_common_name="$domain"', section)
        self.assertIn('"glpi_tls_common_name" "$tls_common_name"', section)
        self.assertNotIn('"glpi_tls_common_name" "$domain"', section)

    def test_remote_snapshot_includes_runtime_certificate_and_key(self):
        script = GLPICTL.read_text(encoding="utf-8")
        section = script[
            script.index("create_remote_domain_backup_snapshot()") : script.index(
                "restore_remote_domain_backup_snapshot()"
            )
        ]
        self.assertIn('read_effective_runtime_value "glpi_tls_certificate_path"', section)
        self.assertIn('read_effective_runtime_value "glpi_tls_certificate_key_path"', section)
        self.assertIn('shell_escape_single_quotes "$glpi_tls_certificate_path"', section)
        self.assertIn('shell_escape_single_quotes "$glpi_tls_certificate_key_path"', section)

    def test_https_firewall_is_conditional_and_uses_env_ports(self):
        tasks = BASE_TASKS.read_text(encoding="utf-8")
        self.assertIn("web_http_port | default(80)", tasks)
        self.assertIn("web_https_port | default(443)", tasks)
        self.assertGreaterEqual(tasks.count("glpi_tls_mode | default('none') != 'none'"), 2)


if __name__ == "__main__":
    unittest.main()
