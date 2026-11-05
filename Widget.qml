import QtQuick
import Quickshell
import qs.Ui as Ui
import qs.Commons as Commons

Item {
    id: root
    property var bar: null
    property string moduleName: "bibstha.look-away"
    property var settings: ({})
    property bool opened: false
    readonly property bool vertical: bar ? bar.vertical : false
    implicitWidth: vertical ? 28 : pill.width + 12
    implicitHeight: bar ? bar.barSize : 30
    function open() { opened = true }
    function close() { opened = false }
    // One service per shell: every bar's widget reads the same timer.
    readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
        ? bar.shell.serviceFor(moduleName) : null
    readonly property var offline: ({
        online: false,
        breaking: false,
        error: "",
        state: { enabled: false, phase: "work", remaining_seconds: 0, total_seconds: 1, label: "—", warning: false, skip_allowed: false, skip_wait_seconds: 0, next_break: "short_break" },
        act: function() {},
        clock: function() { return "--:--" }
    })
    readonly property var appState: service || offline
    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: root.vertical ? 26 : label.implicitWidth + 34
        height: 24; radius: 8
        color: mouse.containsMouse || root.opened ? Commons.Style.hoverFillFor(Commons.Color.bar.text, Commons.Color.accent) : appState.state.warning ? Commons.Style.selectedFillFor(Commons.Color.bar.text, Commons.Color.accent) : "transparent"
        Eye {
            anchors.left: parent.left; anchors.leftMargin: 7
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 14
            ink: !appState.online || !appState.state.enabled ? Commons.Color.muted : Commons.Color.bar.text
        }
        Text {
            id: label
            anchors.left: parent.left; anchors.leftMargin: 31
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical
            text: appState.online ? appState.state.label : "—"
            color: !appState.online || !appState.state.enabled ? Commons.Color.muted : Commons.Color.bar.text
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.body; font.weight: Font.Medium
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.RightButton) appState.act("toggle")
            else root.opened = !root.opened
        }
    }
    Ui.PopupCard {
        id: popup
        anchorItem: root
        bar: root.bar
        owner: root
        open: root.opened
        contentWidth: Commons.Style.space(360)
        contentHeight: menu.implicitHeight + verticalContentInset
        Column {
            id: menu
            width: parent.width
            spacing: Commons.Style.space(12)
            Ui.PanelHero {
                title: "LOOK AWAY"
                meta: !appState.online ? "Offline" : !appState.state.enabled ? "Reminders paused" : appState.breaking ? "Taking a break" : "Eye-break reminders"
                foreground: Commons.Color.popups.text
                iconComponent: Component {
                    Eye {
                        width: Commons.Style.space(32)
                        height: Commons.Style.space(24)
                        ink: Commons.Color.popups.text
                    }
                }
            }
            Ui.PanelSeparator { foreground: Commons.Color.popups.text }
            Ui.PanelSectionHeader {
                text: appState.breaking ? "BREAK REMAINING" : "NEXT " + (appState.state.next_break === "long_break" ? "LONG" : "SHORT") + " BREAK"
                foreground: Commons.Color.popups.text
            }
            Text {
                text: !appState.online ? "--:--" : !appState.state.enabled ? "PAUSED" : appState.clock(appState.state.remaining_seconds)
                color: Commons.Color.popups.text
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.space(30)
                font.bold: true
            }
            Ui.PanelSeparator { foreground: Commons.Color.popups.text }
            Ui.PanelSectionHeader { text: "TAKE A BREAK"; foreground: Commons.Color.popups.text }
            Ui.Button {
                width: parent.width
                text: "Take a short break"
                leftAlign: true; bordered: true; focusable: true
                foreground: Commons.Color.popups.text
                enabled: appState.online
                onClicked: { appState.act("short-break"); root.close() }
            }
            Ui.Button {
                width: parent.width
                text: "Take a long break"
                leftAlign: true; bordered: true; focusable: true
                foreground: Commons.Color.popups.text
                enabled: appState.online
                onClicked: { appState.act("long-break"); root.close() }
            }
            Ui.PanelSectionHeader { text: "POSTPONE BREAK"; foreground: Commons.Color.popups.text }
            Row {
                width: parent.width
                spacing: Commons.Style.space(6)
                Repeater {
                    model: [1, 5, 15]
                    delegate: Ui.Button {
                        required property int modelData
                        width: (menu.width - Commons.Style.space(12)) / 3
                        text: "+" + modelData + " min"
                        bordered: true; focusable: true
                        foreground: Commons.Color.popups.text
                        enabled: appState.online && (!appState.breaking || appState.state.skip_allowed === true)
                        onClicked: { appState.act("snooze " + modelData); root.close() }
                    }
                }
            }
            Ui.PanelSeparator { foreground: Commons.Color.popups.text }
            Ui.Button {
                width: parent.width
                text: appState.state.enabled ? "Disable reminders" : "Enable reminders"
                selected: !appState.state.enabled
                leftAlign: true; bordered: true; focusable: true
                foreground: Commons.Color.popups.text
                enabled: appState.online
                onClicked: appState.act("toggle")
            }
            Ui.Button {
                width: parent.width
                text: "Reload configuration"
                leftAlign: true; bordered: true; focusable: true
                foreground: Commons.Color.popups.text
                enabled: appState.online
                onClicked: appState.act("reload")
            }
            Text {
                width: parent.width
                visible: !appState.online || appState.error !== ""
                text: appState.online ? appState.error : "The Look Away service is not loaded. Try: omarchy restart shell"
                wrapMode: Text.Wrap
                color: Commons.Color.urgent
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.font.body
            }
        }
    }
}
