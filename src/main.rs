mod config;
mod timer;

use anyhow::{Context, Result, bail};
use clap::{Parser, Subcommand};
use config::Config;
use fs2::FileExt;
use std::{
    fs::{self, OpenOptions},
    io::{BufRead, BufReader, Write},
    os::unix::{
        fs::{DirBuilderExt, PermissionsExt},
        net::{UnixListener, UnixStream},
    },
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};
use timer::{Phase, Timer};

#[derive(Parser)]
#[command(version, about = "Eye-break reminders for Omarchy / Hyprland")]
struct Cli {
    /// YAML configuration (used by run; reload rereads this same file)
    #[arg(long, global = true)]
    config: Option<PathBuf>,
    #[command(subcommand)]
    command: Option<Action>,
}
#[derive(Subcommand)]
enum Action {
    /// Start the timer and Wayland overlay (default when no command is given)
    Run {
        /// Run only the timer, without a graphical frontend
        #[arg(long)]
        headless: bool,
        /// Directory containing shell.qml (development / custom installation)
        #[arg(long)]
        ui: Option<PathBuf>,
    },
    /// Print the current state as JSON
    Status,
    /// Stream one JSON state per line when state changes
    Watch,
    /// Take a short break now
    ShortBreak,
    /// Take a long break now
    LongBreak,
    /// Disable reminders; dismisses an active break
    Disable,
    /// Resume the paused work timer
    Enable,
    /// Toggle reminders
    Toggle,
    /// End the current break and start a fresh work session
    Skip,
    /// Validate and reload YAML, starting a fresh work session
    Reload,
    /// Add 1, 5 or 15 minutes to work time, or defer the current break
    Snooze {
        #[arg(value_parser = ["1", "5", "15"])]
        minutes: String,
    },
    /// Stop the app and its overlay
    Quit,
}

