// Timer rules and configuration parsing, free of QML so tests can run them under
// Node with a deterministic clock. Every `now` is milliseconds on the service's
// own clock (see advanceClock), and durations are milliseconds.

var SECOND = 1000
var MINUTE = 60 * SECOND
var HOUR = 60 * MINUTE
var DAY = 24 * HOUR
var WEEK = 7 * DAY

var SKIP_DELAY = 5 * SECOND
var SNOOZE_MINUTES = [1, 5, 15]
// The longest stretch one clock step may count. A longer gap between ticks means
// the machine slept, and sleep is not work time.
var MAX_CLOCK_STEP = 5 * SECOND
// Saved state older than this belongs to an earlier session, not a shell restart.
var MAX_RESTORE_AGE = 2 * MINUTE

var UNITS = {
  ms: 1, msec: 1, msecs: 1, millisecond: 1, milliseconds: 1,
  s: SECOND, sec: SECOND, secs: SECOND, second: SECOND, seconds: SECOND,
  m: MINUTE, min: MINUTE, mins: MINUTE, minute: MINUTE, minutes: MINUTE,
  h: HOUR, hr: HOUR, hrs: HOUR, hour: HOUR, hours: HOUR,
  d: DAY, day: DAY, days: DAY,
  w: WEEK, week: WEEK, weeks: WEEK
}

function defaultConfig() {
  return {
    work_duration: 30 * MINUTE,
    short_break: 30 * SECOND,
    long_break: 3 * MINUTE,
    long_break_every: 4,
    warning_before: 60 * SECOND,
    warning_duration: 8 * SECOND
  }
}

// "30m" or "1h 30m"; null for anything else, including a bare number.
function parseDuration(text) {
  var value = String(text).trim()
  if (!/^(\d+\s*[a-z]+\s*)+$/.test(value)) return null
  var total = 0
  var pattern = /(\d+)\s*([a-z]+)/g
  var match
  while ((match = pattern.exec(value)) !== null) {
    if (!Object.prototype.hasOwnProperty.call(UNITS, match[2])) return null
    total += Number(match[1]) * UNITS[match[2]]
  }
  return total
}

function isDurationKey(key) {
  return key === "work_duration" || key === "short_break" || key === "long_break"
    || key === "warning_before" || key === "warning_duration"
}

