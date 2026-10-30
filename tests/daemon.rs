use serde_json::Value;
use std::{
    io::{BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

struct Daemon(Child);
impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn daemon_protocol_reload_single_instance_and_cleanup() {
    let dir = tempfile::tempdir().unwrap();
    let config = dir.path().join("config.yaml");
    std::fs::write(
        &config,
        "work_duration: 2s\nshort_break: 10s\nwarning_before: 1s\nwarning_duration: 1s",
    )
    .unwrap();
    let bin = env!("CARGO_BIN_EXE_look-away");
    let mut daemon = Daemon(
        Command::new(bin)
            .args(["--config", config.to_str().unwrap(), "run", "--headless"])
            .env("XDG_RUNTIME_DIR", dir.path())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap(),
    );
    let socket = dir.path().join("look-away/control.sock");
    let deadline = Instant::now() + Duration::from_secs(5);
    while !socket.exists() {
        assert!(Instant::now() < deadline);
        thread::sleep(Duration::from_millis(10));
    }
    let request = |command: &str| -> Value {
        let mut s = UnixStream::connect(&socket).unwrap();
        s.set_read_timeout(Some(Duration::from_secs(3))).unwrap();
        writeln!(s, "{command}").unwrap();
        let mut line = String::new();
        BufReader::new(s).read_line(&mut line).unwrap();
        serde_json::from_str(&line).unwrap()
    };
    let mut stream = UnixStream::connect(&socket).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(4)))
        .unwrap();
    writeln!(stream, "watch").unwrap();
    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    reader.read_line(&mut line).unwrap();
    assert_eq!(
        serde_json::from_str::<Value>(&line).unwrap()["phase"],
        "work"
    );
    // Watch through a real automatic transition and advance reminder.
    let mut saw_warning = false;
    loop {
        line.clear();
        reader.read_line(&mut line).unwrap();
        let value: Value = serde_json::from_str(&line).unwrap();
        saw_warning |= value["warning"] == true;
        if value["phase"] == "short_break" {
            break;
        }
    }
    assert!(saw_warning);
    assert!(request("skip").get("error").is_some());
    assert_eq!(request("disable")["enabled"], false);
    assert_eq!(request("enable")["phase"], "work");
    assert_eq!(request("long-break")["phase"], "long_break");
    assert_eq!(request("short-break")["phase"], "short_break");
    std::fs::write(&config, "work_duration: typo").unwrap();
    assert!(request("reload").get("error").is_some());
    assert_eq!(request("status")["phase"], "short_break");
    std::fs::write(&config, "work_duration: 10m").unwrap();
    assert_eq!(request("reload")["remaining_seconds"], 600);
    assert_eq!(request("snooze 5")["remaining_seconds"], 900);
    assert_eq!(request("snooze 1")["remaining_seconds"], 960);
    assert!(request("snooze 2").get("error").is_some());
    let duplicate = Command::new(bin)
        .args(["run", "--headless"])
        .env("XDG_RUNTIME_DIR", dir.path())
        .output()
        .unwrap();
    assert!(!duplicate.status.success());
    assert!(String::from_utf8_lossy(&duplicate.stderr).contains("already running"));
    request("quit");
    assert!(daemon.0.wait().unwrap().success());
    assert!(!socket.exists());
}
