import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GLPICTL = REPO_ROOT / "scripts" / "glpictl.sh"


class GlpiCtlCliTest(unittest.TestCase):
    def test_execution_summary_uses_selected_web_engine_configtest(self):
        script = GLPICTL.read_text(encoding="utf-8")

        build_commands = script[
            script.index("build_execution_test_commands()") : script.index(
                "resolve_execution_access_context()"
            )
        ]

        self.assertIn('web_server_type="$(read_effective_runtime_value "glpi_web_server_type" "nginx")"', build_commands)
        self.assertIn('web_config_test_command="sudo apachectl configtest"', build_commands)
        self.assertIn('web_config_test_command="sudo nginx -t"', build_commands)
        self.assertIn('web_config_test_command="sudo lighttpd -tt -f /etc/lighttpd/lighttpd.conf"', build_commands)
        self.assertNotIn('EXECUTION_TEST_COMMANDS+=("sudo nginx -t")', build_commands)

    def test_managed_db_version_gate_runs_before_apply_ansible(self):
        script = GLPICTL.read_text(encoding="utf-8")
        apply_section = script[
            script.index("case \"$mode\" in\n    apply)") : script.index("    post-check)")
        ]

        self.assertIn("enforce_managed_db_version_compatibility_gate", apply_section)
        self.assertLess(
            apply_section.index("enforce_managed_db_version_compatibility_gate"),
            apply_section.index("invoke_ansible_or_fail"),
        )

    def test_ansible_failure_summary_is_reported(self):
        script = GLPICTL.read_text(encoding="utf-8")

        self.assertIn("record_ansible_failure_summary", script)
        self.assertIn("Ansible failure summary:", script)
        self.assertIn("failure_task:", script)
        self.assertIn("recommended_action:", script)


if __name__ == "__main__":
    unittest.main()
