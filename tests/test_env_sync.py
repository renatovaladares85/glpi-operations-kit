import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "env-sync.py"

BASE_SOURCE = """# Application
APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""

BASE_RULES = """version: 1

defaults:
  add_missing: true
  remove_extra: false
  backup: true
  default_mode: report
  apply_managed_changes: false
  backup_dir: ".env-backups"

keys:
  APP_NAME:
    description: "App name"
    required: true
    policy: managed
    auto_apply: true
    default: "Application"

  APP_ENV:
    description: "Environment"
    required: true
    policy: protected
    allowed_values:
      - development
      - staging
      - production

  APP_DEBUG:
    description: "Debug flag"
    required: true
    policy: managed
    auto_apply: true
    allowed_values:
      - "true"
      - "false"

  APP_URL:
    description: "App url"
    required: true
    policy: protected

  DB_PASSWORD:
    description: "Database password"
    required: true
    policy: protected
    secret: true

  QUEUE_CONNECTION:
    description: "Queue connection"
    required: true
    policy: review_required
    default: database
    allowed_values:
      - sync
      - database
      - redis
    reason: "Can require worker/table/redis"
    impact: "Jobs can fail"
    validation:
      - "Verify worker"
      - "Verify jobs table"

  LOG_LEVEL:
    description: "Log level"
    required: true
    policy: managed
    auto_apply: true
    default: error
    allowed_values:
      - debug
      - info
      - notice
      - warning
      - error
      - critical
      - alert
      - emergency
"""


class EnvSyncCLITest(unittest.TestCase):
    def run_sync(self, source: str, target: str, rules: str, mode: str = "report", extra_args=None):
        extra_args = extra_args or []
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            source_path = tmp_path / ".env.example"
            target_path = tmp_path / "production.env"
            rules_path = tmp_path / ".env.sync.yml"
            source_path.write_text(source, encoding="utf-8")
            target_path.write_text(target, encoding="utf-8")
            rules_path.write_text(rules, encoding="utf-8")

            cmd = [
                sys.executable,
                str(SCRIPT),
                "--source",
                str(source_path),
                "--target",
                str(target_path),
                "--rules",
                str(rules_path),
                "--mode",
                mode,
                "--no-color",
            ]
            cmd.extend(extra_args)
            result = subprocess.run(cmd, capture_output=True, text=True, check=False, cwd=tmp_path)

            backup_files = sorted(
                [path.name for path in (tmp_path / ".env-backups").glob("production.env.backup.*")]
            )

            return {
                "result": result,
                "source": source_path.read_text(encoding="utf-8"),
                "target": target_path.read_text(encoding="utf-8"),
                "rules": rules_path.read_text(encoding="utf-8"),
                "backup_files": backup_files,
            }

    def test_report_does_not_change_target(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=true
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="report")
        self.assertEqual(out["result"].returncode, 2)
        self.assertEqual(out["target"], target)

    def test_apply_creates_backup(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=true
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=sync
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertEqual(out["result"].returncode, 3)
        self.assertIn("APP_DEBUG=false", out["target"])
        self.assertTrue(out["backup_files"])

    def test_protected_key_is_not_changed(self):
        target = """APP_NAME=Application