fn runtime_dir() -> Result<PathBuf> {
    let base = PathBuf::from(
        std::env::var_os("XDG_RUNTIME_DIR")
            .context("XDG_RUNTIME_DIR is not set; run inside your desktop session")?,
    );
    let dir = base.join("look-away");
    match fs::DirBuilder::new().mode(0o700).create(&dir) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
            let meta = fs::symlink_metadata(&dir)?;
            if !meta.is_dir() || meta.permissions().mode() & 0o077 != 0 {
                bail!(
                    "Runtime directory must be a private directory: {}",
                    dir.display()
                );
            }
        }
        Err(e) => return Err(e.into()),
    }
    Ok(dir)
}
fn client(request: &str) -> Result<()> {
    let mut socket = UnixStream::connect(runtime_dir()?.join("control.sock"))
        .context("Look Away is not running. Start it with: look-away run")?;
    socket.set_read_timeout(if request == "watch" {
        None
    } else {
        Some(Duration::from_secs(3))
    })?;
    writeln!(socket, "{request}")?;
    let mut lines = BufReader::new(socket).lines();
    if request == "watch" {
        for line in lines {
            println!("{}", line?);
            std::io::stdout().flush()?;
        }
    } else {
        let line = lines
            .next()
            .context("Daemon disconnected before replying")??;
        let value: serde_json::Value = serde_json::from_str(&line)?;
        if let Some(error) = value.get("error").and_then(|v| v.as_str()) {
            bail!("{error}");
        }
        println!("{line}");
    }
    Ok(())
}
struct Frontend(Option<Child>);
impl Drop for Frontend {
    fn drop(&mut self) {
        if let Some(child) = &mut self.0 {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
struct SocketPath(PathBuf);
impl Drop for SocketPath {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.0);
    }
}
fn ui_path(override_path: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(path) = override_path {
        return Ok(path);
    }
    // An installed binary prefers its matching installed frontend.
    let exe = std::env::current_exe()?;
    if let Some(prefix) = exe.parent().and_then(Path::parent) {
        let installed = prefix.join("share/look-away/ui");
        if installed.join("shell.qml").is_file() {
            return Ok(installed);
        }
    }
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("ui");
    if source.join("shell.qml").is_file() {
        return Ok(source);
    }
    bail!("Cannot find shell.qml; use look-away run --ui /path/to/ui")
}
fn serve(config_path: PathBuf, headless: bool, ui: Option<PathBuf>) -> Result<()> {
    let config =
        Config::load(&config_path).with_context(|| format!("Reading {}", config_path.display()))?;
    let dir = runtime_dir()?;
    let lock = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(dir.join("daemon.lock"))?;
    lock.try_lock_exclusive()
        .context("Look Away is already running")?;
    let path = dir.join("control.sock");
    if path.exists() {
        fs::remove_file(&path)?;
    }
    let listener = UnixListener::bind(&path)?;
    let _cleanup = SocketPath(path.clone());
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
    listener.set_nonblocking(true)?;
    let stopped = Arc::new(AtomicBool::new(false));
    for signal in [signal_hook::consts::SIGTERM, signal_hook::consts::SIGINT] {
        signal_hook::flag::register(signal, Arc::clone(&stopped))?;
    }
    let mut frontend = Frontend(if headless {
        None
    } else {
        Some(
            Command::new("quickshell")
                .arg("-p")
                .arg(ui_path(ui)?)
                .env("LOOK_AWAY_BIN", std::env::current_exe()?)
                .stdin(Stdio::null())
                .spawn()
                .context("Cannot launch quickshell; install it or use --headless")?,
        )
    });
    let mut timer = Timer::new(config, Instant::now());
    let mut watchers: Vec<UnixStream> = Vec::new();
    let mut previous = String::new();
    eprintln!("Look Away started; config: {}", config_path.display());
    while !stopped.load(Ordering::Relaxed) {
        if let Some(child) = &mut frontend.0
            && let Some(status) = child.try_wait()?
        {
            bail!("Quickshell frontend exited ({status}); stopping reminders");
        }
        let now = Instant::now();
        timer.tick(now);
        // Bounded accepts keep UI updates timely even if clients connect repeatedly.
        for _ in 0..16 {
            let (mut socket, _) = match listener.accept() {
                Ok(connection) => connection,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(e) => return Err(e.into()),
            };
            socket.set_read_timeout(Some(Duration::from_millis(100)))?;
            socket.set_write_timeout(Some(Duration::from_millis(50)))?;
            let mut request = String::new();
            // Limit the protocol line to avoid unbounded allocation.
            if std::io::Read::take(BufReader::new(&socket), 1024)
                .read_line(&mut request)
                .is_err()
            {
                continue;
            }
            let now = Instant::now();
            let result: Result<()> = match request.trim() {
                "watch" => {
                    if writeln!(socket, "{}", serde_json::to_string(&timer.status(now))?).is_ok() {
                        watchers.push(socket);
                    }
                    continue;
                }
                "status" => Ok(()),
                cmd if cmd.starts_with("snooze ") => match cmd[7..].parse::<u64>() {
                    Ok(minutes) if timer.snooze(minutes, now) => Ok(()),
                    _ => Err(anyhow::anyhow!(
                        "Choose 1, 5 or 15 minutes. During breaks, wait five seconds first."
                    )),
                },
                "short-break" => {
                    timer.start_break(Phase::ShortBreak, now);
                    Ok(())
                }
                "long-break" => {
                    timer.start_break(Phase::LongBreak, now);
                    Ok(())
                }
                "disable" => {
                    timer.set_enabled(false, now);
                    Ok(())
                }
                "enable" => {
                    timer.set_enabled(true, now);
                    Ok(())
                }
                "toggle" => {
                    timer.set_enabled(!timer.status(now).enabled, now);
                    Ok(())
                }
                "skip" => {
                    if timer.skip(now) {
                        Ok(())
                    } else {
                        Err(anyhow::anyhow!(
                            "Skip becomes available after five seconds of a break"
                        ))
                    }
                }
                "reload" => Config::load(&config_path).map(|c| timer.reload(c, now)),
                "quit" => {
                    stopped.store(true, Ordering::Relaxed);
                    Ok(())
                }
                _ => Err(anyhow::anyhow!("Unknown command")),
            };
            let response = match result {
                Ok(()) => serde_json::to_string(&timer.status(now))?,
                Err(e) => serde_json::json!({"error": e.to_string()}).to_string(),
            };
            let _ = writeln!(socket, "{response}");
        }
        let current = serde_json::to_string(&timer.status(Instant::now()))?;
        if previous != current {
            watchers.retain_mut(|socket| writeln!(socket, "{current}").is_ok());
            previous = current;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    Ok(())
}
fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command.unwrap_or(Action::Run {
        headless: false,
        ui: None,
    }) {
        Action::Run { headless, ui } => serve(
            cli.config.map(Ok).unwrap_or_else(Config::default_path)?,
            headless,
            ui,
        ),
        Action::Snooze { minutes } => client(&format!("snooze {minutes}")),
        command => client(match command {
            Action::Status => "status",
            Action::Watch => "watch",
            Action::ShortBreak => "short-break",
            Action::LongBreak => "long-break",
            Action::Disable => "disable",
            Action::Enable => "enable",
            Action::Toggle => "toggle",
            Action::Skip => "skip",
            Action::Reload => "reload",
            Action::Quit => "quit",
            Action::Run { .. } | Action::Snooze { .. } => unreachable!(),
        }),
    }
}
