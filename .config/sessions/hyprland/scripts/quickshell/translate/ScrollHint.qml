import QtQuick

// Draggable scrollbar + "more below" pill for a Flickable that is a sibling in the same parent.
Item {
    id: sh
    property Flickable flick: null
    property var hub: null
    anchors.fill: flick
    z: 5

    readonly property real maxY: flick ? Math.max(0, flick.contentHeight - flick.height) : 0
    readonly property bool scrollable: maxY > 2
    readonly property bool atEnd: !flick || flick.contentY >= maxY - 2
    visible: !!flick && flick.visible && scrollable

    // scrollbar: wide hit strip, thin visible bar
    Item {
        id: strip
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: sh.hub.s(16)

        readonly property bool hot: stripMa.containsMouse || stripMa.pressed
        readonly property real barW: hot ? sh.hub.s(8) : sh.hub.s(4)
        Behavior on barW { NumberAnimation { duration: 140 } }

        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: sh.hub.s(3)
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: strip.barW
            radius: width / 2
            color: Qt.alpha(sh.hub.surface1, 0.55)
        }
        Rectangle {
            id: thumb
            anchors.right: parent.right
            anchors.rightMargin: sh.hub.s(3)
            width: strip.barW
            radius: width / 2
            height: Math.max(sh.hub.s(36), strip.height * sh.flick.height / Math.max(1, sh.flick.contentHeight))
            y: sh.maxY > 0 ? (strip.height - height) * Math.max(0, Math.min(1, sh.flick.contentY / sh.maxY)) : 0
            color: sh.hub.mauve
            opacity: strip.hot ? 1.0 : 0.7
            Behavior on opacity { NumberAnimation { duration: 140 } }
        }
        MouseArea {
            id: stripMa
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            property real grab: 0
            function scrollTo(my) {
                let range = Math.max(1, strip.height - thumb.height);
                let f = Math.max(0, Math.min(1, (my - grab) / range));
                sh.flick.contentY = f * sh.maxY;
            }
            onPressed: (m) => {
                if (m.y >= thumb.y && m.y <= thumb.y + thumb.height) {
                    grab = m.y - thumb.y;
                } else {
                    grab = thumb.height / 2;
                    scrollTo(m.y);
                }
            }
            onPositionChanged: (m) => { if (pressed) scrollTo(m.y); }
        }
    }

    // "more below" pill
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: sh.hub.s(4)
        width: moreT.implicitWidth + sh.hub.s(24); height: sh.hub.s(24); radius: height / 2
        color: Qt.alpha(sh.hub.base, 0.9)
        border.color: sh.hub.mauve; border.width: 1
        opacity: sh.atEnd ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Text {
            id: moreT
            anchors.centerIn: parent
            text: "\u25be  more"
            font.family: "JetBrains Mono"; font.pixelSize: sh.hub.s(10); color: sh.hub.mauve
        }
        MouseArea { anchors.fill: parent; onClicked: scrollAnim.start() }
    }

    NumberAnimation { id: scrollAnim; target: sh.flick; property: "contentY"; to: sh.maxY; duration: 350; easing.type: Easing.OutCubic }
}
