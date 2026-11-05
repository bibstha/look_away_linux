const test = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

const s = (seconds) => seconds * 1000

function config(overrides = {}) {
  return { ...Model.defaultConfig(), ...overrides }
}

function fast() {
  return config({ work_duration: s(10), short_break: s(2), long_break: s(5), long_break_every: 4 })
}

test("snooze adds time and preserves a deferred break", () => {
  const t = Model.createTimer(config(), 0)
  assert.equal(Model.snooze(t, 5, 0), true)
  assert.equal(Model.status(t, 0).remaining_seconds, 2100)
  assert.equal(Model.snooze(t, 1, 0), true)
  assert.equal(Model.status(t, 0).remaining_seconds, 2160)
  assert.equal(Model.snooze(t, 2, 0), false)
  Model.startBreak(t, "long_break", 0)
  assert.equal(Model.snooze(t, 5, 0), false)
  const later = s(5)
  assert.equal(Model.snooze(t, 5, later), true)
  assert.equal(Model.status(t, later).remaining_seconds, 300)
  assert.equal(Model.status(t, later).phase, "work")
  assert.equal(Model.status(t, later).next_break, "long_break")
  Model.tick(t, later + s(300))
  assert.equal(Model.status(t, later + s(300)).phase, "long_break")
  assert.equal(Model.status(t, later + s(300)).skip_wait_seconds, 5)
  Model.setEnabled(t, false, later)
  assert.equal(Model.snooze(t, 15, later), true)
  assert.equal(Model.status(t, later).remaining_seconds, 2700)
})

test("skip is locked for five seconds", () => {
  const t = Model.createTimer(config(), 0)
  assert.equal(Model.skip(t, 0), false)
  Model.startBreak(t, "short_break", 0)
  assert.equal(Model.status(t, 0).skip_wait_seconds, 5)
  assert.equal(Model.skip(t, 4999), false)
  assert.equal(Model.skip(t, s(5)), true)
  assert.equal(Model.status(t, 0).phase, "work")
  assert.equal(Model.status(t, 0).completed_short_breaks, 0)
})

test("the warning disappears without moving the deadline", () => {
  const t = Model.createTimer(config(), 0)
  for (const [elapsed, expected] of [[1739, false], [1740, true], [1747, true], [1748, false], [1799, false]]) {
    assert.equal(Model.status(t, s(elapsed)).warning, expected, `at ${elapsed}s`)
  }
})

test("the bar shows minutes, then seconds in the final minute", () => {
  const t = Model.createTimer(config(), 0)
  for (const [elapsed, label] of [[0, "30"], [60, "29"], [1739, "2"], [1740, "60"], [1741, "59"]]) {
    assert.equal(Model.status(t, s(elapsed)).label, label, `at ${elapsed}s`)
  }
})

test("every fourth completed break is long, and work restarts after each", () => {
  let now = 0
  const t = Model.createTimer(fast(), now)
  for (const expected of ["short_break", "short_break", "short_break", "long_break", "short_break"]) {
    now += s(10)
    Model.tick(t, now)
    assert.equal(Model.status(t, now).phase, expected)
    now += expected === "long_break" ? s(5) : s(2)
    Model.tick(t, now)
    assert.equal(Model.status(t, now).phase, "work")
    assert.equal(Model.status(t, now).remaining_seconds, 10)
  }
})

test("disabling freezes work, and disabling during a break dismisses it", () => {
  const t = Model.createTimer(fast(), 0)
  Model.setEnabled(t, false, s(3))
  Model.tick(t, s(100))
  assert.equal(Model.status(t, 0).remaining_seconds, 7)
  assert.equal(Model.status(t, 0).label, "Off")
  Model.setEnabled(t, true, s(100))
  assert.equal(Model.status(t, s(100)).remaining_seconds, 7)
  Model.startBreak(t, "long_break", 0)
  Model.setEnabled(t, false, 0)
  assert.equal(Model.status(t, 0).phase, "work")
  assert.equal(Model.status(t, 0).completed_short_breaks, 0)
})

test("skipped breaks do not count, and a late tick does not skip the overlay", () => {
  const t = Model.createTimer(fast(), 0)
  Model.tick(t, s(1000))
  assert.equal(Model.status(t, s(1000)).phase, "short_break")
  assert.equal(Model.status(t, s(1000)).remaining_seconds, 2)
  assert.equal(Model.skip(t, 0), false)
  assert.equal(Model.status(t, 0).completed_short_breaks, 0)
  t.config.long_break_every = 0
  for (let i = 0; i < 5; i++) {
    Model.startBreak(t, "short_break", 0)
    Model.tick(t, s(2))
  }
  assert.equal(Model.status(t, 0).next_break, "short_break")
  Model.reload(t, fast(), 0)
  assert.equal(Model.status(t, 0).completed_short_breaks, 0)
})

test("the clock does not count sleep or a clock moved backwards", () => {
  assert.equal(Model.advanceClock(100, s(1), s(1) + 200), 300)
  assert.equal(Model.advanceClock(100, s(1), s(1) + s(5)), 100 + s(5))
  assert.equal(Model.advanceClock(100, s(1), s(1) + s(3600)), 100, "a night of sleep")
  assert.equal(Model.advanceClock(100, s(10), s(1)), 100, "clock set back")
})

test("a night of sleep does not start a break on wake", () => {
  const t = Model.createTimer(config(), 0)
  const wake = Model.advanceClock(s(600), s(600), s(600) + s(8 * 3600))
  Model.tick(t, wake)
  assert.equal(Model.status(t, wake).phase, "work")
  assert.equal(Model.status(t, wake).remaining_seconds, 1200)
})

