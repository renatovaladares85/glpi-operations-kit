import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class GlpiDatabaseBootstrapTest(unittest.TestCase):
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
        self.assertIn("public $dbpassword = '{{ glpi_db_password | urlencode }}';", template)
        self.assertNotIn("?>", template)

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

    def test_defer_policy_skips_schema_bootstrap_and_web_smoke_checks(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )
        redis_script = (
            REPO_ROOT / "ansible" / "roles" / "app" / "files" / "glpi-redis-integration.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("database_compatibility_policy_effective", app_tasks)
        self.assertIn("database_compatibility_operator_confirmed_effective", app_tasks)
        self.assertIn("database_compatibility_schema_bootstrap_deferred_effective", app_tasks)
        self.assertIn("glpi_schema_bootstrap_deferred_effective", app_tasks)
        self.assertIn("Use DATABASE_COMPATIBILITY_POLICY=warn|defer only through glpictl confirmation", app_tasks)
        self.assertIn("not (glpi_schema_bootstrap_deferred_effective | bool)", app_tasks)
        self.assertIn("GLPI_DEFER_SCHEMA_BOOTSTRAP", app_tasks)
        self.assertIn("GLPI cache console configuration deferred because DB schema bootstrap is deferred.", redis_script)

    def test_wizard_mode_skips_config_db_and_schema_bootstrap(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("glpi_installation_mode_effective in ['cli', 'wizard', 'defer']", app_tasks)
        self.assertIn("when: glpi_installation_mode_effective != 'wizard'", app_tasks)
        self.assertIn("glpi_installation_mode_effective in ['wizard', 'defer']", app_tasks)
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
