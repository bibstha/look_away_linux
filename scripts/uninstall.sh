#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
systemctl --user disable --now look-away.service 2>/dev/null || true
python3 scripts/integrate.py uninstall
systemctl --user daemon-reload
if command -v omarchy-shell >/dev/null; then omarchy-shell shell rescanPlugins; fi
echo 'Look Away removed. Your YAML configuration has been kept.'