test("commands report their errors", () => {
  const t = Model.createTimer(config(), 0)
  assert.match(Model.act(t, "skip", 0), /five seconds/)
  assert.match(Model.act(t, "snooze 2", 0), /1, 5 or 15/)
  assert.match(Model.act(t, "snooze", 0), /1, 5 or 15/)
  assert.equal(Model.act(t, "nonsense", 0), "Unknown command")
  assert.equal(Model.act(t, "snooze 5", 0), "")
  assert.equal(Model.act(t, "toggle", 0), "")
  assert.equal(Model.status(t, 0).enabled, false)
  assert.equal(Model.act(t, "enable", 0), "")
  assert.equal(Model.act(t, "disable", 0), "")
  assert.equal(Model.act(t, "short-break", 0), "")
  assert.equal(Model.status(t, 0).phase, "short_break")
  assert.equal(Model.status(t, 0).enabled, true)
  assert.equal(Model.act(t, "long-break", 0), "")
  assert.equal(Model.status(t, 0).phase, "long_break")
  assert.equal(Model.act(t, "skip", s(5)), "")
})

test("a saved timer resumes where it stopped", () => {
  const t = Model.createTimer(config(), 0)
  const saved = JSON.stringify(Model.snapshot(t, s(600), 5000000))
  const restored = Model.restore(saved, config(), 42, 5000000 + s(3))
  assert.equal(Model.status(restored, 42).remaining_seconds, 1200)
  assert.equal(Model.status(restored, 42).phase, "work")
})

test("a saved break keeps its skip delay, paused state and deferred break", () => {
  const t = Model.createTimer(config(), 0)
  Model.startBreak(t, "short_break", 0)
  let restored = Model.restore(JSON.stringify(Model.snapshot(t, s(2), 1000)), config(), 0, 1000)
  assert.equal(Model.status(restored, 0).phase, "short_break")
  assert.equal(Model.status(restored, 0).skip_wait_seconds, 3)
  assert.equal(Model.status(restored, 0).remaining_seconds, 28)

  const paused = Model.createTimer(config(), 0)
  Model.setEnabled(paused, false, s(100))
  restored = Model.restore(JSON.stringify(Model.snapshot(paused, s(200), 1000)), config(), 7, 1000)
  assert.equal(Model.status(restored, 7).enabled, false)
  assert.equal(Model.status(restored, 7).remaining_seconds, 1700)

  const deferred = Model.createTimer(config(), 0)
  Model.startBreak(deferred, "long_break", 0)
  Model.snooze(deferred, 5, s(5))
  restored = Model.restore(JSON.stringify(Model.snapshot(deferred, s(5), 1000)), config(), 0, 1000)
  assert.equal(Model.status(restored, 0).next_break, "long_break")
})

test("old or damaged saved state starts fresh", () => {
  const t = Model.createTimer(config(), 0)
  const good = Model.snapshot(t, 0, 1000000)
  const text = JSON.stringify(good)
  assert.equal(Model.restore(text, config(), 0, 1000000 + s(121)), null, "too old")
  assert.equal(Model.restore(text, config(), 0, 1), null, "from the future")
  assert.notEqual(Model.restore(text, config(), 0, 1000000 + s(120)), null)
  for (const damaged of [
    "", "not json", "null", "3",
    JSON.stringify({ ...good, phase: "nap" }),
    JSON.stringify({ ...good, enabled: "yes" }),
    JSON.stringify({ ...good, remaining: -1 }),
    JSON.stringify({ ...good, remaining: "1" }),
    JSON.stringify({ ...good, paused: null }),
    JSON.stringify({ ...good, completed: null }),
    JSON.stringify({ ...good, total: null }),
    JSON.stringify({ ...good, saved_at: null }),
    JSON.stringify({ ...good, pending_break: "work" })
  ]) {
    assert.equal(Model.restore(damaged, config(), 0, 1000000), null, damaged)
  }
})

test("durations accept units and reject bare numbers", () => {
  assert.equal(Model.parseDuration("30s"), s(30))
  assert.equal(Model.parseDuration("20m"), s(1200))
  assert.equal(Model.parseDuration("1h 30m"), s(5400))
  assert.equal(Model.parseDuration("2 hours"), s(7200))
  for (const bad of ["30", "-1s", "", "m", "5 parsecs", "toString", "1.5h"]) {
    assert.equal(Model.parseDuration(bad), null, bad)
  }
})

test("the configuration inherits defaults and rejects anything invalid", () => {
  assert.equal(Model.parseConfig("").config.work_duration, s(1800))
  assert.equal(Model.parseConfig(null).config.work_duration, s(1800))
  const { config: c } = Model.parseConfig("---\n# comment\nwork_duration: 20m  # short\nlong_break_every: 0\nshort_break: \"45s\"\r\n")
  assert.equal(c.work_duration, s(1200))
  assert.equal(c.short_break, s(45))
  assert.equal(c.long_break, s(180))
  assert.equal(c.long_break_every, 0)
  for (const invalid of [
    "short_break: 0s",
    "long_break: -1s",
    "work_duration: 8days",
    "work_duraton: 20m",
    "short_break: 30",
    "short_break:",
    "long_break_every: 1.5",
    "long_break_every: 4m",
    "warning_before: 8days",
    "warning_duration: 61s",
    "work_duration: 20m\nwork_duration: 30m",
    "constructor: 1s",
    "- work_duration: 20m"
  ]) {
    assert.ok(Model.parseConfig(invalid).error, invalid)
  }
})

test("the example configuration is valid", () => {
  const fs = require("node:fs")
  const path = require("node:path")
  const text = fs.readFileSync(path.join(__dirname, "../config.example.yaml"), "utf8")
  assert.deepEqual(Model.parseConfig(text), { config: Model.defaultConfig() })
})
