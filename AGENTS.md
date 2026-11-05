# Development guidelines

- `Model.js` owns timing rules, scheduling, configuration validation, and command behavior, with no QML so tests can run it. `Service.qml` runs it; the other QML files render its state and send commands.
- Use Omarchy's native components and live theme tokens for the bar menu. Keep break screens on Wayland overlay layers, covering all connected screens.
- Preserve the five-second delay before Skip and postpone controls become available during breaks. Test timer behavior with deterministic clocks where possible.
- Keep installation user-local, reversible, and respectful of existing configuration. Do not install the plugin, restart the shell, or change the developer's desktop configuration unless requested.
- This repository is public. Never commit credentials, private configuration, personal paths, logs, or screenshots containing unrelated desktop content.
- Keep changes focused and update the README when user-visible behavior changes.

For code changes, run the relevant checks:

```sh
./tests/run
./tests/service-restart
omarchy plugin validate .
```

Verify graphical changes in a Hyprland session when available; report any checks you could not run.
