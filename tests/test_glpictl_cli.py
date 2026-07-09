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

    def test_managed_db_compatibility_policy_requires_explicit_acceptance(self):
        script = GLPICTL.read_text(encoding="utf-8")
        gate = script[
            script.index("enforce_managed_db_version_compatibility_gate()") : script.index(
                "effective_managed_timezone_db_mode()"
            )
        ]

        self.assertIn('MANAGED_DB_COMPATIBILITY_POLICY" != "warn"', gate)
        self.assertIn("DATABASE_COMPATIBILITY_JUSTIFICATION", gate)
        self.assertIn('SECURITY_MODE_EFFECTIVE" != "permissive"', gate)
        self.assertIn("environment_stage_is_production", gate)
        self.assertIn("DATABASE_UNSUPPORTED_PROD_OVERRIDE", gate)
        self.assertIn("DATABASE_COMPATIBILITY_ASSUME_YES", gate)
        self.assertIn("prompt_yes_no", gate)
        self.assertIn('DB_COMPATIBILITY_OPERATOR_CONFIRMED="true"', gate)
        self.assertIn('DB_COMPATIBILITY_SCHEMA_BOOTSTRAP_DEFERRED="true"', gate)
        self.assertIn('EXECUTION_SUCCESS_STATUS_LABEL="SUCCESS_WITH_WARNINGS"', gate)

    def test_database_compatibility_evidence_does_not_write_passwords(self):
        script = GLPICTL.read_text(encoding="utf-8")
        evidence_section = script[
            script.index("write_database_compatibility_evidence()") : script.index(
                "enforce_managed_db_version_compatibility_gate()"
            )
        ]

        self.assertIn("database_compatibility_status", evidence_section)
        self.assertIn("database_version_detected", evidence_section)
        self.assertIn("database_compatibility_justification", evidence_section)
        self.assertNotIn("PASSWORD", evidence_section)
        self.assertNotIn("MANAGED_DB_PASSWORD", evidence_section)

    def test_ansible_failure_summary_is_reported(self):
        script = GLPICTL.read_text(encoding="utf-8")

        self.assertIn("record_ansible_failure_summary", script)
        self.assertIn("Ansible failure summary:", script)
        self.assertIn("failure_task:", script)
        self.assertIn("recommended_action:", script)


if __name__ == "__main__":
    unittest.main()
