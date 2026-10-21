import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

Item {
    id: pg
    property var hub: null
    property bool active: false
    property bool loaded: false
    property bool confirmUp: false
    property var items: []
    property var news: []
    property int repoN: 0
    property int aurN: 0
    function s(v) { return hub.s(v) }

    function reload() {
        if (updProc.running) return
        loaded = true
        updProc.running = true
        if (!newsProc.running) newsProc.running = true
    }
    onActiveChanged: if (active && !loaded) reload()
    Connections {
        target: pg.hub
        function onJobTickChanged() { if (pg.loaded) pg.reload() }
    }
    Timer { id: confirmT; interval: 4000; onTriggered: pg.confirmUp = false }

    Process {
        id: updProc
        command: ["python3", pg.hub.script, "updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                var a
                try { a = JSON.parse(text) } catch (e) { return }
                a.sort(function (x, y) { return (y.hot ? 1 : 0) - (x.hot ? 1 : 0) || x.name.localeCompare(y.name) })
                var r = 0, u = 0
                for (var i = 0; i < a.length; i++) { if (a[i].src === "aur") u++; else r++ }
                pg.repoN = r; pg.aurN = u; pg.items = a
            }
        }
    }
    Process {
        id: newsProc
        command: ["python3", pg.hub.script, "news"]
        stdout: StdioCollector { onStreamFinished: { try { pg.news = JSON.parse(text) } catch (e) {} } }
    }

    RowLayout {
        anchors.fill: parent
        spacing: pg.s(20)

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: pg.s(14)

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: pg.s(128)
                radius: pg.s(14)
                color: Qt.alpha(pg.hub.surface0, 0.55)
                border.width: 1
                border.color: Qt.alpha(pg.hub.pink, 0.4)
                Rectangle { width: pg.s(3); height: parent.height * 0.5; radius: 2; anchors.verticalCenter: parent.verticalCenter; color: pg.hub.pink }
                Text {
                    id: bigN
                    x: pg.s(24); y: pg.s(12)
                    text: updProc.running ? "..." : pg.items.length
                    color: pg.items.length > 50 ? pg.hub.peach : pg.hub.text
                    font.family: pg.hub.mono; font.pixelSize: pg.s(46); font.bold: true
                }
                Column {
                    x: pg.s(24) + bigN.width + pg.s(18); y: pg.s(26)
                    spacing: pg.s(4)
                    Text { text: "PENDING UPDATES"; color: pg.hub.text
                           font.family: pg.hub.mono; font.pixelSize: pg.s(13); font.bold: true; font.letterSpacing: pg.s(2) }
                    Text { text: pg.repoN + " REPO  /  " + pg.aurN + " AUR  //  FULL UPGRADES ONLY"; color: pg.hub.subtext0
                           font.family: pg.hub.mono; font.pixelSize: pg.s(9); font.letterSpacing: pg.s(1) }
                }
                Row {
                    anchors { left: parent.left; leftMargin: pg.s(24); bottom: parent.bottom; bottomMargin: pg.s(14) }
                    spacing: pg.s(10)
                    HubBtn {
                        hub: pg.hub; label: "RECHECK"; accent: pg.hub.blue
                        enabled: !updProc.running
                        onClicked: pg.reload()
                    }
                    HubBtn {
                        hub: pg.hub; label: "TERMINAL (YAY)"; accent: pg.hub.peach
                        onClicked: Quickshell.execDetached(["kitty", "-e", "bash", "-c", "yay -Syu; echo; read -rp 'Press enter to close' _"])
                    }
                    HubBtn {
                        hub: pg.hub
                        label: pg.confirmUp ? "CONFIRM UPGRADE" : "FULL UPGRADE"
                        accent: pg.confirmUp ? pg.hub.red : pg.hub.pink
                        solid: pg.confirmUp
                        enabled: pg.hub.fixStatus !== "running" && pg.repoN > 0
                        onClicked: {
                            if (pg.confirmUp) { pg.confirmUp = false; pg.hub.startJob("upgrade", []) }
                            else { pg.confirmUp = true; confirmT.restart() }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: pg.s(14)
                color: Qt.alpha(pg.hub.surface0, 0.4)
                border.width: 1
                border.color: Qt.alpha(pg.hub.mauve, 0.25)
                clip: true
                ListView {
                    anchors.fill: parent
                    anchors.margins: pg.s(8)
                    clip: true
                    spacing: pg.s(4)
                    model: pg.items
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: ur
                        required property var modelData
                        width: ListView.view.width
                        height: pg.s(40)
                        radius: pg.s(8)
                        color: ur.modelData.hot ? Qt.alpha(pg.hub.peach, 0.08) : "transparent"
                        Text {
                            x: pg.s(14); anchors.verticalCenter: parent.verticalCenter
                            width: pg.s(210); elide: Text.ElideRight
                            text: ur.modelData.name; color: pg.hub.text
                            font.family: pg.hub.mono; font.pixelSize: pg.s(12); font.bold: true
                        }
                        Row {
                            x: pg.s(236); anchors.verticalCenter: parent.verticalCenter
                            spacing: pg.s(8)
                            Text { text: ur.modelData.old; color: pg.hub.subtext0
                                   font.family: pg.hub.mono; font.pixelSize: pg.s(10) }
                            Text { text: "->"; color: pg.hub.overlay0
                                   font.family: pg.hub.mono; font.pixelSize: pg.s(10) }
                            Text { text: ur.modelData.new; color: pg.hub.green
                                   font.family: pg.hub.mono; font.pixelSize: pg.s(10); font.bold: true }
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: pg.s(12); verticalCenter: parent.verticalCenter }
                            spacing: pg.s(6)
                            Rectangle {
                                visible: ur.modelData.hot
                                height: pg.s(16); width: coreT.width + pg.s(12); radius: pg.s(4)
                                color: Qt.alpha(pg.hub.peach, 0.15); border.width: 1; border.color: pg.hub.peach
                                Text { id: coreT; anchors.centerIn: parent; text: "CORE"; color: pg.hub.peach
                                       font.family: pg.hub.mono; font.pixelSize: pg.s(8); font.bold: true }
                            }
                            Rectangle {
                                height: pg.s(16); width: srcT.width + pg.s(12); radius: pg.s(4)
                                color: "transparent"; border.width: 1
                                border.color: ur.modelData.src === "aur" ? pg.hub.peach : pg.hub.blue
                                Text { id: srcT; anchors.centerIn: parent; text: ur.modelData.src.toUpperCase()
                                       color: ur.modelData.src === "aur" ? pg.hub.peach : pg.hub.blue
                                       font.family: pg.hub.mono; font.pixelSize: pg.s(8); font.bold: true }
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    visible: updProc.running || (pg.loaded && pg.items.length === 0)
                    text: updProc.running ? "SYNCING DATABASES..." : "SYSTEM UP TO DATE"
                    color: updProc.running ? pg.hub.pink : pg.hub.green
                    font.family: pg.hub.mono; font.pixelSize: pg.s(14); font.bold: true; font.letterSpacing: pg.s(3)
                    SequentialAnimation on opacity {
                        running: updProc.running; loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: pg.s(320)
            Layout.fillHeight: true
            radius: pg.s(14)
            color: Qt.alpha(pg.hub.surface0, 0.55)
            border.width: 1
            border.color: Qt.alpha(pg.hub.blue, 0.4)
            Text { x: pg.s(18); y: pg.s(14); text: "ARCH NEWS"; color: pg.hub.blue
                   font.family: pg.hub.mono; font.pixelSize: pg.s(10); font.bold: true; font.letterSpacing: pg.s(2) }
            Text { x: pg.s(18); y: pg.s(30); text: "READ BEFORE UPGRADING"; color: pg.hub.subtext0
                   font.family: pg.hub.mono; font.pixelSize: pg.s(8); font.letterSpacing: pg.s(1) }
            Column {
                x: pg.s(12); y: pg.s(58); width: parent.width - pg.s(24)
                spacing: pg.s(8)
                Repeater {
                    model: pg.news
                    delegate: Rectangle {
                        id: nr
                        required property var modelData
                        width: parent.width; height: pg.s(76); radius: pg.s(10)
                        color: nma.containsMouse ? Qt.alpha(pg.hub.blue, 0.16) : Qt.alpha(pg.hub.surface1, 0.35)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            x: pg.s(12); y: pg.s(10); width: parent.width - pg.s(24)
                            text: nr.modelData.title; color: pg.hub.text
                            wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                            font.family: pg.hub.mono; font.pixelSize: pg.s(10); font.bold: true
                        }
                        Text {
                            x: pg.s(12); anchors.bottom: parent.bottom; anchors.bottomMargin: pg.s(8)
                            text: nr.modelData.date; color: pg.hub.subtext0
                            font.family: pg.hub.mono; font.pixelSize: pg.s(9)
                        }
                        MouseArea { id: nma; anchors.fill: parent; hoverEnabled: true
                                    onClicked: Quickshell.execDetached(["xdg-open", nr.modelData.link]) }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: pg.news.length === 0
                text: newsProc.running ? "LOADING..." : "FEED OFFLINE"
                color: pg.hub.overlay0
                font.family: pg.hub.mono; font.pixelSize: pg.s(10); font.letterSpacing: pg.s(2)
            }
        }
    }
}
