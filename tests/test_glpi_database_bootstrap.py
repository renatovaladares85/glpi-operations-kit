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
        self.assertIn("Use DATABASE_COMPATIBILITY_POLICY=warn|defer only through glpictl confirmation", app_tasks)
        self.assertIn("not (database_compatibility_schema_bootstrap_deferred_effective | bool)", app_tasks)
        self.assertIn("GLPI_DEFER_SCHEMA_BOOTSTRAP", app_tasks)
        self.assertIn("GLPI cache console configuration deferred because DB schema bootstrap is deferred.", redis_script)


if __name__ == "__main__":
    unittest.main()
