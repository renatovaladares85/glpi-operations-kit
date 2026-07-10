import unittest
import importlib.util
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]
BASE_TASKS_PATH = REPO_ROOT / "ansible" / "roles" / "base" / "tasks" / "main.yml"
BASE_DEFAULTS_PATH = REPO_ROOT / "ansible" / "roles" / "base" / "defaults" / "main.yml"


class AnsibleRockySupportTest(unittest.TestCase):
    def test_chrony_service_is_mapped_by_platform_family(self):
        defaults = yaml.safe_load(BASE_DEFAULTS_PATH.read_text(encoding="utf-8"))

        self.assertEqual(
            defaults["base_chrony_service_by_family"],
            {"debian": "chrony", "rhel": "chronyd"},
        )

    def test_rhel_keeps_chrony_package_and_uses_chronyd_service(self):
        tasks = yaml.safe_load(BASE_TASKS_PATH.read_text(encoding="utf-8"))
        package_task = next(
            task for task in tasks if task["name"] == "Install base operating system packages"
        )
        service_task = next(
            task for task in tasks if task["name"] == "Ensure chrony service is enabled"
        )

        self.assertIn("chrony", package_task["vars"]["base_os_packages_by_family"]["rhel"])
        self.assertEqual(
            service_task["ansible.builtin.service"]["name"],
            "{{ base_chrony_service_by_family[platform_family] }}",
        )
        self.assertNotEqual(service_task["ansible.builtin.service"]["name"], "chrony")

    def test_base_role_rejects_unknown_platform_family_clearly(self):
        tasks = yaml.safe_load(BASE_TASKS_PATH.read_text(encoding="utf-8"))
        validation = tasks[0]["ansible.builtin.assert"]

        self.assertIn("platform_family is defined", validation["that"])
        self.assertIn("platform_family in base_chrony_service_by_family", validation["that"])
        self.assertIn("Unsupported platform_family", validation["fail_msg"])

    def test_base_firewall_uses_configured_ports_and_platform_tools(self):
        tasks = BASE_TASKS_PATH.read_text(encoding="utf-8")
        rocky_8443 = tasks.replace("{{ web_https_port | default(443) }}", "8443")

        self.assertIn("ufw allow {{ web_http_port | default(80) }}/tcp", tasks)
        self.assertIn("ufw allow {{ web_https_port | default(443) }}/tcp", tasks)
        self.assertIn("firewall-cmd --permanent --add-port={{ web_http_port | default(80) }}/tcp", tasks)
        self.assertIn("firewall-cmd --permanent --add-port={{ web_https_port | default(443) }}/tcp", tasks)
        self.assertIn("firewall-cmd --permanent --remove-port={{ web_https_port | default(443) }}/tcp", tasks)
        self.assertIn("firewall-cmd --permanent --add-port=8443/tcp", rocky_8443)
        self.assertIn("firewall-cmd --permanent --remove-port=8443/tcp", rocky_8443)
        self.assertGreaterEqual(tasks.count("glpi_tls_mode | default('none') != 'none'"), 2)
        self.assertGreaterEqual(tasks.count("glpi_tls_mode | default('none') == 'none'"), 2)
        self.assertIn("name: firewalld", tasks)
        self.assertIn("ufw --force enable", tasks)
        self.assertIn("firewall-cmd --reload", tasks)
        self.assertNotIn("--add-service=http\n", tasks)
        self.assertNotIn("--add-service=https", tasks)

    def test_site_uses_dynamic_role_includes_for_tagged_runs(self):
        site = yaml.safe_load((REPO_ROOT / "ansible" / "site.yml").read_text(encoding="utf-8"))

        self.assertTrue(site)
        self.assertTrue(all("roles" not in play for play in site))
        include_role_names = []
        for play in site:
            for task in play.get("tasks", []):
                include_role = task.get("ansible.builtin.include_role")
                if include_role:
                    include_role_names.append(include_role.get("name"))

        self.assertEqual(
            include_role_names,
            ["base", "app", "db", "monitoring", "backup", "email"],
        )

    def test_community_general_is_not_required_by_playbooks(self):
        ansible_files = [
            path
            for path in (REPO_ROOT / "ansible").rglob("*")
            if path.is_file() and path.suffix in {".yml", ".j2"}
        ]
        combined = "\n".join(path.read_text(encoding="utf-8") for path in ansible_files)

        self.assertNotIn("community.general.", combined)
        self.assertNotIn("community.general", (REPO_ROOT / "ansible" / "requirements.yml").read_text(encoding="utf-8"))

    def test_apache_app_role_has_rhel_specific_configuration_path(self):
        renderer = (REPO_ROOT / "scripts" / "lib" / "render_product_config.py").read_text(encoding="utf-8")
        app_tasks = (REPO_ROOT / "ansible" / "roles" / "app" / "tasks" / "main.yml").read_text(encoding="utf-8")
        apache_template = (
            REPO_ROOT / "ansible" / "roles" / "app" / "templates" / "apache-glpi.conf.j2"
        ).read_text(encoding="utf-8")

        self.assertIn('"apache_conf_path": "/etc/httpd/conf.d/glpi.conf"', renderer)
        self.assertIn('"apache_default_conf_path": "/etc/httpd/conf.d/welcome.conf"', renderer)
        self.assertIn('dest: "{{ glpi_apache_conf_path }}"', app_tasks)
        self.assertIn("platform_family | default('debian') == 'rhel'", app_tasks)
        self.assertIn('SetHandler "proxy:unix:{{ glpi_php_fpm_socket }}|fcgi://localhost/"', apache_template)

    def test_rhel_app_defaults_use_mysql_client_package(self):
        renderer_path = REPO_ROOT / "scripts" / "lib" / "render_product_config.py"
        spec = importlib.util.spec_from_file_location("render_product_config", renderer_path)
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)

        self.assertIn("mysql", renderer.DEFAULT_GLPI_APP_PACKAGES_RHEL)
        self.assertNotIn("mariadb", renderer.DEFAULT_GLPI_APP_PACKAGES_RHEL)

    def test_renderer_exposes_database_compatibility_contract(self):
        renderer_path = REPO_ROOT / "scripts" / "lib" / "render_product_config.py"
        spec = importlib.util.spec_from_file_location("render_product_config", renderer_path)
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)

        self.assertEqual(
            renderer.DOTTED_KEY_MAP["database.compatibility_policy"],
            "DATABASE_COMPATIBILITY_POLICY",
        )
        self.assertEqual(
            renderer.DOTTED_KEY_MAP["database.compatibility_justification"],
            "DATABASE_COMPATIBILITY_JUSTIFICATION",
        )
        self.assertEqual(
            renderer.DOTTED_KEY_MAP["database.compatibility_assume_yes"],
            "DATABASE_COMPATIBILITY_ASSUME_YES",
        )
        self.assertEqual(
            renderer.DOTTED_KEY_MAP["glpi.installation_mode"],
            "GLPI_INSTALLATION_MODE",
        )
        self.assertEqual(
            renderer.DOTTED_KEY_MAP["glpi.wizard_reset_config_db"],
            "GLPI_WIZARD_RESET_CONFIG_DB",
        )
        self.assertEqual(renderer.GLPI_INSTALLATION_MODES, {"auto", "cli", "wizard"})

    def test_installation_mode_auto_is_deterministic(self):
        renderer_path = REPO_ROOT / "scripts" / "lib" / "render_product_config.py"
        spec = importlib.util.spec_from_file_location("render_product_config_modes", renderer_path)
        renderer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(renderer)
        complete = {
            "TOPOLOGY_DB_HOST": "192.0.2.20",
            "DATABASE_PORT": "3306",
            "DATABASE_NAME": "example_database",
            "DATABASE_USER": "example_user",
            "DATABASE_PASSWORD": "fictional-secret",
        }

        self.assertEqual(renderer.resolve_glpi_installation_mode(complete), "cli")
        self.assertEqual(
            renderer.resolve_glpi_installation_mode({"GLPI_INSTALLATION_MODE": "auto"}),
            "wizard",
        )
        self.assertEqual(
            renderer.resolve_glpi_installation_mode({"GLPI_INSTALLATION_MODE": "wizard"}),
            "wizard",
        )
        with self.assertRaises(SystemExit):
            renderer.resolve_glpi_installation_mode(
                {"TOPOLOGY_DB_HOST": "192.0.2.20", "DATABASE_NAME": "example_database"}
            )
        with self.assertRaises(SystemExit):
            renderer.resolve_glpi_installation_mode(
                {"GLPI_INSTALLATION_MODE": "cli", "TOPOLOGY_DB_HOST": "192.0.2.20"}
            )


if __name__ == "__main__":
    unittest.main()