APP_ENV=staging
APP_DEBUG=false
APP_URL=https://old.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertIn("APP_ENV=staging", out["target"])
        self.assertIn("APP_URL=https://old.example.com", out["target"])
        self.assertIn("PRESERVED / PROTECTED", out["result"].stdout)

    def test_managed_not_changed_without_allow_managed(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=true
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply")
        self.assertEqual(out["result"].returncode, 0)
        self.assertIn("APP_DEBUG=true", out["target"])

    def test_managed_changed_with_allow_managed(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=true
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertEqual(out["result"].returncode, 0)
        self.assertIn("APP_DEBUG=false", out["target"])

    def test_review_required_not_changed_without_force(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=sync
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertEqual(out["result"].returncode, 3)
        self.assertIn("QUEUE_CONNECTION=sync", out["target"])

    def test_review_required_changed_with_force(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=sync
LOG_LEVEL=error
"""
        out = self.run_sync(
            BASE_SOURCE,
            target,
            BASE_RULES,
            mode="apply",
            extra_args=["--allow-managed", "--force-reviewed", "QUEUE_CONNECTION"],
        )
        self.assertEqual(out["result"].returncode, 0)
        self.assertIn("QUEUE_CONNECTION=database", out["target"])

    def test_secret_is_masked_in_report(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="report")
        combined = out["result"].stdout + out["result"].stderr
        self.assertNotIn("real-secret", combined)

    def test_missing_key_is_added_when_allowed(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertIn("# Added by env-sync on", out["target"])
        self.assertIn("LOG_LEVEL=error", out["target"])

    def test_extra_key_is_not_removed(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=true
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
OLD_FEATURE_FLAG=true
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertIn("OLD_FEATURE_FLAG=true", out["target"])

    def test_duplicate_key_becomes_ambiguous(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=true
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        self.assertIn("AMBIGUOUS", out["result"].stdout)
        self.assertIn("APP_DEBUG duplicated in target", out["result"].stdout)

    def test_required_empty_generates_required_missing(self):
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="report")
        self.assertIn("REQUIRED MISSING", out["result"].stdout)
        self.assertIn("APP_URL is missing or empty", out["result"].stdout)

    def test_invalid_allowed_value_generates_validation_error(self):
        target = """APP_NAME=Application
APP_ENV=prod
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="report")
        self.assertEqual(out["result"].returncode, 1)
        self.assertIn("VALIDATION ERRORS", out["result"].stdout)

    def test_key_without_rule_becomes_ambiguous(self):
        source = BASE_SOURCE + "CUSTOM_KEY=value\n"
        target = """APP_NAME=Application
APP_ENV=production
APP_DEBUG=false
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
CUSTOM_KEY=old
"""
        out = self.run_sync(source, target, BASE_RULES, mode="report")
        self.assertIn("CUSTOM_KEY no rule in .env.sync.yml", out["result"].stdout)

    def test_comments_and_blank_lines_are_preserved(self):
        target = """# Header

APP_NAME=Application
APP_ENV=production
APP_DEBUG=true  # keep this comment
APP_URL=https://app.example.com
DB_PASSWORD=real-secret
QUEUE_CONNECTION=database
LOG_LEVEL=error
"""
        out = self.run_sync(BASE_SOURCE, target, BASE_RULES, mode="apply", extra_args=["--allow-managed"])
        updated = out["target"]
        self.assertIn("# Header", updated)
        self.assertIn("APP_DEBUG=false  # keep this comment", updated)
        self.assertIn("\n\nAPP_NAME=Application", updated)

    def test_value_with_equal_sign_is_parsed(self):
        source = "EXAMPLE_DOUBLE=abc=123\n"
        target = "EXAMPLE_DOUBLE=abc=123\n"
        rules = """version: 1
keys:
  EXAMPLE_DOUBLE:
    description: "Example"
    required: true
    policy: managed
    auto_apply: true
"""
        out = self.run_sync(source, target, rules, mode="report")
        self.assertEqual(out["result"].returncode, 0)

    def test_single_quoted_value_is_parsed(self):
        source = "EXAMPLE_SINGLE='abc=123'\n"
        target = "EXAMPLE_SINGLE='abc=123'\n"
        rules = """version: 1
keys:
  EXAMPLE_SINGLE:
    description: "Example"
    required: true
    policy: managed
    auto_apply: true
"""
        out = self.run_sync(source, target, rules, mode="report")
        self.assertEqual(out["result"].returncode, 0)

    def test_double_quoted_value_is_parsed(self):
        source = 'EXAMPLE_DOUBLE="abc=123"\n'
        target = 'EXAMPLE_DOUBLE="abc=123"\n'
        rules = """version: 1
keys:
  EXAMPLE_DOUBLE:
    description: "Example"
    required: true
    policy: managed
    auto_apply: true
"""
        out = self.run_sync(source, target, rules, mode="report")
        self.assertEqual(out["result"].returncode, 0)


class EnvSyncGenerateContractCLITest(unittest.TestCase):
    def run_generate(self, template: str, env_files=None, extra_args=None):
        env_files = env_files or {}
        extra_args = extra_args or []
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            config_dir = tmp_path / "config"
            config_dir.mkdir(parents=True, exist_ok=True)
            template_path = config_dir / ".env.example"
            template_path.write_text(template, encoding="utf-8")

            for env_name, env_content in env_files.items():
                (config_dir / f"{env_name}.env").write_text(env_content, encoding="utf-8")

            cmd = [
                sys.executable,
                str(SCRIPT),
                "--generate-contract",
                "--output",
                ".env.sync.generated.yml",
                "--report-output",
                "docs/env-sync-contract-report.md",
                "--no-color",
            ]
            cmd.extend(extra_args)

            result = subprocess.run(cmd, capture_output=True, text=True, check=False, cwd=tmp_path)
            output_path = tmp_path / ".env.sync.generated.yml"
            publish_path = tmp_path / ".env.sync.yml"
            report_path = tmp_path / "docs" / "env-sync-contract-report.md"

            return {
                "result": result,
                "output_exists": output_path.exists(),
                "output_text": output_path.read_text(encoding="utf-8") if output_path.exists() else "",
                "output_yaml": yaml.safe_load(output_path.read_text(encoding="utf-8")) if output_path.exists() else {},
                "publish_exists": publish_path.exists(),
                "publish_text": publish_path.read_text(encoding="utf-8") if publish_path.exists() else "",
                "report_exists": report_path.exists(),
                "report_text": report_path.read_text(encoding="utf-8") if report_path.exists() else "",
            }

    def test_generate_without_real_env_files(self):
        template = """PRODUCT_NAME=GLPI Kit
#OPTIONAL_FLAG=true
SECRET_TOKEN=
TLS_MODE=none
"""
        out = self.run_generate(template)
        self.assertEqual(out["result"].returncode, 0)
        self.assertTrue(out["output_exists"])
        self.assertTrue(out["report_exists"])
        self.assertIn("Nenhum `config/<ambiente>.env` encontrado.", out["report_text"])
        self.assertIn("PRODUCT_NAME", out["output_yaml"]["keys"])
        self.assertIn("OPTIONAL_FLAG", out["output_yaml"]["keys"])
        self.assertFalse(out["publish_exists"])

    def test_generate_discovers_staging_and_production_env_files(self):
        template = """PRODUCT_NAME=GLPI Kit
TLS_MODE=none
MONITORING_MYSQLD_EXPORTER_PASSWORD=
"""
        out = self.run_generate(
            template,
            env_files={
                "staging": "PRODUCT_NAME=GLPI Kit Staging\nTLS_MODE=self_signed\n",
                "production": "PRODUCT_NAME=GLPI Kit Production\nTLS_MODE=provided\n",
            },
        )
        self.assertEqual(out["result"].returncode, 0)
        self.assertIn("Discovered environments: 2", out["result"].stdout)
        self.assertIn("`config/staging.env`", out["report_text"])
        self.assertIn("`config/production.env`", out["report_text"])

    def test_generate_reports_extra_and_duplicate_keys(self):
        template = """PRODUCT_NAME=GLPI Kit
TLS_MODE=none
"""
        out = self.run_generate(
            template,
            env_files={
                "staging": "PRODUCT_NAME=kit-a\nPRODUCT_NAME=kit-b\nLEGACY_FLAG=true\nTLS_MODE=none\n",
            },
        )
        self.assertEqual(out["result"].returncode, 0)
        self.assertIn("LEGACY_FLAG", out["report_text"])
        self.assertIn("chaves duplicadas", out["report_text"])

    def test_generate_publish_writes_env_sync_yml(self):
        template = """PRODUCT_NAME=GLPI Kit
TLS_MODE=none
"""
        out = self.run_generate(template, extra_args=["--publish"])
        self.assertEqual(out["result"].returncode, 0)
        self.assertTrue(out["publish_exists"])
        self.assertEqual(out["output_text"], out["publish_text"])

    def test_generate_strict_post_checks_fails_on_pending_differences(self):
        template = """PRODUCT_NAME=GLPI Kit
TLS_MODE=none
"""
        out = self.run_generate(
            template,
            env_files={"staging": "PRODUCT_NAME=different-name\nTLS_MODE=none\n"},
            extra_args=["--strict-post-checks"],
        )
        self.assertEqual(out["result"].returncode, 1)
        self.assertIn("Strict post-check failed", out["result"].stderr)


if __name__ == "__main__":
    unittest.main()
