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

    def test_app_role_bootstraps_schema_before_http_smoke_without_force(self):
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(
            encoding="utf-8"
        )

        schema_marker_pos = app_tasks.index("Check GLPI database schema marker")
        schema_install_pos = app_tasks.index("Install GLPI database schema when absent")
        http_check_pos = app_tasks.index("Check GLPI root endpoint for selected engine")

        self.assertLess(schema_marker_pos, schema_install_pos)
        self.assertLess(schema_install_pos, http_check_pos)
        self.assertIn("SHOW TABLES LIKE 'glpi_configs';", app_tasks)
        self.assertIn("db:install", app_tasks)
        self.assertIn("--no-interaction", app_tasks)
        self.assertIn("--no-telemetry", app_tasks)
        self.assertNotIn("--force", app_tasks)


if __name__ == "__main__":
    unittest.main()
