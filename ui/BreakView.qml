import QtQuick

Item {
    id: root
    required property var session
    readonly property bool longBreak: session.state.phase === "long_break"
    Canvas {
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let c = getContext("2d")
            c.reset()
            let base = c.createLinearGradient(0, 0, width, height)
            base.addColorStop(0, "#211a37")
            base.addColorStop(0.45, "#51304f")
            base.addColorStop(1, "#b36662")
            c.fillStyle = base; c.fillRect(0, 0, width, height)
            let glow = c.createRadialGradient(width * 0.85, height * 0.9, 0, width * 0.85, height * 0.9, width * 0.8)
            glow.addColorStop(0, "#eab88b")
            glow.addColorStop(0.45, "#75d6867e")
            glow.addColorStop(1, "#00c9758d")
            c.fillStyle = glow; c.fillRect(0, 0, width, height)
            let purple = c.createRadialGradient(width * 0.05, height * 0.2, 0, width * 0.05, height * 0.2, width * 0.65)
            purple.addColorStop(0, "#806591")
            purple.addColorStop(1, "#00584578")
            c.fillStyle = purple; c.fillRect(0, 0, width, height)
        }
    }
    Row {
        anchors.left: parent.left; anchors.top: parent.top
        anchors.margins: 40
        spacing: 10
        Eye { width: 26; height: 20; opacity: 0.8 }
        Text { text: "look away"; color: "#e9dfe8"; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.DemiBold }
    }
    Column {
        anchors.centerIn: parent
        spacing: 24
        width: Math.min(parent.width - 40, 600)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.longBreak ? "A LITTLE TIME FOR YOURSELF" : "A MOMENT FOR YOUR EYES"
            color: "#fff1f8"
            font.family: "Inter"; font.pixelSize: 14; font.letterSpacing: 3; font.weight: Font.Medium
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.longBreak ? "Step away.\nCome back refreshed." : "Look away.\nLet your eyes wander."
            color: "#fff9f3"
            font.family: "Inter Display"; font.pixelSize: Math.min(58, root.width / 13); font.weight: Font.DemiBold
            lineHeight: 1.05
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.longBreak ? "Stand up, stretch, and give yourself a little space." : "Find something about 6 metres away.\nSoften your focus. Remember to blink."
            color: "#fff1f8"
            font.family: "Inter"; font.pixelSize: 18; lineHeight: 1.5; font.weight: Font.Medium
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 156; height: 156
            Canvas {
                id: ring
                anchors.fill: parent
                property real progress: Math.min(1, root.session.state.remaining_seconds / Math.max(1, root.session.state.total_seconds))
                onProgressChanged: requestPaint()
                onPaint: {
                    let c = getContext("2d"); c.reset()
                    c.lineWidth = 2; c.strokeStyle = "#30ffffff"
                    c.beginPath(); c.arc(78, 78, 74, 0, 2 * Math.PI); c.stroke()
                    c.strokeStyle = "#f5ddd7"; c.lineCap = "round"
                    c.beginPath(); c.arc(78, 78, 74, -Math.PI / 2, -Math.PI / 2 + progress * Math.PI * 2); c.stroke()
                }
            }
            Column {
                anchors.centerIn: parent
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.session.state.remaining_seconds > 60 ? root.session.clock(root.session.state.remaining_seconds) : root.session.state.remaining_seconds
                    font.family: "Inter Display"; font.pixelSize: 46; font.weight: Font.DemiBold
                    color: "#fff9f3"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.session.state.remaining_seconds > 60 ? "REMAINING" : "SECONDS"
                    font.family: "Inter"; font.pixelSize: 11; font.letterSpacing: 2; font.weight: Font.Medium
                    color: "#fff1f8"
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Nothing to do. Just a little room to breathe."
            font.family: "Inter"; font.pixelSize: 14; font.weight: Font.Medium
            color: "#fff1f8"
        }
    }
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 32
        spacing: 12
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: [1, 5, 15]
                delegate: ActionButton {
                    required property int modelData
                    width: 124; implicitHeight: 40
                    text: "Wait " + modelData + " min"
                    enabled: root.session.state.skip_allowed === true
                    onClicked: root.session.act("snooze " + modelData)
                }
            }
        }
        Rectangle {
            id: skipButton
            anchors.horizontalCenter: parent.horizontalCenter
            width: 194; height: 44; radius: 20
            readonly property bool ready: root.session.state.skip_allowed === true
            color: skip.containsMouse && ready ? "#25ffffff" : "#12ffffff"
            border.width: 1; border.color: "#30ffffff"
            opacity: ready ? 1 : 0.9
            Row {
                anchors.centerIn: parent; spacing: 9
                Canvas {
                    id: unlockRing
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    property real progress: 1 - Math.min(5, root.session.state.skip_wait_seconds || 0) / 5
                    Behavior on progress { NumberAnimation { duration: 250 } }
                    onProgressChanged: requestPaint()
                    onPaint: {
                        let c = getContext("2d"); c.reset()
                        c.lineWidth = 1.8; c.strokeStyle = "#35ffffff"
                        c.beginPath(); c.arc(9, 9, 7, 0, Math.PI * 2); c.stroke()
                        c.strokeStyle = "#f4e3ef"; c.lineCap = "round"
                        c.beginPath(); c.arc(9, 9, 7, -Math.PI / 2, -Math.PI / 2 + progress * Math.PI * 2); c.stroke()
                        if (skipButton.ready) {
                            c.beginPath(); c.moveTo(5.5, 9); c.lineTo(8, 11.5); c.lineTo(12, 6.5); c.stroke()
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: skipButton.ready ? "Skip this break" : "Skip in " + root.session.state.skip_wait_seconds + "s"
                    color: "#fff1f8"; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.Medium
                }
            }
            MouseArea {
                id: skip
                anchors.fill: parent; hoverEnabled: true
                enabled: skipButton.ready
                cursorShape: Qt.PointingHandCursor
                onClicked: root.session.act("skip")
            }
        }
        Text {
            text: "Your next work session starts automatically."
            color: "#fff1f8"; font.family: "Inter"; font.pixelSize: 14; font.weight: Font.Medium
        }
    }
}
