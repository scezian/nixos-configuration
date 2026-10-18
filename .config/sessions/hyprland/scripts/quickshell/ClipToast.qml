import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: win

    WlrLayershell.namespace: "qs-cliptoast"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors.top: true
    margins.top: win.s(64)
    implicitWidth: win.s(580)
    implicitHeight: win.s(280)
    visible: win.shown || card.opacity > 0.01
    mask: Region { item: card }

    MatugenColors { id: theme }

    property bool shown: false
    property string status: "done"
    property string original: ""
    property string translated: ""
    property string lastRaw: ""
    property real upSince: Date.now()
    property real remain: 1.0
    readonly property real sc: Math.max(0.6, Math.min(1.5, (win.screen ? win.screen.width : 1920) / 1920.0))
    function s(v) { return Math.round(v * win.sc); }

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateFile: home + "/.cache/qs_cliptoast.json"
    readonly property string script: home + "/.config/hypr/scripts/ocr_translate.sh"
    readonly property string mgr: home + "/.config/hypr/scripts/qs_manager.sh"

    function openHub() {
        Quickshell.execDetached(["bash", "-c",
            'bash "$1" --text "$2" & sleep 0.25; bash "$3" open translate; wait',
            "_", win.script, win.original, win.mgr]);
        countdown.stop();
        win.shown = false;
    }

    // watches the clipboard (the pkill is anchored so it only ever kills our own watcher, never cliphist's)
    Process {
        running: true
        command: ["bash", "-c", "pkill -f '^wl-paste --watch .*clip_translate' 2>/dev/null; exec wl-paste --watch \"$HOME/.config/hypr/scripts/clip_translate.sh\""]
    }

    Process {
        id: reader
        command: ["cat", win.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text;
                if (raw === win.lastRaw) return;
                win.lastRaw = raw;
                // ignore whatever the watcher fires for the clipboard that was already there at startup
                if (!raw || Date.now() - win.upSince < 5000) return;
                try {
                    let d = JSON.parse(raw);
                    win.original = d.original || "";
                    win.translated = d.translated || "";
                    win.status = d.status || "done";
                    win.shown = true;
                    win.remain = 1.0;
                    if (win.status === "loading") countdown.stop();
                    else countdown.restart();
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 400; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!reader.running) reader.running = true; }
    }

    NumberAnimation {
        id: countdown
        target: win; property: "remain"
        from: 1.0; to: 0.0; duration: 8000
        paused: cardMa.containsMouse
        onFinished: win.shown = false
    }

    property real pulse: 1.0
    SequentialAnimation on pulse {
        running: win.status === "loading" && win.shown; loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - win.s(24)
        height: col.implicitHeight + win.s(32)
        y: win.shown ? win.s(4) : -(height + win.s(30))
        Behavior on y { NumberAnimation { duration: 520; easing.type: win.shown ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.1 } }
        opacity: win.shown ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 260 } }
        radius: win.s(16)
        color: Qt.alpha(theme.base, 0.86)
        border.color: Qt.alpha(theme.mauve, 0.45)
        border.width: 1
        clip: true

        Rectangle {
            anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
            height: win.s(3)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: theme.mauve }
                GradientStop { position: 1.0; color: theme.pink }
            }
        }

        MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; onClicked: win.openHub() }

        ColumnLayout {
            id: col
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: win.s(16)
            anchors.topMargin: win.s(18)
            spacing: win.s(8)

            RowLayout {
                Layout.fillWidth: true
                spacing: win.s(10)
                Rectangle {
                    Layout.preferredWidth: win.s(26); Layout.preferredHeight: win.s(26)
                    radius: win.s(8)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: theme.mauve }
                        GradientStop { position: 1.0; color: theme.pink }
                    }
                    Text { anchors.centerIn: parent; text: "\uDB81\uDDCA"; font.family: "Iosevka Nerd Font"; font.pixelSize: win.s(15); color: theme.crust }
                }
                Text { text: "CLIPBOARD"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: win.s(10); font.letterSpacing: 1.5; color: theme.mauve }
                Item { Layout.fillWidth: true }
                Text { text: "click to open"; font.family: "JetBrains Mono"; font.pixelSize: win.s(10); color: theme.subtext0 }
                Rectangle {
                    Layout.preferredWidth: win.s(22); Layout.preferredHeight: win.s(22)
                    radius: win.s(6)
                    color: xMa.containsMouse ? Qt.alpha(theme.red, 0.15) : "transparent"
                    Text { anchors.centerIn: parent; text: "\u00d7"; font.pixelSize: win.s(16); color: xMa.containsMouse ? theme.red : theme.subtext0 }
                    MouseArea { id: xMa; anchors.fill: parent; hoverEnabled: true; onClicked: { countdown.stop(); win.shown = false; } }
                }
            }

            Text {
                Layout.fillWidth: true
                text: win.original
                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                font.pixelSize: win.s(14); color: theme.subtext1
            }

            Rectangle {
                visible: win.status === "loading"
                Layout.preferredWidth: parent.width * 0.7; Layout.preferredHeight: win.s(14)
                radius: win.s(7); color: theme.surface1; opacity: win.pulse
            }
            Text {
                visible: win.status !== "loading"
                Layout.fillWidth: true
                text: win.translated
                wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
                font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: win.s(17)
                color: win.status === "error" ? theme.red : theme.text
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom; anchors.left: parent.left
            height: win.s(2)
            width: parent.width * win.remain
            color: Qt.alpha(theme.mauve, 0.85)
            visible: win.status !== "loading"
        }
    }
}
