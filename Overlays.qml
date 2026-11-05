import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The break screen, heads-up and pointer badge, on every connected screen.
Item {
    id: root
    required property var session
    readonly property var appState: session
    property real cursorX: -1000
    property real cursorY: -1000
    Process {
        id: cursor
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { let pos = JSON.parse(text); root.cursorX = pos.x; root.cursorY = pos.y } catch (e) {}
            }
        }
    }
    Timer {
        interval: 100
        running: appState.starting
        triggeredOnStart: true
        repeat: true
        onTriggered: if (!cursor.running) cursor.running = true
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: overlay
            required property var modelData
            screen: modelData
            visible: appState.breaking
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "look-away-break"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "#352440"
            BreakView { anchors.fill: parent; session: appState }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            required property var modelData
            screen: modelData
            visible: appState.online && appState.state.enabled && appState.state.warning && !appState.breaking
            anchors { top: true }
            margins.top: 54
            implicitWidth: 440; implicitHeight: 100
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "look-away-reminder"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {} // Reminder is entirely click-through.
            Rectangle {
                anchors.fill: parent; anchors.margins: 2
                color: "#ee211d32"; radius: 24
                border.width: 1; border.color: "#35d9b3e8"
                Rectangle {
                    x: 20; anchors.verticalCenter: parent.verticalCenter
                    width: 52; height: 52; radius: 18
                    gradient: Gradient { GradientStop { position: 0; color: "#d47aac" } GradientStop { position: 1; color: "#9a709e" } }
                    Eye { anchors.centerIn: parent; width: 30; height: 23 }
                }
                Column {
                    x: 88; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Text { text: "A little pause in " + appState.clock(appState.state.remaining_seconds); color: "#fff5fb"; font.family: "Inter"; font.pixelSize: 17; font.weight: Font.Medium }
                    Text { text: appState.state.next_break === "long_break" ? "Time to stretch and step away, soon." : "Almost time to give your eyes a rest."; color: "#bcb0ce"; font.family: "Inter"; font.pixelSize: 12 ; font.weight: Font.Medium }
                }
            }
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: PanelWindow {
            id: badgeWindow
            required property var modelData
            screen: modelData
            readonly property real localX: root.cursorX - modelData.x
            readonly property real localY: root.cursorY - modelData.y
            visible: appState.starting && localX >= 0 && localY >= 0 && localX < modelData.width && localY < modelData.height
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "look-away-pointer"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            mask: Region {}
            Rectangle {
                x: Math.max(8, Math.min(badgeWindow.width - width - 8, badgeWindow.localX + 20))
                y: Math.max(8, Math.min(badgeWindow.height - height - 8, badgeWindow.localY + 24))
                width: 210; height: 42; radius: 21
                color: "#ed30243e"; border.width: 1; border.color: "#55c99bcd"
                Row {
                    anchors.centerIn: parent; spacing: 9
                    Eye { width: 23; height: 18; anchors.verticalCenter: parent.verticalCenter; ink: "#eebbe2" }
                    Text { text: "Starting break in " + appState.state.remaining_seconds; color: "#f9eaf6"; font.family: "Inter"; font.pixelSize: 13 ; font.weight: Font.Medium }
                }
            }
        }
    }
}
