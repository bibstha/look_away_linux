# Look Away for Omarchy

A small Rust app that reminds you to give your eyes a rest. Built for **Hyprland and the current Quickshell-based Omarchy bar**. The bar menu uses Omarchy’s native panel components and follows its theme, fonts, borders, and spacing. The break screen’s soft gradients and typography take visual inspiration from [LookAway](https://lookaway.com/); this is an independent Linux implementation.

## What it does

- Work for **30 minutes**, then look away for **30 seconds**.
- Every fourth completed break lasts **3 minutes** instead: short → short → short → long.
- The bar displays whole minutes, then seconds during the final minute: `30`, `29`, … `2`, `60`, `59`, …
- A click-through heads-up appears **one minute before** a scheduled break and disappears after **8 seconds**.
- A click-through badge follows the pointer during the **last 5 seconds**.
- An opaque Wayland **overlay layer** covers every connected screen during breaks, including the bar and fullscreen apps. It is not a tiled or ordinary fullscreen application window.
- The break screen displays a large countdown and closes automatically when time is up. Then a fresh work session starts.
- **Skip in 5s → 4s → 3s → 2s → 1s**, with circular progress, becomes **Skip this break** after five seconds. Rust enforces the delay.
- **Wait 1 / 5 / 15 min** in both the bar menu and break overlay. During work this adds to the remaining time; during a break it postpones that same kind of break. Overlay controls unlock after five seconds.
- Left-click the eye countdown for the menu; right-click to enable/disable reminders. Manual short and long breaks are available in the menu.

This first version has no idle detection, meeting detection, sounds, or analytics. The pointer position is queried locally only during the final countdown; no input is recorded.

## Install and run

Requires Rust/Cargo, Quickshell, Hyprland, Python 3, and a systemd user session. On current Omarchy, the desktop dependencies are already present. Install Rust through [rustup](https://rustup.rs/) if needed.

```sh
./scripts/install.sh
```

This builds a release binary, installs it to `~/.local/bin/look-away`, installs a bar plugin, backs up `shell.json` before adding the eye widget, and starts a user service. Existing layout entries and YAML settings are preserved. You should see the eye and `30` in the bar.

To also start at future logins:

```sh
./scripts/install.sh --autostart
# Or after installing:
systemctl --user enable look-away.service
```

To stop or start:

```sh
systemctl --user stop look-away.service
systemctl --user start look-away.service
```

For development without installation:

```sh
cargo run -- run
# Or use accelerated timings in your own config:
cargo run -- --config /path/to/test.yaml run
```

Only one timer instance can run per desktop runtime directory. Stop the installed service before using `cargo run`. A development instance provides the overlay; the bar widget is installed by the installer.

## Configuration

Edit `~/.config/look-away/config.yaml` (or `$XDG_CONFIG_HOME/look-away/config.yaml`):

```yaml
work_duration: 30m
short_break: 30s
long_break: 3m
long_break_every: 4
warning_before: 60s
warning_duration: 8s
```

Durations accept units such as `s`, `m`, and `h`. Work and break durations must be between one second and seven days. Set `long_break_every: 0` for manual long breaks only. Set either warning duration to `0s` to disable the heads-up. The pointer badge remains enabled for the final five seconds.

Click **Reload configuration** in the menu, or run `look-away reload`. Reload validates the file and starts a fresh work session; a bad file leaves the running timer intact. Partial YAML files inherit defaults. Unknown keys are rejected to catch typos. A missing file uses defaults.

Disabling freezes the work countdown. Disabling during a break dismisses it and prepares a fresh work session; enabling resumes it. An on-demand break enables reminders. Completed short breaks advance the cycle; a completed long break resets it. Skipping or postponing a break does not count it as completed. Restarting the app resets the session and enables reminders. Timing uses a monotonic clock and does not count system suspend as work time on Linux. Desktop locking is not detected in this version.

## Commands

```sh
look-away                     # Same as `look-away run`
look-away status              # JSON snapshot
look-away watch               # Streaming newline-delimited JSON
look-away short-break
look-away long-break
look-away snooze 1             # Also accepts 5 or 15; adds minutes
look-away disable
look-away enable
look-away toggle
look-away skip                 # Only during breaks, after five seconds
look-away reload
look-away quit
```

The service owns the timer; a separate Quickshell frontend draws overlays. The bar is a small Omarchy plugin. Both consume the same Rust state over a private Unix socket under `$XDG_RUNTIME_DIR/look-away/`. The app stops if its frontend exits, so a hidden timer cannot silently count breaks with no overlay. If the installed frontend repeatedly fails, inspect `journalctl --user -u look-away.service`.

The overlay is a reminder, not a security lock screen. Hyprland compositor shortcuts remain available.

## Research and defaults

The [American Optometric Association recommends the 20-20-20 rule](https://www.aoa.org/healthy-eyes/eye-and-vision-conditions/computer-vision-syndrome/20-20-20-rule?sso=y): look at something 20 feet away for 20 seconds every 20 minutes. Its guidance also recommends longer rests after sustained computer use. [Oregon OSHA's workstation guide](https://ehs.oregonstate.edu/sites/ehs.oregonstate.edu/files/pdf/ergo/or-osha_evaluating_your_computer_workstation.pdf) describes frequent short breaks and longer breaks depending on work intensity.

The requested **30m / 30s / 3m every fourth break** is a configurable personal schedule, not a medically established prescription. For the common 20-20-20 reminder, set `work_duration: 20m` and `short_break: 20s`. A reminder app cannot establish that you actually looked away.

The compositor integration follows Quickshell's [PanelWindow](https://quickshell.org/docs/v0.2.0/types/Quickshell/PanelWindow/) and [WlrLayershell](https://quickshell.org/docs/v0.2.0/types/Quickshell.Wayland/WlrLayershell/) APIs.

## Development and verification

```sh
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
python3 -m unittest discover -s tests -p 'test_*.py'
```

Tests cover display boundaries, automatic break cycling, warning timing, disable/resume, five-second skip enforcement, additive snoozing and preserved break types, configuration validation, actual Unix-socket commands and streaming, automatic transitions, failed reload recovery, duplicate-instance rejection, and shutdown cleanup. The graphical frontend is checked separately in a live Hyprland session.

Source layout:

- `src/`: Rust timer, YAML validation, daemon, and CLI.
- `ui/`: Quickshell overlay and Omarchy widget.
- `scripts/`: reversible user-local installation and bar integration.

Remove the installed app with:

```sh
./scripts/uninstall.sh
```

This removes its bar entry, user service, binary, and frontend. Your YAML and bar configuration backups are retained.

MIT licensed.
