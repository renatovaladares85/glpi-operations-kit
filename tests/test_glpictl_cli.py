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

    def test_web_engine_postcheck_uses_rendered_service_and_selected_configtest(self):
        script = GLPICTL.read_text(encoding="utf-8")
        service_function = script[
            script.index("web_engine_expected_service()") : script.index(
                "web_engine_configtest_command()"
            )
        ]
        configtest_function = script[
            script.index("web_engine_configtest_command()") : script.index(
                "web_engine_error_log_path()"
            )
        ]

        self.assertIn('read_effective_runtime_value "glpi_web_service"', service_function)
        self.assertIn('echo "httpd"', service_function)
        self.assertIn('echo "apache2"', service_function)
        self.assertIn('apache) echo "apachectl configtest"', configtest_function)
        self.assertIn('nginx) echo "nginx -t"', configtest_function)
        self.assertIn('lighttpd) echo "lighttpd -tt -f /etc/lighttpd/lighttpd.conf"', configtest_function)

    def test_web_engine_runtime_ready_fails_when_service_or_listener_is_missing(self):
        script = GLPICTL.read_text(encoding="utf-8")
        runtime_ready = script[
            script.index("enforce_selected_web_engine_runtime_ready()") : script.index(
                "enforce_local_target_consistency()"
            )
        ]

        self.assertIn('if [[ "$expected_service_status" != "active" ]]', runtime_ready)
        self.assertIn("not active", runtime_ready)
        self.assertIn('if ! web_engine_all_listeners_detected "$expected_ports"', runtime_ready)
        self.assertIn("no listener was detected", runtime_ready)
        self.assertIn("web_engine_local_connectivity_detected", runtime_ready)
        self.assertIn("set_failure_context", runtime_ready)
        self.assertIn("return 1", runtime_ready)
        self.assertNotIn("record_execution_warning", runtime_ready)

    def test_post_check_and_apply_enforce_web_engine_runtime_readiness(self):
        script = GLPICTL.read_text(encoding="utf-8")
        apply_section = script[
            script.index("case \"$mode\" in\n    apply)") : script.index("    post-check)")
        ]
        post_check_start = script.index("    post-check)", script.index("case \"$mode\" in\n    apply)"))
        post_check_section = script[
            post_check_start : script.index("    *)\n      echo \"Unsupported deploy action", post_check_start)
        ]

        self.assertIn("enforce_selected_web_engine_runtime_ready", apply_section)
        self.assertLess(
            apply_section.index("invoke_ansible_or_fail"),
            apply_section.index("enforce_selected_web_engine_runtime_ready"),
        )
        self.assertIn("enforce_selected_web_engine_runtime_ready", post_check_section)
        self.assertLess(
            post_check_section.index("invoke_ansible_or_fail"),
            post_check_section.index("enforce_selected_web_engine_runtime_ready"),
        )

    def test_web_engine_summary_reports_actionable_runtime_fields(self):
        script = GLPICTL.read_text(encoding="utf-8")
        summary_function = script[
            script.index("print_web_engine_postcheck_summary()") : script.index(
                "print_web_engine_failure_diagnostics()"
            )
        ]

        for field in (
            "selected_engine:",
            "expected_service:",
            "service_status:",
            "expected_ports:",
            "listener_detected:",
            "suggested_diagnostic_command:",
        ):
            self.assertIn(field, summary_function)

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
