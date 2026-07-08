import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
COMMON_SH = REPO_ROOT / "scripts" / "lib" / "common.sh"


class OperationLoggingTest(unittest.TestCase):
    def test_operation_log_stream_finishes_before_following_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            script_root = root / "scripts"
            logs_dir = root / ".runtime" / "test-env" / "logs"
            script_root.mkdir(parents=True)
            logs_dir.mkdir(parents=True)

            script = f"""
set -euo pipefail
SCRIPT_ROOT={shlex.quote(str(script_root))}
source {shlex.quote(str(COMMON_SH))}
begin_operation_log test-env test-operation "unit test"
echo "first logged line"
echo "last logged line"
finish_operation_log_stream
echo "after finish"
"""
            result = subprocess.run(
                ["bash", "-lc", script],
                cwd=REPO_ROOT,
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            output_lines = result.stdout.strip().splitlines()
            self.assertGreaterEqual(len(output_lines), 4, result.stdout)
            self.assertIn("last logged line", output_lines[-2])
            self.assertEqual(output_lines[-1], "after finish")

            log_path = logs_dir / "test-operation.log"
            self.assertTrue(log_path.exists())
            self.assertIn("last logged line", log_path.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
