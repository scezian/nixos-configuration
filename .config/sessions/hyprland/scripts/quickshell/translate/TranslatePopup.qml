import QtQuick
import "."
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val); }

    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color red: _theme.red

    // ---- shared state (pages read these) ----
    property int page: 0                 // 0 = Translate, 1 = Dictionary
    property string status: "idle"       // idle | loading | done | error
    property string original: ""
    property string translated: ""
    property string phonetic: ""
    property string langs: "chi_sim+eng"
    property string lastRaw: ""
    property real actionTs: 0
    property string toast: ""
    property real introBase: 0.0
    property real introContent: 0.0

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateFile: home + "/.cache/qs_translate.json"
    readonly property string mgr: home + "/.config/hypr/scripts/qs_manager.sh"
    readonly property string script: home + "/.config/hypr/scripts/ocr_translate.sh"

    readonly property var langChips: [
        { label: "简体",   langs: "chi_sim+eng" },
        { label: "繁體",   langs: "chi_tra+eng" },
        { label: "日本語", langs: "jpn+eng" },
        { label: "한국어", langs: "kor+eng" }
    ]

    function requestClose() { closeSequence.start(); }
    function copyText(t, label) {
        if (!t) return;
        Quickshell.execDetached(["wl-copy", t]);
        root.toast = label || "Copied";
        toastTimer.restart();
    }
    function startScan() { Quickshell.execDetached(["bash", root.script]); }
    function rescan(l) {
        root.actionTs = Date.now();
        root.status = "loading";
        Quickshell.execDetached(["bash", root.script, "--redo", "--lang", l]);
    }
    function retranslate(t) {
        t = (t || "").trim();
        if (t === "") return;
        root.actionTs = Date.now();
        root.status = "loading";
        Quickshell.execDetached(["bash", root.script, "--text", t, "--lang", root.langs]);
        root.forceActiveFocus();
    }

    onPageChanged: root.forceActiveFocus()

    Keys.onEscapePressed: { root.requestClose(); event.accepted = true; }
    Keys.onPressed: (event) => {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (event.key === Qt.Key_1) { root.page = 0; event.accepted = true; }
        else if (event.key === Qt.Key_2) { root.page = 1; event.accepted = true; }
        else if (event.key === Qt.Key_S) { root.startScan(); event.accepted = true; }
        else if (event.key === Qt.Key_C) {
            if (root.page === 0) root.copyText(root.translated, "Copied"); else dPage.copyMeanings();
            event.accepted = true;
        }
        else if (event.key === Qt.Key_Slash) { root.page = 1; dPage.focusSearch(); event.accepted = true; }
    }

    Timer { id: toastTimer; interval: 1600; onTriggered: root.toast = "" }

    // ---- state file polling (the script rewrites it: loading -> done) ----
    Process {
        id: reader
        command: ["cat", root.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text;
                if (!raw || raw === root.lastRaw) return;
                try {
                    let d = JSON.parse(raw);
                    if (root.actionTs > 0 && (d.ts || 0) < root.actionTs) return;
                    root.actionTs = 0;
                    root.lastRaw = raw;
                    root.status = d.status || "done";
                    root.original = d.original || "";
                    root.translated = d.translated || "";
                    root.phonetic = d.phonetic || "";
                    root.langs = d.langs || root.langs;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!reader.running) reader.running = true; }
    }

    // ---- animations ----
    Component.onCompleted: startupSequence.start()

    ParallelAnimation {
        id: startupSequence
        NumberAnimation { target: root; property: "introBase"; from: 0.0; to: 1.0; duration: 600; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introContent"; from: 0.0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.02 }
        }
    }
    SequentialAnimation {
        id: closeSequence
        NumberAnimation { target: root; property: "introContent"; to: 0.0; duration: 150; easing.type: Easing.InExpo }
        NumberAnimation { target: root; property: "introBase"; to: 0.0; duration: 200; easing.type: Easing.InQuart }
        ScriptAction { script: Quickshell.execDetached(["bash", root.mgr, "close"]) }
    }

    // four-corner scan icon, drawn so there is no icon-font dependency
    component ScanGlyph: Item {
        id: glyph
        property color col: "white"
        width: 18; height: 18
        Repeater {
            model: [[0,0,6,2],[0,0,2,6],[12,0,6,2],[16,0,2,6],[0,16,6,2],[0,12,2,6],[12,16,6,2],[16,12,2,6],[7,7,4,4]]
            delegate: Rectangle {
                required property var modelData
                x: modelData[0]; y: modelData[1]; width: modelData[2]; height: modelData[3]
                radius: modelData[2] === 4 ? 2 : 0
                color: glyph.col
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.introBase
        scale: 0.95 + (0.05 * root.introBase)

        Rectangle {
            id: card
            anchors.fill: parent
            radius: root.s(18)
            color: Qt.alpha(root.base, 0.72)
            border.color: root.surface0
            border.width: 1
            clip: true

            // ---- animated ambient orbs (seamless loop) ----
            Item {
                id: orbLayer
                anchors.fill: parent
                property real time: 0
                NumberAnimation on time { from: 0; to: Math.PI * 2; duration: 18000; loops: Animation.Infinite; running: true }
                Repeater {
                    model: 3
                    delegate: Item {
                        id: orb
                        required property int index
                        readonly property real sz: root.s([520, 420, 360][index])
                        readonly property color oc: [root.mauve, root.blue, root.pink][index]
                        readonly property real t: orbLayer.time
                        width: sz; height: sz
                        x: orbLayer.width  * [0.9, 0.12, 0.6][index] - sz / 2 + Math.sin(t * [1, 1, 2][index]) * root.s(90)
                        y: orbLayer.height * [0.05, 0.95, 0.5][index] - sz / 2 + Math.cos(t * [2, 1, 1][index]) * root.s(60)
                        opacity: 0.65 + 0.35 * Math.sin(t + index * 2.1)
                        Rectangle { anchors.fill: parent; radius: width / 2; color: orb.oc; opacity: 0.05 }
                        Rectangle { anchors.centerIn: parent; width: parent.width * 0.6; height: width; radius: width / 2; color: orb.oc; opacity: 0.07 }
                    }
                }
            }

            // ================= SIDEBAR =================
            Rectangle {
                id: side
                x: root.s(16) - (1.0 - root.introContent) * root.s(30)
                y: root.s(16)
                width: root.s(236)
                height: parent.height - root.s(32)
                radius: root.s(14)
                color: Qt.alpha(root.crust, 0.55)
                border.color: root.surface0
                border.width: 1
                opacity: root.introContent

                // brand
                RowLayout {
                    x: root.s(18); y: root.s(20)
                    width: parent.width - root.s(36)
                    spacing: root.s(12)
                    Rectangle {
                        Layout.preferredWidth: root.s(46); Layout.preferredHeight: root.s(46)
                        radius: root.s(13)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.mauve }
                            GradientStop { position: 1.0; color: root.pink }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "\uDB81\uDDCA"
                            font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(24)
                            color: root.crust
                        }
                    }
                    ColumnLayout {
                        spacing: root.s(2)
                        Text { text: "Lexicon"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(17); color: root.text }
                        Text { text: "translate \u00b7 dictionary"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                    }
                }

                Rectangle { x: root.s(16); y: root.s(86); width: parent.width - root.s(32); height: 1; color: root.surface0 }

                // nav
                Item {
                    id: nav
                    x: root.s(12); y: root.s(104)
                    width: parent.width - root.s(24)
                    readonly property int itemH: root.s(66)
                    readonly property int gap: root.s(8)
                    height: itemH * 2 + gap

                    Rectangle {
                        id: pill
                        width: nav.width; height: nav.itemH
                        radius: root.s(12)
                        y: root.page * (nav.itemH + nav.gap)
                        Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutExpo } }
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: root.mauve }
                            GradientStop { position: 1.0; color: Qt.tint(root.mauve, Qt.alpha(root.pink, 0.45)) }
                        }
                    }

                    Repeater {
                        model: [
                            { badge: "\uDB81\uDDCA", name: "Translate",  sub: "Screen text to English" },
                            { badge: "\uDB80\uDF49", name: "Dictionary", sub: "English definitions" }
                        ]
                        delegate: Item {
                            id: navItem
                            required property int index
                            required property var modelData
                            readonly property bool act: root.page === navItem.index
                            y: navItem.index * (nav.itemH + nav.gap)
                            width: nav.width; height: nav.itemH

                            Rectangle {
                                anchors.fill: parent
                                radius: root.s(12)
                                color: Qt.alpha(root.surface1, 0.5)
                                opacity: (navMa.containsMouse && !navItem.act) ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 150 } }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: root.s(14); anchors.rightMargin: root.s(12)
                                spacing: root.s(12)
                                Rectangle {
                                    Layout.preferredWidth: root.s(40); Layout.preferredHeight: root.s(40)
                                    radius: root.s(11)
                                    color: navItem.act ? Qt.alpha(root.crust, 0.22) : Qt.alpha(root.surface1, 0.55)
                                    Text {
                                        anchors.centerIn: parent
                                        text: navItem.modelData.badge
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(22)
                                        color: navItem.act ? root.crust : root.mauve
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(2)
                                    Text {
                                        text: navItem.modelData.name
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14)
                                        color: navItem.act ? root.crust : root.text
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: navItem.modelData.sub
                                        elide: Text.ElideRight
                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                                        color: navItem.act ? Qt.alpha(root.crust, 0.7) : root.subtext0
                                    }
                                }
                                Text {
                                    text: String(navItem.index + 1)
                                    font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                                    color: navItem.act ? Qt.alpha(root.crust, 0.6) : root.surface2
                                }
                            }
                            MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.page = navItem.index }
                        }
                    }
                }

                // scan button
                Rectangle {
                    id: scanBtn
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16)
                    anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(76)
                    height: root.s(58)
                    radius: root.s(13)
                    scale: scanMa.pressed ? 0.96 : (scanMa.containsMouse ? 1.03 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: root.mauve }
                        GradientStop { position: 1.0; color: root.pink }
                    }
                    RowLayout {
                        anchors.centerIn: parent
                        spacing: root.s(12)
                        ScanGlyph { col: root.crust; scale: root.s(18) / 18 * 1.15 }
                        ColumnLayout {
                            spacing: 0
                            Text { text: "Scan screen"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(14); color: root.crust }
                            Text { text: "drag to select  \u00b7  S"; font.family: "JetBrains Mono"; font.pixelSize: root.s(9); color: Qt.alpha(root.crust, 0.7) }
                        }
                    }
                    MouseArea { id: scanMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.startScan() }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(24)
                    horizontalAlignment: Text.AlignHCenter
                    text: "SUPER+T scan\nSUPER+SHIFT+T type"
                    font.family: "JetBrains Mono"; font.pixelSize: root.s(10)
                    lineHeight: 1.3
                    color: root.subtext0
                }
            }

            // ================= CONTENT =================
            Item {
                id: content
                anchors.left: parent.left; anchors.leftMargin: root.s(16) + root.s(236) + root.s(26)
                anchors.top: parent.top; anchors.topMargin: root.s(26)
                anchors.right: parent.right; anchors.rightMargin: root.s(28)
                anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(22)
                opacity: root.introContent
                transform: Translate { y: (1.0 - root.introContent) * root.s(14) }

                TranslatePage {
                    id: tPage
                    hub: root
                    anchors.fill: parent
                    opacity: root.page === 0 ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    transform: Translate {
                        x: root.page === 0 ? 0 : -root.s(36)
                        Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }
                    }
                }
                DictionaryPage {
                    id: dPage
                    hub: root
                    anchors.fill: parent
                    opacity: root.page === 1 ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    transform: Translate {
                        x: root.page === 1 ? 0 : root.s(36)
                        Behavior on x { NumberAnimation { duration: 380; easing.type: Easing.OutExpo } }
                    }
                }
            }

            // close button
            Rectangle {
                anchors.top: parent.top; anchors.right: parent.right
                anchors.topMargin: root.s(20); anchors.rightMargin: root.s(22)
                width: root.s(34); height: root.s(34); radius: root.s(10); z: 20
                opacity: root.introContent
                color: xMa.containsMouse ? Qt.alpha(root.red, 0.12) : "transparent"
                border.color: xMa.containsMouse ? root.red : root.surface1
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "\uDB80\uDD56"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: root.s(15)
                    color: xMa.containsMouse ? root.red : root.subtext0
                }
                MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.requestClose() }
            }

            // toast
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(30)
                height: root.s(36); width: toastText.implicitWidth + root.s(40); radius: height / 2
                color: Qt.alpha(root.mauve, 0.95)
                opacity: root.toast !== "" ? 1 : 0
                visible: opacity > 0.01
                z: 30
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Text {
                    id: toastText
                    anchors.centerIn: parent
                    text: root.toast
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(12)
                    color: root.crust
                }
            }
        }
    }
}
