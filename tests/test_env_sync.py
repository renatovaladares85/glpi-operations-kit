import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()
