import QtQuick

Canvas {
    id: root
    property color ink: "#ffffff"
    implicitWidth: 40
    implicitHeight: 28
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        let c = getContext("2d")
        c.reset()
        c.scale(width / 40, height / 28)
        c.strokeStyle = ink
        c.lineWidth = 2.4
        c.lineCap = "round"
        c.beginPath()
        c.moveTo(3, 13)
        c.bezierCurveTo(11, 2, 29, 2, 37, 13)
        c.bezierCurveTo(29, 25, 11, 25, 3, 13)
        c.stroke()
        c.beginPath()
        c.arc(20, 13, 5, 0, Math.PI * 2)
        c.stroke()
    }
}
