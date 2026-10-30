#!/usr/bin/env python3
"""Install owned files and one bar entry, preserving existing Omarchy settings."""
import datetime
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config"))
PREFIX = HOME / ".local"
PLUGIN_ID = "local.look-away"
PLUGIN = CONFIG / "omarchy/plugins" / PLUGIN_ID
UI = PREFIX / "share/look-away/ui"
SHELL = CONFIG / "omarchy/shell.json"
SERVICE = CONFIG / "systemd/user/look-away.service"
BIN = PREFIX / "bin/look-away"


def write_shell(install):
    if not SHELL.exists():
        if install:
            raise SystemExit(f"Omarchy shell config not found: {SHELL}")
        return
    current = SHELL.read_text()
    data = json.loads(current)
    if data.get("version") != 1:
        raise SystemExit("Unsupported Omarchy shell configuration version")
    layout = data.setdefault("bar", {}).setdefault("layout", {})
    found = any(entry.get("id") == PLUGIN_ID for entries in layout.values() for entry in entries)
    if install and not found:
        layout.setdefault("right", []).insert(0, {"id": PLUGIN_ID})
    elif not install and found:
        for section, entries in layout.items():
            layout[section] = [e for e in entries if e.get("id") != PLUGIN_ID]
    else:
        return
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup = SHELL.with_name(f"shell.json.look-away-backup-{stamp}")
    shutil.copy2(SHELL, backup)
    temporary = SHELL.with_name("shell.json.look-away-tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(SHELL)
    print(f"Bar config backup: {backup}")


def install():
    # Validate before changing any files.
    data = json.loads(SHELL.read_text())
    if data.get("version") != 1:
        raise SystemExit("Expected Omarchy shell.json version 1")
    BIN.parent.mkdir(parents=True, exist_ok=True)
    temporary = BIN.with_name("look-away.new")
    shutil.copy2(ROOT / "target/release/look-away", temporary)
    temporary.chmod(0o755)
    temporary.replace(BIN)
    for destination in [UI, PLUGIN]:
        destination.mkdir(parents=True, exist_ok=True)
        for source in (ROOT / "ui").iterdir():
            if source.is_file():
                shutil.copy2(source, destination / source.name)
    config = CONFIG / "look-away/config.yaml"
    config.parent.mkdir(parents=True, exist_ok=True)
    if not config.exists():
        shutil.copy2(ROOT / "config.example.yaml", config)
    SERVICE.parent.mkdir(parents=True, exist_ok=True)
    # systemd quoted values escape backslashes, quotes and % specifiers.
    executable = str(BIN).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
    SERVICE.write_text(f'''[Unit]
Description=Look Away eye-break reminders
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart="{executable}" run
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
''')
    write_shell(True)
    print(f"Configuration: {config}")


def uninstall():
    write_shell(False)
    for path in [PLUGIN, UI]:
        if path.exists():
            shutil.rmtree(path)
    for path in [BIN, SERVICE]:
        path.unlink(missing_ok=True)


if __name__ == "__main__":
    {"install": install, "uninstall": uninstall}[sys.argv[1]]()
