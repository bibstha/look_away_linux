#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if [[ ${1:-} != "" && ${1:-} != --autostart ]]; then
  echo "Usage: scripts/install.sh [--autostart]" >&2
  exit 2
fi
cargo_bin=$(command -v cargo || true)
if [[ -z "$cargo_bin" && -x "$HOME/.cargo/bin/cargo" ]]; then cargo_bin="$HOME/.cargo/bin/cargo"; fi
if [[ -z "$cargo_bin" ]]; then echo 'Install Rust with rustup first: https://rustup.rs' >&2; exit 1; fi
command -v quickshell >/dev/null || { echo 'Quickshell is required.' >&2; exit 1; }
"$cargo_bin" build --release --locked
python3 scripts/integrate.py install
systemctl --user daemon-reload
if [[ ${1:-} == --autostart ]]; then
  systemctl --user enable --now look-away.service
else
  systemctl --user restart look-away.service
fi
if command -v omarchy-shell >/dev/null; then omarchy-shell shell rescanPlugins; fi
echo 'Look Away is running. Click the eye countdown in the bar for controls.'
