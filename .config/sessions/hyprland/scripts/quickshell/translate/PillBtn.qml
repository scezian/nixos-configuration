import QtQuick

Rectangle {
    id: pb
    property var hub: null
    property string label: ""
    signal clicked()

    implicitWidth: pbText.implicitWidth + hub.s(30)
    implicitHeight: hub.s(36)
    radius: hub.s(9)
    color: pbMa.containsMouse ? Qt.alpha(hub.mauve, 0.18) : "transparent"
    border.color: pbMa.containsMouse ? hub.mauve : hub.surface1
    border.width: 1
    scale: pbMa.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: 90 } }

    Text {
        id: pbText
        anchors.centerIn: parent
        text: pb.label
        font.family: "JetBrains Mono"
        font.weight: Font.Bold
        font.pixelSize: hub.s(12)
        color: hub.mauve
    }
    MouseArea { id: pbMa; anchors.fill: parent; hoverEnabled: true; onClicked: pb.clicked() }
}
