import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The plugin's engine, instantiated once per shell as its `service` entry point.
// It owns the timer and draws the overlays; every bar widget reads this instance.
Item {
  id: root

  property var shell: null
  property var timer: null
  property var clockMs: 0
  property var lastWall: 0
  property var state: ({ enabled: false, phase: "work", remaining_seconds: 0, label: "—", completed_short_breaks: 0, next_break: "short_break", total_seconds: 1, warning: false, skip_wait_seconds: 0, skip_allowed: false })
  property string error: ""
  property string lastPublished: ""

  readonly property bool online: timer !== null
  readonly property bool breaking: online && state.enabled && state.phase !== "work"
  readonly property bool starting: online && state.enabled && state.phase === "work" && state.remaining_seconds <= 5

  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  // Under /run/user: it survives a shell restart without writing to disk every
  // few seconds, and a reboot starts fresh.
  readonly property string statePath: Quickshell.env("XDG_RUNTIME_DIR") + "/look-away-state.json"

  function clock(seconds) {
    return Math.floor(seconds / 60).toString().padStart(2, "0") + ":" + (seconds % 60).toString().padStart(2, "0")
  }

  function read(view) {
    view.reload()
    view.waitForJob()
    return view.loaded ? view.text() : ""
  }

  function advance() {
    var wall = Date.now()
    clockMs = Model.advanceClock(clockMs, lastWall, wall)
    lastWall = wall
    return clockMs
  }

  function publish() {
    if (!timer) return
    var next = Model.status(timer, clockMs)
    var text = JSON.stringify(next)
    if (text === lastPublished) return
    lastPublished = text
    state = next
  }

  function save() {
    if (timer) stateFile.setText(JSON.stringify(Model.snapshot(timer, clockMs, lastWall)))
  }

  function tick() {
    if (!timer) return
    var phase = timer.phase
    Model.tick(timer, advance())
    publish()
    if (timer.phase !== phase) save()
  }

  function reload() {
    var parsed = Model.parseConfig(read(configFile))
    if (parsed.error) return "Reading config.yaml: " + parsed.error
    Model.reload(timer, parsed.config, advance())
    return ""
  }

  function act(command) {
    if (!timer) return "Look Away has not started"
    var now = advance()
    error = command === "reload" ? reload() : Model.act(timer, command, now)
    publish()
    save()
    return error
  }

  function start() {
    lastWall = Date.now()
    var parsed = Model.parseConfig(read(configFile))
    // A bad file must not cost you your reminders: run on defaults and say so.
    var config = parsed.error ? Model.defaultConfig() : parsed.config
    error = parsed.error ? "Reading config.yaml: " + parsed.error + ". Using defaults." : ""
    timer = Model.restore(read(stateFile), config, clockMs, lastWall) || Model.createTimer(config, clockMs)
    publish()
    save()
  }

  function reply(command) {
    var failure = act(command)
    return failure ? JSON.stringify({ error: failure }) : JSON.stringify(state)
  }

  Component.onCompleted: start()

  FileView {
    id: configFile
    path: root.configHome + "/look-away/config.yaml"
    printErrors: false
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    atomicWrites: true
  }

  Timer {
    interval: 200
    running: root.online
    repeat: true
    onTriggered: root.tick()
  }

  Timer {
    interval: 5000
    running: root.online
    repeat: true
    onTriggered: root.save()
  }

  // omarchy-shell local.look-away <command>
  IpcHandler {
    target: "local.look-away"
    function status(): string { return JSON.stringify(root.state) }
    function shortBreak(): string { return root.reply("short-break") }
    function longBreak(): string { return root.reply("long-break") }
    function disable(): string { return root.reply("disable") }
    function enable(): string { return root.reply("enable") }
    function toggle(): string { return root.reply("toggle") }
    function skip(): string { return root.reply("skip") }
    function snooze(minutes: int): string { return root.reply("snooze " + minutes) }
    function reload(): string { return root.reply("reload") }
  }

  Overlays {
    session: root
  }
}
