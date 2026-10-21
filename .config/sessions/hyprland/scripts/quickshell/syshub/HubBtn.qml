import QtQuick

Rectangle {
    id: b
    property var hub: null
    property string label: ""
    property color accent: hub.mauve
    property bool solid: false
    signal clicked()
    implicitWidth: lt.width + hub.s(30)
    height: hub.s(34)
    radius: hub.s(9)
    color: solid ? (ma.containsMouse ? Qt.alpha(accent, 0.85) : accent)
                 : (ma.containsMouse ? Qt.alpha(accent, 0.26) : Qt.alpha(accent, 0.10))
    border.width: 1
    border.color: accent
    opacity: enabled ? 1 : 0.35
    Behavior on color { ColorAnimation { duration: 140 } }
    Text {
        id: lt
        anchors.centerIn: parent
        text: b.label
        color: b.solid ? b.hub.crust : b.accent
        font.family: b.hub.mono; font.pixelSize: b.hub.s(10); font.bold: true; font.letterSpacing: b.hub.s(1)
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
}