function stripValue(raw) {
  var value = raw.replace(/\s+#.*$/, "").trim()
  var quoted = value.match(/^(["'])(.*)\1$/)
  return quoted ? quoted[2] : value
}

// The flat `key: value` subset of YAML the configuration uses. Returns
// { config } or { error }; a key left out inherits its default.
function parseConfig(text) {
  var config = defaultConfig()
  var seen = {}
  var lines = String(text === null || text === undefined ? "" : text).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "" || line === "---" || line.charAt(0) === "#") continue
    var match = line.match(/^([a-z_]+):\s*(.*)$/)
    if (!match) return { error: "Invalid configuration on line " + (i + 1) }
    var key = match[1]
    if (!Object.prototype.hasOwnProperty.call(config, key)) return { error: "Unknown setting: " + key }
    if (seen[key]) return { error: "Duplicate setting: " + key }
    seen[key] = true
    var value = stripValue(match[2])
    if (isDurationKey(key)) {
      var duration = parseDuration(value)
      if (duration === null) return { error: key + " must be a duration such as 30s or 20m" }
      config[key] = duration
    } else {
      if (!/^\d+$/.test(value)) return { error: key + " must be a whole number" }
      config[key] = Number(value)
    }
  }
  var bounded = ["work_duration", "short_break", "long_break"]
  for (var b = 0; b < bounded.length; b++) {
    if (config[bounded[b]] < SECOND || config[bounded[b]] > WEEK) {
      return { error: bounded[b] + " must be at least one second and at most 7 days" }
    }
  }
  if (config.warning_before > WEEK || config.warning_duration > 60 * SECOND) {
    return { error: "warning_before must be at most 7 days; warning_duration must be at most 60 seconds" }
  }
  return { config: config }
}

function advanceClock(clock, lastWall, wall) {
  var step = wall - lastWall
  if (step < 0 || step > MAX_CLOCK_STEP) step = 0
  return clock + step
}

function createTimer(config, now) {
  return {
    config: config,
    phase: "work",
    deadline: now + config.work_duration,
    enabled: true,
    paused: config.work_duration,
    completed: 0,
    total: config.work_duration,
    pendingBreak: null
  }
}

function nextBreak(timer) {
  if (timer.pendingBreak) return timer.pendingBreak
  var every = timer.config.long_break_every
  return every > 0 && timer.completed >= every - 1 ? "long_break" : "short_break"
}

function startWork(timer, now) {
  timer.phase = "work"
  timer.pendingBreak = null
  timer.total = timer.config.work_duration
  timer.deadline = now + timer.total
  timer.paused = timer.total
}

function startBreak(timer, phase, now) {
  timer.enabled = true
  timer.pendingBreak = null
  timer.phase = phase
  timer.total = phase === "long_break" ? timer.config.long_break : timer.config.short_break
  timer.deadline = now + timer.total
}

// A late tick starts the next phase from `now`, so a break is never skipped.
function tick(timer, now) {
  if (!timer.enabled || now < timer.deadline) return
  if (timer.phase === "work") {
    startBreak(timer, nextBreak(timer), now)
    return
  }
  timer.completed = timer.phase === "long_break" ? 0 : timer.completed + 1
  startWork(timer, now)
}

function setEnabled(timer, enabled, now) {
  if (timer.enabled === enabled) return
  if (!enabled) {
    if (timer.phase !== "work") startWork(timer, now)
    timer.paused = Math.max(0, timer.deadline - now)
  } else {
    timer.deadline = now + timer.paused
  }
  timer.enabled = enabled
}

function status(timer, now) {
  var remaining = timer.enabled ? Math.max(0, timer.deadline - now) : timer.paused
  var seconds = Math.ceil(remaining / SECOND)
  var elapsed = Math.max(0, timer.total - remaining)
  var skipWait = Math.max(0, SKIP_DELAY - elapsed)
  var inWork = timer.phase === "work"
  var config = timer.config
  var label
  if (!timer.enabled) label = "Off"
  else if (seconds > 60 && inWork) label = String(Math.ceil(seconds / 60))
  else label = String(seconds)
  return {
    enabled: timer.enabled,
    phase: timer.phase,
    remaining_seconds: seconds,
    label: label,
    completed_short_breaks: timer.completed,
    next_break: nextBreak(timer),
    total_seconds: Math.floor(timer.total / SECOND),
    warning: timer.enabled && inWork
      && timer.total > config.warning_before
      && remaining <= config.warning_before
      && remaining > Math.max(0, config.warning_before - config.warning_duration),
    skip_wait_seconds: Math.ceil(skipWait / SECOND),
    skip_allowed: timer.enabled && !inWork && skipWait === 0
  }
}

function snooze(timer, minutes, now) {
  if (SNOOZE_MINUTES.indexOf(minutes) === -1) return false
  var extra = minutes * MINUTE
  if (timer.phase === "work") {
    timer.deadline += extra
    timer.paused += extra
    timer.total += extra
    return true
  }
  if (!status(timer, now).skip_allowed) return false
  timer.pendingBreak = timer.phase
  timer.phase = "work"
  timer.total = extra
  timer.deadline = now + extra
  timer.paused = extra
  return true
}

function skip(timer, now) {
  if (!status(timer, now).skip_allowed) return false
  startWork(timer, now)
  return true
}

function reload(timer, config, now) {
  timer.config = config
  timer.completed = 0
  startWork(timer, now)
}

// One command from the menu, the break screen or IPC. Returns an error message,
// or "" on success. `reload` is the service's, since it has to read the file.
function act(timer, command, now) {
  var parts = String(command).split(" ")
  switch (parts[0]) {
    case "short-break": startBreak(timer, "short_break", now); return ""
    case "long-break": startBreak(timer, "long_break", now); return ""
    case "disable": setEnabled(timer, false, now); return ""
    case "enable": setEnabled(timer, true, now); return ""
    case "toggle": setEnabled(timer, !timer.enabled, now); return ""
    case "skip":
      return skip(timer, now) ? "" : "Skip becomes available after five seconds of a break"
    case "snooze":
      return snooze(timer, Number(parts[1]), now) ? "" : "Choose 1, 5 or 15 minutes. During breaks, wait five seconds first."
    default:
      return "Unknown command"
  }
}

// What a restarted shell needs, with times relative to the moment of saving.
function snapshot(timer, now, wall) {
  return {
    saved_at: wall,
    phase: timer.phase,
    enabled: timer.enabled,
    remaining: timer.enabled ? Math.max(0, timer.deadline - now) : timer.paused,
    paused: timer.paused,
    completed: timer.completed,
    total: timer.total,
    pending_break: timer.pendingBreak
  }
}

function isPhase(phase) {
  return phase === "work" || phase === "short_break" || phase === "long_break"
}

function isBreak(phase) {
  return phase === "short_break" || phase === "long_break"
}

function isTime(value) {
  return typeof value === "number" && isFinite(value) && value >= 0
}

// A timer from saved text, or null when it is unusable or too old.
function restore(text, config, now, wall) {
  var saved
  try {
    saved = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!saved || typeof saved !== "object" || !isPhase(saved.phase)) return null
  if (typeof saved.enabled !== "boolean") return null
  if (!isTime(saved.saved_at) || !isTime(saved.remaining) || !isTime(saved.paused)) return null
  if (!isTime(saved.completed) || !isTime(saved.total)) return null
  if (saved.pending_break !== null && !isBreak(saved.pending_break)) return null
  var age = wall - saved.saved_at
  if (age < 0 || age > MAX_RESTORE_AGE) return null
  return {
    config: config,
    phase: saved.phase,
    deadline: now + saved.remaining,
    enabled: saved.enabled,
    paused: saved.paused,
    completed: saved.completed,
    total: saved.total,
    pendingBreak: saved.pending_break
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    SECOND: SECOND,
    MINUTE: MINUTE,
    defaultConfig: defaultConfig,
    parseDuration: parseDuration,
    parseConfig: parseConfig,
    advanceClock: advanceClock,
    createTimer: createTimer,
    tick: tick,
    startBreak: startBreak,
    setEnabled: setEnabled,
    status: status,
    snooze: snooze,
    skip: skip,
    reload: reload,
    act: act,
    snapshot: snapshot,
    restore: restore
  }
}
