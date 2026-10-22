import QtQuick

Item {
    id: sb
    property var hub: null
    property var target: null
    property bool shown: true
    width: hub.s(16)
    visible: shown && target !== null && target.contentHeight > target.height + 1
    readonly property real range: target ? Math.max(1, target.contentHeight - target.height) : 1
    readonly property real frac: target ? Math.max(0, Math.min(1, (target.contentY - target.originY) / range)) : 0

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: sb.hub.s(4); height: parent.height; radius: width / 2
        color: sb.hub.surface1; opacity: 0.6
    }
    Rectangle {
        id: handle
        anchors.horizontalCenter: parent.horizontalCenter
        width: ma.pressed || ma.containsMouse ? sb.hub.s(8) : sb.hub.s(5)
        height: Math.max(sb.hub.s(44), sb.target ? sb.target.visibleArea.heightRatio * sb.height : 0)
        y: sb.frac * (sb.height - height)
        radius: width / 2
        color: sb.hub.pink
        opacity: ma.pressed ? 1 : (ma.containsMouse ? 0.95 : 0.7)
        Behavior on width { NumberAnimation { duration: 100 } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        function jump(y) {
            if (!sb.target) return
            var f = (y - handle.height / 2) / Math.max(1, sb.height - handle.height)
            f = Math.max(0, Math.min(1, f))
            sb.target.contentY = sb.target.originY + f * sb.range
        }
        onPressed: function (m) { if (sb.target) sb.target.cancelFlick(); jump(m.y) }
        onPositionChanged: function (m) { if (pressed) jump(m.y) }
    }
}
