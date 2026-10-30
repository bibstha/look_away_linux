"""Exercise installer mutations in a temporary HOME, without starting services."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class IntegrationTest(unittest.TestCase):
    def test_install_is_idempotent_and_uninstall_preserves_other_settings(self):
        if not (ROOT / "target/release/look-away").exists():
            self.skipTest("cargo build --release first")
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".config"
            shell = config / "omarchy/shell.json"
            shell.parent.mkdir(parents=True)
            original = {"version": 1, "idle": {"lock": 999}, "custom": "keep", "bar": {"layout": {"left": [], "right": [{"id": "existing"}]}}}
            shell.write_text(json.dumps(original))
            env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(config))
            def run(action):
                subprocess.run(["python3", str(ROOT / "scripts/integrate.py"), action], env=env, check=True, capture_output=True)
            run("install")
            yaml = config / "look-away/config.yaml"
            yaml.write_text("work_duration: 22m\n")
            run("install")
            installed = json.loads(shell.read_text())
            self.assertEqual(installed["idle"], original["idle"])
            self.assertEqual(installed["custom"], "keep")
            self.assertEqual(installed["bar"]["layout"]["right"], [{"id": "local.look-away"}, {"id": "existing"}])
            self.assertEqual(yaml.read_text(), "work_duration: 22m\n")
            run("uninstall")
            self.assertEqual(json.loads(shell.read_text()), original)
            self.assertTrue(yaml.exists())
            self.assertFalse((home / ".local/bin/look-away").exists())
            self.assertTrue(list(shell.parent.glob("shell.json.look-away-backup-*")))


if __name__ == "__main__":
    unittest.main()
