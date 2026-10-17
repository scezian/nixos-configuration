import QtQuick
import "."
import QtQuick.Layouts

Item {
    id: page
    property var hub: null
    function s(v) { return hub.s(v); }

    readonly property color cText: hub.text
    readonly property color cSub0: hub.subtext0
    readonly property color cSub1: hub.subtext1
    readonly property color cSurf0: hub.surface0
    readonly property color cSurf1: hub.surface1
    readonly property color cMauve: hub.mauve
    readonly property color cGreen: hub.green
    readonly property color cRed: hub.red

    readonly property string statusLabel: hub.status === "loading" ? "Translating" : hub.status === "done" ? "Done" : hub.status === "error" ? "Error" : "Ready"
    readonly property color statusColor: hub.status === "loading" ? cMauve : hub.status === "done" ? cGreen : hub.status === "error" ? cRed : cSub0

    property real pulse: 1.0
    property bool moreLangs: false
    readonly property var chipModel: (moreLangs ? hub.langChips : hub.langChips.slice(0, 8)).concat([{ label: moreLangs ? "Less" : "More\u2026", langs: "__more" }])
    SequentialAnimation on pulse {
        running: page.hub.status === "loading"; loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    Component.onCompleted: srcEdit.text = hub.original
    Connections {
        target: page.hub
        function onOriginalChanged() { srcEdit.text = page.hub.original; }
        function onStatusChanged() { if (page.hub.status === "idle") srcEdit.forceActiveFocus(); }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: page.s(16)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: page.s(46)
            ColumnLayout {
                spacing: page.s(4)
                Text { text: "Translate"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(30); color: page.cText }
                Text { text: "Screen text to English  \u00b7  " + hub.langLabel(hub.langs) + (hub.conf > 0 ? "  \u00b7  " + hub.conf + "% confident" : ""); font.family: "JetBrains Mono"; font.pixelSize: page.s(11); color: page.cSub0 }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredHeight: page.s(30)
                Layout.preferredWidth: pillRow.implicitWidth + page.s(26)
                radius: height / 2
                color: Qt.alpha(page.statusColor, 0.14)
                border.color: Qt.alpha(page.statusColor, 0.5); border.width: 1
                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: page.s(8)
                    Rectangle { width: page.s(8); height: page.s(8); radius: page.s(4); color: page.statusColor; opacity: hub.status === "loading" ? page.pulse : 1.0 }
                    Text { text: page.statusLabel; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(11); color: page.statusColor }
                }
            }
        }

        // ---- progress sweep ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: page.s(2)
            radius: 1
            color: page.cSurf0
            clip: true
            Rectangle {
                id: sweep
                width: parent.width * 0.3; height: parent.height; radius: 1
                color: page.cMauve
                visible: hub.status === "loading"
                SequentialAnimation on x {
                    running: hub.status === "loading"; loops: Animation.Infinite
                    NumberAnimation { from: -sweep.width; to: sweep.parent.width; duration: 1000; easing.type: Easing.InOutQuad }
                }
            }
        }

        // ---- cards ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: page.s(14)

            // SOURCE
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredWidth: 100
                radius: page.s(16)
                color: Qt.alpha(page.cSurf0, 0.45)
                border.color: srcEdit.activeFocus ? page.cMauve : page.cSurf1
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 200 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: page.s(20)
                    spacing: page.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "SOURCE"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cSub0 }
                        Item { Layout.fillWidth: true }
                        Text { text: srcEdit.text.length + " chars"; font.family: "JetBrains Mono"; font.pixelSize: page.s(10); color: page.cSub0 }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Flickable {
                            id: srcFlick
                            anchors.fill: parent
                            contentHeight: srcEdit.paintedHeight
                            clip: true; boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: srcEdit
                                width: srcFlick.width
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                readOnly: hub.status === "loading"
                                font.family: "JetBrains Mono"; font.pixelSize: page.s(20)
                                color: page.cText; selectionColor: page.cMauve
                                Keys.onReturnPressed: (e) => {
                                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; }
                                    else { hub.retranslate(srcEdit.text); e.accepted = true; }
                                }
                                Keys.onEnterPressed: (e) => {
                                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; }
                                    else { hub.retranslate(srcEdit.text); e.accepted = true; }
                                }
                                Keys.onEscapePressed: (e) => { hub.requestClose(); e.accepted = true; }
                            }
                        }
                        Text {
                            visible: srcEdit.text === ""
                            anchors.left: parent.left; anchors.top: parent.top
                            text: "Scan the screen, or type here\u2026"
                            font.family: "JetBrains Mono"; font.pixelSize: page.s(18)
                            color: page.cSub0; opacity: 0.6
                        }
                    }

                    Text {
                        visible: hub.phonetic !== ""
                        Layout.fillWidth: true
                        text: hub.phonetic
                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                        font.family: "JetBrains Mono"; font.pixelSize: page.s(13); font.italic: true
                        color: Qt.alpha(page.cMauve, 0.9)
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: page.s(8)
                        Text {
                            height: page.s(26); verticalAlignment: Text.AlignVCenter
                            text: "RE-SCAN AS"; font.family: "JetBrains Mono"; font.pixelSize: page.s(9); font.letterSpacing: 1.5; color: page.cSub0
                        }
                        Repeater {
                            model: page.chipModel
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool active: hub.langs === chip.modelData.langs
                                width: chipText.implicitWidth + page.s(22); height: page.s(26)
                                radius: page.s(7)
                                color: active ? Qt.alpha(page.cMauve, 0.2) : (chipMa.containsMouse ? Qt.alpha(page.cMauve, 0.1) : "transparent")
                                border.color: (active || chipMa.containsMouse) ? page.cMauve : page.cSurf1
                                border.width: 1
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData.label
                                    font.family: "JetBrains Mono"; font.pixelSize: page.s(11)
                                    font.weight: chip.active ? Font.Bold : Font.Normal
                                    color: chip.active ? page.cMauve : page.cSub0
                                }
                                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; onClicked: { if (chip.modelData.langs === "__more") page.moreLangs = !page.moreLangs; else hub.rescan(chip.modelData.langs); } }
                            }
                        }
                    }
                }
            }

            // ARROW
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: page.s(46); Layout.preferredHeight: page.s(46)
                radius: width / 2
                scale: hub.status === "loading" ? 0.9 + 0.1 * page.pulse : 1.0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: hub.mauve }
                    GradientStop { position: 1.0; color: hub.pink }
                }
                Text {
                    anchors.centerIn: parent
                    text: "\uDB80\uDC54"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: page.s(20)
                    color: hub.crust
                }
            }

            // ENGLISH
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredWidth: 100
                radius: page.s(16)
                color: Qt.alpha(page.cMauve, 0.07)
                border.color: Qt.alpha(page.cMauve, 0.4); border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: page.s(20)
                    spacing: page.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "ENGLISH"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cMauve }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredWidth: page.s(32); Layout.preferredHeight: page.s(32)
                            radius: page.s(9)
                            opacity: hub.status === "done" ? 1.0 : 0.35
                            color: cpMa.containsMouse ? Qt.alpha(page.cMauve, 0.18) : "transparent"
                            border.color: cpMa.containsMouse ? page.cMauve : page.cSurf1; border.width: 1
                            Text { anchors.centerIn: parent; text: "\uDB80\uDD8F"; font.family: "Iosevka Nerd Font"; font.pixelSize: page.s(15); color: page.cMauve }
                            MouseArea {
                                id: cpMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: { if (hub.status === "done") hub.copyText(hub.translated, "Translation copied"); }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true

                        Column {
                            visible: hub.status === "loading"
                            width: parent.width; spacing: page.s(12)
                            Repeater {
                                model: [0.92, 0.78, 0.5]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width * modelData; height: page.s(16); radius: page.s(8)
                                    color: page.cSurf1; opacity: page.pulse
                                }
                            }
                        }
                        Text {
                            visible: hub.status === "idle"
                            anchors.left: parent.left; anchors.top: parent.top
                            text: "The translation appears here."
                            font.family: "JetBrains Mono"; font.pixelSize: page.s(18); color: page.cSub0; opacity: 0.6
                        }
                        Flickable {
                            id: dstFlick
                            visible: hub.status === "done" || hub.status === "error"
                            anchors.fill: parent
                            contentHeight: dstText.paintedHeight
                            clip: true; boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: dstText
                                width: dstFlick.width
                                text: hub.translated
                                readOnly: true; selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: page.s(24)
                                color: hub.status === "error" ? page.cRed : page.cText
                                selectionColor: page.cMauve
                            }
                        }
                    }
                }
            }
        }

        // ---- footer ----
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Enter translate  \u00b7  Shift+Enter new line  \u00b7  C copy  \u00b7  S scan  \u00b7  2 dictionary"
                font.family: "JetBrains Mono"; font.pixelSize: page.s(11); color: page.cSub0
            }
            Item { Layout.fillWidth: true }
            PillBtn { hub: page.hub; label: "Open in Dictionary"; onClicked: page.hub.page = 1 }
        }
    }
}
