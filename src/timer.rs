use crate::config::Config;
use serde::Serialize;
use std::time::{Duration, Instant};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Work,
    ShortBreak,
    LongBreak,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Status {
    pub enabled: bool,
    pub phase: Phase,
    pub remaining_seconds: u64,
    pub label: String,
    pub completed_short_breaks: u32,
    pub next_break: Phase,
    pub total_seconds: u64,
    pub warning: bool,
    pub skip_wait_seconds: u64,
    pub skip_allowed: bool,
}
pub struct Timer {
    pub config: Config,
    phase: Phase,
    deadline: Instant,
    enabled: bool,
    paused: Duration,
    completed: u32,
    total: Duration,
    pending_break: Option<Phase>,
}
impl Timer {
    pub fn new(config: Config, now: Instant) -> Self {
        let total = config.work_duration;
        Self {
            config,
            phase: Phase::Work,
            deadline: now + total,
            enabled: true,
            paused: total,
            completed: 0,
            total,
            pending_break: None,
        }
    }
    fn next_break(&self) -> Phase {
        if let Some(phase) = self.pending_break {
            return phase;
        }
        if self.config.long_break_every > 0 && self.completed >= self.config.long_break_every - 1 {
            Phase::LongBreak
        } else {
            Phase::ShortBreak
        }
    }
    pub fn tick(&mut self, now: Instant) {
        if !self.enabled || now < self.deadline {
            return;
        }
        if self.phase == Phase::Work {
            self.start_break(self.next_break(), now);
        } else {
            if self.phase == Phase::LongBreak {
                self.completed = 0;
            } else {
                self.completed = self.completed.saturating_add(1);
            }
            self.work(now);
        }
    }
    fn work(&mut self, now: Instant) {
        self.phase = Phase::Work;
        self.pending_break = None;
        self.total = self.config.work_duration;
        self.deadline = now + self.total;
        self.paused = self.total;
    }
    pub fn start_break(&mut self, phase: Phase, now: Instant) {
        self.enabled = true;
        self.pending_break = None;
        self.phase = phase;
        self.total = match phase {
            Phase::ShortBreak => self.config.short_break,
            Phase::LongBreak => self.config.long_break,
            Phase::Work => self.config.work_duration,
        };
        self.deadline = now + self.total;
    }
    pub fn set_enabled(&mut self, enabled: bool, now: Instant) {
        if self.enabled == enabled {
            return;
        }
        if !enabled {
            if self.phase != Phase::Work {
                self.work(now);
            }
            self.paused = self.deadline.saturating_duration_since(now);
        } else {
            self.deadline = now + self.paused;
        }
        self.enabled = enabled;
    }
    pub fn snooze(&mut self, minutes: u64, now: Instant) -> bool {
        if ![1, 5, 15].contains(&minutes) {
            return false;
        }
        let extra = Duration::from_secs(minutes * 60);
        if self.phase == Phase::Work {
            self.deadline += extra;
            self.paused += extra;
            self.total += extra;
        } else {
            if !self.status(now).skip_allowed {
                return false;
            }
            self.pending_break = Some(self.phase);
            self.phase = Phase::Work;
            self.total = extra;
            self.deadline = now + extra;
            self.paused = extra;
        }
        true
    }
    pub fn skip(&mut self, now: Instant) -> bool {
        if !self.status(now).skip_allowed {
            return false;
        }
        self.work(now);
        true
    }
    pub fn reload(&mut self, config: Config, now: Instant) {
        self.config = config;
        self.completed = 0;
        self.work(now);
    }
    pub fn status(&self, now: Instant) -> Status {
        let remaining = if self.enabled {
            self.deadline.saturating_duration_since(now)
        } else {
            self.paused
        };
        let seconds = remaining.as_secs() + u64::from(remaining.subsec_nanos() > 0);
        let elapsed = self.total.saturating_sub(remaining);
        let skip_wait = Duration::from_secs(5).saturating_sub(elapsed);
        let skip_wait_seconds = skip_wait.as_secs() + u64::from(skip_wait.subsec_nanos() > 0);
        let label = if !self.enabled {
            "Off".into()
        } else if seconds > 60 && self.phase == Phase::Work {
            seconds.div_ceil(60).to_string()
        } else {
            seconds.to_string()
        };
        Status {
            enabled: self.enabled,
            phase: self.phase,
            remaining_seconds: seconds,
            label,
            completed_short_breaks: self.completed,
            next_break: self.next_break(),
            total_seconds: self.total.as_secs(),
            skip_wait_seconds,
            skip_allowed: self.enabled && self.phase != Phase::Work && skip_wait.is_zero(),
            warning: self.enabled
                && self.phase == Phase::Work
                && self.total > self.config.warning_before
                && remaining <= self.config.warning_before
                && remaining
                    > self
                        .config
                        .warning_before
                        .saturating_sub(self.config.warning_duration),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fast() -> Config {
        Config {
            work_duration: Duration::from_secs(10),
            short_break: Duration::from_secs(2),
            long_break: Duration::from_secs(5),
            long_break_every: 4,
            ..Config::default()
        }
    }
    #[test]
    fn snooze_adds_time_and_preserves_deferred_break() {
        let now = Instant::now();
        let mut t = Timer::new(Config::default(), now);
        assert!(t.snooze(5, now));
        assert_eq!(t.status(now).remaining_seconds, 2100);
        assert!(t.snooze(1, now));
        assert_eq!(t.status(now).remaining_seconds, 2160);
        assert!(!t.snooze(2, now));
        t.start_break(Phase::LongBreak, now);
        assert!(!t.snooze(5, now));
        let later = now + Duration::from_secs(5);
        assert!(t.snooze(5, later));
        assert_eq!(t.status(later).remaining_seconds, 300);
        assert_eq!(t.status(later).phase, Phase::Work);
        assert_eq!(t.status(later).next_break, Phase::LongBreak);
        t.tick(later + Duration::from_secs(300));
        assert_eq!(
            t.status(later + Duration::from_secs(300)).phase,
            Phase::LongBreak
        );
        assert_eq!(
            t.status(later + Duration::from_secs(300)).skip_wait_seconds,
            5
        );
        t.set_enabled(false, later);
        assert!(t.snooze(15, later));
        assert_eq!(t.status(later).remaining_seconds, 2700);
    }
    #[test]
    fn skip_is_locked_for_five_seconds() {
        let now = Instant::now();
        let mut t = Timer::new(Config::default(), now);
        assert!(!t.skip(now));
        t.start_break(Phase::ShortBreak, now);
        assert_eq!(t.status(now).skip_wait_seconds, 5);
        assert!(!t.skip(now + Duration::from_millis(4999)));
        assert!(t.skip(now + Duration::from_secs(5)));
        assert_eq!(t.status(now).phase, Phase::Work);
        assert_eq!(t.status(now).completed_short_breaks, 0);
    }
    #[test]
    fn warning_disappears_without_moving_deadline() {
        let start = Instant::now();
        let timer = Timer::new(Config::default(), start);
        for (elapsed, expected) in [
            (1739, false),
            (1740, true),
            (1747, true),
            (1748, false),
            (1799, false),
        ] {
            assert_eq!(
                timer.status(start + Duration::from_secs(elapsed)).warning,
                expected
            );
        }
    }
    #[test]
    fn countdown_boundary() {
        let start = Instant::now();
        let timer = Timer::new(Config::default(), start);
        for (elapsed, label) in [
            (0, "30"),
            (60, "29"),
            (1739, "2"),
            (1740, "60"),
            (1741, "59"),
        ] {
            assert_eq!(
                timer.status(start + Duration::from_secs(elapsed)).label,
                label
            );
        }
    }
    #[test]
    fn schedule_and_restart() {
        let mut now = Instant::now();
        let mut t = Timer::new(fast(), now);
        for expected in [
            Phase::ShortBreak,
            Phase::ShortBreak,
            Phase::ShortBreak,
            Phase::LongBreak,
            Phase::ShortBreak,
        ] {
            now += Duration::from_secs(10);
            t.tick(now);
            assert_eq!(t.status(now).phase, expected);
            now += if expected == Phase::LongBreak {
                Duration::from_secs(5)
            } else {
                Duration::from_secs(2)
            };
            t.tick(now);
            assert_eq!(t.status(now).phase, Phase::Work);
            assert_eq!(t.status(now).remaining_seconds, 10);
        }
    }
    #[test]
    fn pause_resume_and_disable_break() {
        let now = Instant::now();
        let mut t = Timer::new(fast(), now);
        t.set_enabled(false, now + Duration::from_secs(3));
        t.tick(now + Duration::from_secs(100));
        assert_eq!(t.status(now).remaining_seconds, 7);
        t.set_enabled(true, now + Duration::from_secs(100));
        assert_eq!(
            t.status(now + Duration::from_secs(100)).remaining_seconds,
            7
        );
        t.start_break(Phase::LongBreak, now);
        t.set_enabled(false, now);
        assert_eq!(t.status(now).phase, Phase::Work);
        assert_eq!(t.status(now).completed_short_breaks, 0);
    }
    #[test]
    fn skipped_breaks_do_not_count_and_late_ticks_do_not_skip_overlay() {
        let now = Instant::now();
        let mut t = Timer::new(fast(), now);
        t.tick(now + Duration::from_secs(1000));
        assert_eq!(
            t.status(now + Duration::from_secs(1000)).remaining_seconds,
            2
        );
        assert!(!t.skip(now));
        assert_eq!(t.status(now).completed_short_breaks, 0);
        t.config.long_break_every = 0;
        for _ in 0..5 {
            t.start_break(Phase::ShortBreak, now);
            t.tick(now + Duration::from_secs(2));
        }
        assert_eq!(t.status(now).next_break, Phase::ShortBreak);
        t.reload(fast(), now);
        assert_eq!(t.status(now).completed_short_breaks, 0);
    }
}
