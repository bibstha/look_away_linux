use anyhow::{Context, Result, bail};
use serde::Deserialize;
use std::{
    path::{Path, PathBuf},
    time::Duration,
};

#[derive(Clone, Debug, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    #[serde(deserialize_with = "duration")]
    pub work_duration: Duration,
    #[serde(deserialize_with = "duration")]
    pub short_break: Duration,
    #[serde(deserialize_with = "duration")]
    pub long_break: Duration,
    pub long_break_every: u32,
    #[serde(deserialize_with = "duration")]
    pub warning_before: Duration,
    #[serde(deserialize_with = "duration")]
    pub warning_duration: Duration,
}
fn duration<'de, D: serde::Deserializer<'de>>(d: D) -> Result<Duration, D::Error> {
    let s = String::deserialize(d)?;
    humantime::parse_duration(&s).map_err(serde::de::Error::custom)
}
impl Default for Config {
    fn default() -> Self {
        Self {
            work_duration: Duration::from_secs(1800),
            short_break: Duration::from_secs(30),
            long_break: Duration::from_secs(180),
            long_break_every: 4,
            warning_before: Duration::from_secs(60),
            warning_duration: Duration::from_secs(8),
        }
    }
}
impl Config {
    pub fn load(path: &Path) -> Result<Self> {
        let config: Self = match std::fs::read_to_string(path) {
            Ok(text) => serde_yaml_ng::from_str(&text).context("Invalid YAML configuration")?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Self::default(),
            Err(e) => return Err(e).context("Cannot read configuration"),
        };
        for (name, value) in [
            ("work_duration", config.work_duration),
            ("short_break", config.short_break),
            ("long_break", config.long_break),
        ] {
            if value < Duration::from_secs(1) || value > Duration::from_secs(86400 * 7) {
                bail!("{name} must be at least one second and at most 7 days");
            }
        }
        if config.warning_before > Duration::from_secs(86400 * 7)
            || config.warning_duration > Duration::from_secs(60)
        {
            bail!(
                "warning_before must be at most 7 days; warning_duration must be at most 60 seconds"
            );
        }
        Ok(config)
    }
    pub fn default_path() -> Result<PathBuf> {
        let base = std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
            .context("HOME or XDG_CONFIG_HOME must be set")?;
        Ok(base.join("look-away/config.yaml"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn validates_yaml_and_durations() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("config.yaml");
        assert_eq!(Config::load(&path).unwrap().work_duration.as_secs(), 1800);
        for invalid in [
            "short_break: 0s",
            "long_break: -1s",
            "work_duration: 8days",
            "work_duraton: 20m",
            "short_break: 30",
        ] {
            std::fs::write(&path, invalid).unwrap();
            assert!(Config::load(&path).is_err(), "{invalid}");
        }
        std::fs::write(&path, "work_duration: 20m\nlong_break_every: 0").unwrap();
        let c = Config::load(&path).unwrap();
        assert_eq!(c.work_duration.as_secs(), 1200);
        assert_eq!(c.short_break.as_secs(), 30);
        assert_eq!(c.long_break_every, 0);
    }
}
