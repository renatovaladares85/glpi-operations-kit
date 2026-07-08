import unittest
from pathlib import Path

import yaml


REPO_ROOT = Path(__file__).resolve().parents[1]


class AnsibleRockySupportTest(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
