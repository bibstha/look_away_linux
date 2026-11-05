import QtQuick

Rectangle {
    id: root
    property string text: ""
    property string detail: ""
    property bool primary: false
    signal clicked()
    implicitHeight: 44
    implicitWidth: 240
    radius: 12
    color: mouse.pressed ? "#51405e" : mouse.containsMouse ? "#3a3349" : primary ? "#393047" : "#292633"
    border.color: "#55ffffff"
    opacity: enabled ? 1 : 0.72
    activeFocusOnTab: true
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()
    border.width: activeFocus ? 2 : 1
    Text {
        anchors.left: parent.left; anchors.leftMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold
        color: "#fff9fc"
    }
    Text {
        anchors.right: parent.right; anchors.rightMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        text: root.detail
        font.family: "Inter"; font.pixelSize: 14; font.weight: Font.DemiBold
        color: "#e0d5e8"
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    Behavior on color { ColorAnimation { duration: 120 } }
}
