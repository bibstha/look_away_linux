import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    property string binary: Quickshell.env("LOOK_AWAY_BIN") || (Quickshell.env("HOME") + "/.local/bin/look-away")
    property bool online: false
    property var state: ({ enabled: false, phase: "work", remaining_seconds: 0, total_seconds: 1, label: "—", warning: false, skip_wait_seconds: 5, skip_allowed: false, next_break: "short_break" })
    property string error: ""
    readonly property bool breaking: online && state.enabled && state.phase !== "work"
    readonly property bool starting: online && state.enabled && state.phase === "work" && state.remaining_seconds <= 5
    function act(command) {
        if (action.running) return
        error = ""
        action.command = [binary].concat(command.split(" "))
        action.running = true
    }
    function clock(seconds) {
        return Math.floor(seconds / 60).toString().padStart(2, "0") + ":" + (seconds % 60).toString().padStart(2, "0")
    }
    Process {
        id: stream
        command: [root.binary, "watch"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try { root.state = JSON.parse(data); root.online = true } catch (e) { console.warn("Look Away:", e) }
            }
        }
        onExited: root.online = false
    }
    Timer {
        interval: 2000
        running: !stream.running
        repeat: true
        onTriggered: stream.running = true
    }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text)
                    if (result.error) root.error = result.error
                } catch (e) {}
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) root.error = text.trim()
        }
    }
}
