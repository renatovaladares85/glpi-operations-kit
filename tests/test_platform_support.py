import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMON_SH = REPO_ROOT / "scripts" / "lib" / "common.sh"


class PlatformSupportTest(unittest.TestCase):
    def run_common(self, os_release: str, body: str) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as tmp:
            os_release_path = Path(tmp) / "os-release"
            os_release_path.write_text(os_release, encoding="utf-8")
            script = f"""
set -euo pipefail
export GLPI_OS_RELEASE_FILE={shlex.quote(str(os_release_path))}
source {shlex.quote(str(COMMON_SH))}
{body}
"""
            return subprocess.run(
                ["bash", "-lc", script],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

    def test_ubuntu_2404_is_supported_with_apt_packages(self):
        result = self.run_common(
            'ID=ubuntu\nVERSION_ID="24.04"\nID_LIKE=debian\n',
            """
platform_supported
printf 'family=%s\\n' "$(platform_family)"
printf 'ssh=%s\\n' "$(package_for_command ssh)"
printf 'yaml=%s\\n' "$(package_for_python_yaml)"
""",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("family=debian", result.stdout)
        self.assertIn("ssh=openssh-client", result.stdout)
        self.assertIn("yaml=python3-yaml", result.stdout)

    def test_rocky_9_is_supported_with_dnf_packages(self):
        result = self.run_common(
            'ID=rocky\nVERSION_ID="9.4"\nID_LIKE="rhel centos fedora"\n',
            """
platform_supported
printf 'family=%s\\n' "$(platform_family)"
printf 'manager=%s\\n' "$(platform_package_manager)"
printf 'ansible=%s\\n' "$(package_for_command ansible-playbook)"
printf 'ssh=%s\\n' "$(package_for_command ssh)"
printf 'yaml=%s\\n' "$(package_for_python_yaml)"
printf 'mysql=%s\\n' "$(package_for_command mysql)"
""",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("family=rhel", result.stdout)
        self.assertIn("manager=dnf", result.stdout)
        self.assertIn("ansible=ansible-core", result.stdout)
        self.assertIn("ssh=openssh-clients", result.stdout)
        self.assertIn("yaml=python3-PyYAML", result.stdout)
        self.assertIn("mysql=mysql", result.stdout)

    def test_unsupported_platform_fails(self):
        for os_release in (
            'ID=ubuntu\nVERSION_ID="22.04"\nID_LIKE=debian\n',
            'ID=fedora\nVERSION_ID="39"\nID_LIKE=fedora\n',
        ):
            with self.subTest(os_release=os_release):
                result = self.run_common(
                    os_release,
                    """
if platform_supported; then
  echo supported
  exit 1
fi
echo unsupported
""",
                )

                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("unsupported", result.stdout)

    def test_ensure_mode_clears_directory_special_bits(self):
        result = self.run_common(
            'ID=rocky\nVERSION_ID="9.4"\nID_LIKE="rhel centos fedora"\n',
            """
tmp_dir="$(mktemp -d)"
chmod 2700 "$tmp_dir"
printf 'y\\n' | ensure_mode "$tmp_dir" "700"
printf 'mode=%s\\n' "$(stat -c '%a' "$tmp_dir")"
rm -rf "$tmp_dir"
""",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("mode=700", result.stdout)

    def test_required_ansible_modules_reports_missing_collection_module(self):
        result = self.run_common(
            'ID=rocky\nVERSION_ID="9.4"\nID_LIKE="rhel centos fedora"\n',
            """
ansible-doc() {
  case "$*" in
    *community.mysql.mysql_db*) return 1 ;;
    *) return 0 ;;
  esac
}
if required_ansible_modules_available; then
  echo unexpected-pass
  exit 1
fi
""",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("missing modules: community.mysql.mysql_db", result.stdout)

    def test_glpi_database_compatibility_matrix(self):
        result = self.run_common(
            'ID=rocky\nVERSION_ID="9.4"\nID_LIKE="rhel centos fedora"\n',
            """
check_case() {
  local glpi_version="$1"
  local db_banner="$2"
  local expected="$3"
  local report
  report="$(glpi_db_compatibility_report "$glpi_version" "$db_banner")"
  printf '%s|%s|%s\\n' "$glpi_version" "$db_banner" "$(glpi_db_compatibility_value "$report" status)"
  [[ "$(glpi_db_compatibility_value "$report" status)" == "$expected" ]]
}
check_case "11.0.8" "10.5.27-MariaDB MariaDB Server" "fail"
check_case "11.0.8" "10.6.21-MariaDB MariaDB Server" "pass"
check_case "11.0.8" "8.0.36 MySQL Community Server" "pass"
check_case "10.0.18" "10.5.27-MariaDB MariaDB Server" "pass"
""",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("11.0.8|10.5.27-MariaDB MariaDB Server|fail", result.stdout)
        self.assertIn("11.0.8|10.6.21-MariaDB MariaDB Server|pass", result.stdout)
        self.assertIn("11.0.8|8.0.36 MySQL Community Server|pass", result.stdout)
        self.assertIn("10.0.18|10.5.27-MariaDB MariaDB Server|pass", result.stdout)

    def test_database_compatibility_policy_helpers_are_explicit(self):
        result = self.run_common(
            'ID=rocky\nVERSION_ID="9.4"\nID_LIKE="rhel centos fedora"\n',
            """
[[ "$(normalize_database_compatibility_policy "")" == "block" ]]
[[ "$(normalize_database_compatibility_policy "warn")" == "block" ]]
[[ "$(normalize_database_compatibility_policy "defer")" == "block" ]]
[[ "$(normalize_database_compatibility_policy "allow")" == "invalid" ]]
environment_stage_allows_unsupported_database "hml"
environment_stage_allows_unsupported_database "example-hml"
environment_stage_allows_unsupported_database "staging"
! environment_stage_allows_unsupported_database "unknown"
environment_stage_is_production "prod"
environment_stage_is_production "production"
! environment_stage_is_production "hml"
echo policy-helpers-ok
""",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("policy-helpers-ok", result.stdout)


if __name__ == "__main__":
    unittest.main()
