import unittest
import importlib.util
import subprocess
import tempfile
from pathlib import Path

from jinja2 import Environment, StrictUndefined


REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_DB_TEMPLATE = REPO_ROOT / "ansible" / "roles" / "app" / "templates" / "config_db.php.j2"
PHP_FILTER = REPO_ROOT / "ansible" / "filter_plugins" / "php_string.py"


class GlpiDatabaseBootstrapTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location("php_string", PHP_FILTER)
        cls.php_filter = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.php_filter)

    def render_config_db(self, password):
        environment = Environment(undefined=StrictUndefined, autoescape=False)
        environment.filters["php_single_quoted_string"] = (
            self.php_filter.php_single_quoted_string
        )
        environment.filters["php_rawurlencoded_single_quoted_string"] = (
            self.php_filter.php_rawurlencoded_single_quoted_string
        )
        environment.filters["bool"] = bool
        template = environment.from_string(CONFIG_DB_TEMPLATE.read_text(encoding="utf-8"))
        return template.render(
            glpi_db_host="192.0.2.20",
            mariadb_port=3306,
            glpi_db_user="example_user",
            glpi_db_password=password,
            glpi_db_name="example_database",
            glpi_timezone_support_enabled=True,
        )

    def test_app_role_deploys_database_config_without_logging_secret(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )
        template = (
            REPO_ROOT / "ansible" / "roles" / "app" / "templates" / "config_db.php.j2"
        ).read_text(encoding="utf-8")

        self.assertIn("src: config_db.php.j2", app_tasks)
        self.assertIn('dest: "{{ glpi_config_dir }}/config_db.php"', app_tasks)
        self.assertIn("no_log: true", app_tasks)
        self.assertIn("when: glpi_installation_mode_effective != 'wizard'", app_tasks)
        self.assertIn("class DB extends DBmysql", template)
        self.assertIn("public $dbhost", template)
        self.assertIn(
            "public $dbpassword = {{ glpi_db_password | php_rawurlencoded_single_quoted_string }};",
            template,
        )
        self.assertNotIn("glpi_db_password | urlencode", template)
        self.assertNotIn("?>", template)

    def test_php_single_quoted_filter_preserves_supported_characters(self):
        values = [
            "ExamplePassword123",
            "Abc@123#Test%+/: value;=!?$&*()[]{}-_.,",
            "A'b\\c@123",
            'Dollar$ double" backtick` braces{}',
        ]

        for original in values:
            with self.subTest(original=original):
                literal = self.php_filter.php_rawurlencoded_single_quoted_string(original)
                self.assertTrue(literal.startswith("'") and literal.endswith("'"))
                if "@" in original:
                    self.assertIn("%40", literal)
                if "#" in original:
                    self.assertIn("%23", literal)

    def test_rendered_config_db_is_valid_php_and_round_trips_password(self):
        passwords = [
            "ExamplePassword123",
            "Abc@123#Test%+/: value",
            "A'b\\c@123",
            'Dollar$ double" backtick` braces{}',
        ]

        for original in passwords:
            with self.subTest(case=passwords.index(original)):
                rendered = self.render_config_db(original)
                with tempfile.TemporaryDirectory() as tmpdir:
                    config_path = Path(tmpdir) / "config_db.php"
                    config_path.write_text(rendered, encoding="utf-8")

                    lint = subprocess.run(
                        ["php", "-l", str(config_path)],
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(lint.returncode, 0, lint.stderr)

                    php_code = """
class DBmysql {}
require $argv[1];
$config = new DB();
exit(hash_equals($argv[2], rawurldecode($config->dbpassword)) ? 0 : 1);
"""
                    round_trip = subprocess.run(
                        ["php", "-r", php_code, str(config_path), original],
                        text=True,
                        capture_output=True,
                        check=False,
                    )
                    self.assertEqual(round_trip.returncode, 0, round_trip.stderr)
                    self.assertEqual(round_trip.stdout, "")

    def test_database_secret_is_not_added_to_public_runtime_or_logs(self):
        renderer = (REPO_ROOT / "scripts" / "lib" / "render_product_config.py").read_text(
            encoding="utf-8"
        )
        public_runtime = renderer[
            renderer.index("def build_public_runtime") : renderer.index("def build_inventory")
        ]
        glpictl = (REPO_ROOT / "scripts" / "glpictl.sh").read_text(encoding="utf-8")

        self.assertNotIn('"glpi_db_password"', public_runtime)
        self.assertIn("mask_sensitive_stream", glpictl)
        self.assertIn("DATABASE_PASSWORD=", glpictl)

    def test_app_role_checks_db_compatibility_and_schema_before_redis_and_http(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )

        version_check_pos = app_tasks.index("Check GLPI database server version")
        schema_marker_pos = app_tasks.index("Check GLPI database schema marker")
        schema_install_pos = app_tasks.index("Install GLPI database schema when absent")
        redis_pos = app_tasks.index("Configure GLPI Redis cache and PHP-FPM sessions")
        http_check_pos = app_tasks.index("Check GLPI root endpoint for selected engine")

        self.assertLess(version_check_pos, schema_marker_pos)
        self.assertLess(schema_marker_pos, schema_install_pos)
        self.assertLess(schema_install_pos, redis_pos)
        self.assertLess(redis_pos, http_check_pos)
        self.assertIn("--execute=SELECT VERSION(), @@version_comment;", app_tasks)
        self.assertIn("MariaDB >= 10.6 or MySQL >= 8.0 for GLPI 11", app_tasks)
        self.assertIn("SHOW TABLES LIKE 'glpi_configs';", app_tasks)
        self.assertIn("db:install", app_tasks)
        self.assertIn("--no-interaction", app_tasks)
        self.assertIn("--no-telemetry", app_tasks)
        self.assertNotIn("--force", app_tasks)

    def test_incompatible_database_cannot_defer_schema_bootstrap(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("database_compatibility_operator_confirmed_effective", app_tasks)
        self.assertIn("database_compatibility_schema_bootstrap_deferred_effective", app_tasks)
        self.assertIn("glpi_schema_bootstrap_deferred_effective", app_tasks)
        self.assertIn("database_compatibility_schema_bootstrap_deferred_effective: false", app_tasks)
        self.assertIn("glpi_db_server_version_supported | bool", app_tasks)
        self.assertNotIn("accepted under DATABASE_COMPATIBILITY_POLICY", app_tasks)

    def test_wizard_mode_skips_config_db_and_schema_bootstrap(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("glpi_installation_mode_effective in ['cli', 'wizard']", app_tasks)
        self.assertIn("when: glpi_installation_mode_effective != 'wizard'", app_tasks)
        self.assertIn("not (glpi_schema_bootstrap_deferred_effective | bool)", app_tasks)
        self.assertIn('GLPI_DEFER_SCHEMA_BOOTSTRAP: "{{ glpi_schema_bootstrap_deferred_effective | string | lower }}"', app_tasks)
        self.assertIn("SHOW TABLES LIKE 'glpi_configs';", app_tasks)
        self.assertIn("db:install", app_tasks)

    def test_wizard_mode_detects_existing_config_db_and_backs_up_only_when_allowed(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("Check existing GLPI database configuration for wizard mode", app_tasks)
        self.assertIn("Refuse wizard mode with existing database config unless reset is explicit", app_tasks)
        self.assertIn("GLPI_WIZARD_RESET_CONFIG_DB=true is refused in production-like stages", app_tasks)
        self.assertIn("Assert wizard config reset only targets empty GLPI schema", app_tasks)
        self.assertIn("Move existing GLPI database config aside for wizard mode", app_tasks)
        self.assertIn("config_db.php.bak.{{ ansible_date_time.iso8601_basic_short }}", app_tasks)
        self.assertIn("config_db.php exists while schema is missing", app_tasks)

    def test_wizard_mode_has_dedicated_smoke_check_and_rejects_http_500(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("Check GLPI wizard root endpoint", app_tasks)
        self.assertIn("Check GLPI wizard installer endpoint", app_tasks)
        self.assertIn("status_code: [200, 301, 302, 303, 500]", app_tasks)
        self.assertIn("status_code: [200, 301, 302, 303, 404, 500]", app_tasks)
        self.assertIn("Assert GLPI wizard is reachable without server error", app_tasks)
        self.assertIn("!= 500", app_tasks)
        self.assertIn("glpi_wizard_ready: true", app_tasks)
        self.assertIn("glpi_schema_ready: false", app_tasks)
        self.assertIn("glpi_user_ready: false", app_tasks)


if __name__ == "__main__":
    unittest.main()
