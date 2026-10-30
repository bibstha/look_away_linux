# Development guidelines

- Rust (`src/`) owns timer state, scheduling, configuration validation, and command behavior. QML (`ui/`) renders that state and sends commands; keep timing rules in Rust.
- Use Omarchy's native components and live theme tokens for the bar menu. Keep break screens on Wayland overlay layers, covering all connected screens.
- Preserve the five-second delay before Skip and postpone controls become available during breaks. Test timer behavior with deterministic clocks where possible.
- Keep installation user-local, reversible, and respectful of existing configuration. Do not run installers, restart desktop services, or change the developer's desktop configuration unless requested.
- This repository is public. Never commit credentials, private configuration, personal paths, logs, or screenshots containing unrelated desktop content.
- Keep changes focused and update the README when user-visible behavior changes.

For code changes, run the relevant checks:

```sh
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
```

For installer changes, also run `cargo build --release --locked` and
`python3 -m unittest discover -s tests -p 'test_*.py'`.
Verify graphical changes in a Hyprland session when available; report any checks you could not run.
