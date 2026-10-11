import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window
    focus: true

    Scaler {
        id: scaler
        currentWidth: Screen.width
    }

    function s(val) {
        return scaler.s(val);
    }

    MatugenColors { id: _theme }

    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color red: _theme.red
    readonly property color green: _theme.green

    // mode: how the preview moves. vert: vertical movement.
    readonly property var options: [
        { label: "Slide",          hint: "Classic sideways slide",     style: "slide",             on: true,  mode: "slide",     vert: false },
        { label: "Vertical slide", hint: "Slides up and down",         style: "slidevert",         on: true,  mode: "slide",     vert: true  },
        { label: "Fade",           hint: "Cross-fade, no movement",    style: "fade",              on: true,  mode: "fade",      vert: false },
        { label: "Slide + fade",   hint: "Short soft slide with fade", style: "slidefade 20%",     on: true,  mode: "slidefade", vert: false },
        { label: "Vertical soft",  hint: "Short vertical slide + fade", style: "slidefadevert 20%", on: true, mode: "slidefade", vert: true  },
        { label: "None",           hint: "Instant switch",             style: "slide",             on: false, mode: "none",      vert: false }
    ]

    property int selected: 0
    property real speed: 5.0
    property bool busy: false
    property bool statusError: false
    property string statusText: "Pick a style, set the duration, then apply."
    readonly property real previewMs: Math.max(150, speed * 100)

    function loadChoice(txt) {
        var m = /style\s*=\s*"([^"]+)"/.exec(txt);
        var sp = /speed\s*=\s*([0-9.]+)/.exec(txt);
        var en = /enabled\s*=\s*(true|false)/.exec(txt);
        if (!m) return;
        if (sp) speed = parseFloat(sp[1]);
        if (en && en[1] === "false") { selected = 5; return; }
        for (var i = 0; i < options.length; i++) {
            if (options[i].style === m[1] && options[i].on) { selected = i; return; }
        }
    }

    function apply() {
        if (busy) return;
        var o = options[selected];
        var lua = 'return { style = "' + o.style + '", speed = ' + speed.toFixed(1) + ', enabled = ' + (o.on ? "true" : "false") + ' }';
        busy = true;
        statusError = false;
        statusText = "Applying...";
        applier.command = ["bash", "-c",
            'printf "%s\\n" "$1" > "$HOME/.config/hypr/config/animation_choice.lua" && hyprctl reload', "_", lua];
        applier.running = true;
    }

    Component.onCompleted: reader.running = true

    Process {
        id: reader
        command: ["bash", "-c", 'cat "$HOME/.config/hypr/config/animation_choice.lua" 2>/dev/null']
        stdout: StdioCollector {
            onStreamFinished: window.loadChoice(this.text)
        }
    }

    Process {
        id: applier
        stderr: StdioCollector { id: applyErr }
        onExited: (code) => {
            window.busy = false;
            if (code === 0) {
                window.statusError = false;
                window.statusText = "Applied. Switch workspace to feel it.";
            } else {
                window.statusError = true;
                var e = applyErr.text.trim();
                window.statusText = e !== "" ? e : ("Failed (exit " + code + ").");
            }
        }
    }

    // Reusable button (no outer ids inside, so it's scope-safe)
    component ActionButton: Rectangle {
        id: btn
        property string label: ""
        property color fill: "#313244"
        property color fillHover: "#45475a"
        property color fg: "#cdd6f4"
        property bool active: true
        property real px: 13
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: px * 3.2
        radius: height / 2.6
        color: !active ? Qt.alpha(fill, 0.35) : (ma.containsMouse ? fillHover : fill)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.fg
            opacity: btn.active ? 1.0 : 0.5
            font.family: "JetBrains Mono"
            font.pixelSize: btn.px
            font.bold: true
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: window.s(24)
        color: window.base
        border.width: 1
        border.color: Qt.alpha(window.surface1, 0.8)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: window.s(28)
        spacing: window.s(14)

        Text {
            text: "Workspace animation"
            color: window.text
            font.family: "JetBrains Mono"
            font.pixelSize: window.s(22)
            font.bold: true
        }
        Text {
            text: "Previews loop at the duration you choose"
            color: window.subtext0
            font.family: "JetBrains Mono"
            font.pixelSize: window.s(12)
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            rowSpacing: window.s(14)
            columnSpacing: window.s(14)

            Repeater {
                model: window.options

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 1
                    radius: window.s(16)
                    color: cardMa.containsMouse ? window.surface1 : window.surface0
                    border.width: window.selected === card.index ? window.s(3) : 1
                    border.color: window.selected === card.index ? window.mauve : Qt.alpha(window.surface2, 0.6)
                    Behavior on color { ColorAnimation { duration: 150 } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(12)
                        spacing: window.s(6)

                        // Mini screen with two "workspaces"
                        Rectangle {
                            id: screen
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: window.s(8)
                            color: window.crust
                            clip: true

                            property real p: card.modelData.mode === "none" ? 1 : 0
                            readonly property string mode: card.modelData.mode
                            readonly property bool vert: card.modelData.vert
                            readonly property bool fades: mode === "fade" || mode === "slidefade"
                            readonly property real travel: mode === "slidefade" ? 0.2 : 1.0

                            SequentialAnimation on p {
                                running: card.modelData.mode !== "none"
                                loops: Animation.Infinite
                                NumberAnimation { from: 0; to: 1; duration: window.previewMs; easing.type: Easing.OutCubic }
                                PauseAnimation { duration: 700 }
                                NumberAnimation { from: 1; to: 0; duration: window.previewMs; easing.type: Easing.OutCubic }
                                PauseAnimation { duration: 700 }
                            }

                            Rectangle {
                                width: screen.width
                                height: screen.height
                                visible: screen.mode !== "none"
                                color: Qt.alpha(window.mauve, 0.85)
                                x: (screen.vert || screen.mode === "fade") ? 0 : -screen.p * screen.width * screen.travel
                                y: screen.vert ? -screen.p * screen.height * screen.travel : 0
                                opacity: screen.fades ? 1 - screen.p : 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "1"
                                    color: window.crust
                                    font.family: "JetBrains Mono"
                                    font.bold: true
                                    font.pixelSize: window.s(20)
                                }
                            }
                            Rectangle {
                                width: screen.width
                                height: screen.height
                                color: Qt.alpha(window.green, 0.85)
                                x: (screen.vert || screen.mode === "fade" || screen.mode === "none") ? 0 : (1 - screen.p) * screen.width * screen.travel
                                y: screen.vert ? (1 - screen.p) * screen.height * screen.travel : 0
                                opacity: screen.fades ? screen.p : 1
                                Text {
                                    anchors.centerIn: parent
                                    text: "2"
                                    color: window.crust
                                    font.family: "JetBrains Mono"
                                    font.bold: true
                                    font.pixelSize: window.s(20)
                                }
                            }
                        }

                        Text {
                            text: card.modelData.label
                            color: window.text
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(13)
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.hint
                            color: window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(10)
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: cardMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.selected = card.index
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: window.s(12)
            Text {
                text: "Duration"
                color: window.subtext0
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(12)
            }
            Slider {
                id: speedSlider
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(28)
                implicitHeight: window.s(28)
                from: 2
                to: 12
                stepSize: 0.5
                value: window.speed
                enabled: window.options[window.selected].on
                onMoved: window.speed = value

                background: Rectangle {
                    x: speedSlider.leftPadding
                    y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                    width: speedSlider.availableWidth
                    height: window.s(6)
                    radius: height / 2
                    color: window.surface0
                    Rectangle {
                        width: speedSlider.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: window.mauve
                    }
                }
                handle: Rectangle {
                    x: speedSlider.leftPadding + speedSlider.visualPosition * (speedSlider.availableWidth - width)
                    y: speedSlider.topPadding + speedSlider.availableHeight / 2 - height / 2
                    width: window.s(18)
                    height: window.s(18)
                    radius: width / 2
                    color: window.mauve
                    border.width: window.s(2)
                    border.color: window.base
                }
            }
            Text {
                text: Math.round(window.speed * 100) + " ms"
                color: window.text
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(12)
                font.bold: true
                Layout.preferredWidth: window.s(64)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: window.s(14)

            Text {
                Layout.fillWidth: true
                text: window.statusText
                wrapMode: Text.WordWrap
                color: window.statusError ? window.red : window.subtext0
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(11)
            }
            ActionButton {
                Layout.fillWidth: false
                Layout.preferredWidth: window.s(200)
                label: window.busy ? "Applying..." : "Apply"
                px: window.s(13)
                fill: window.mauve
                fillHover: Qt.lighter(window.mauve, 1.12)
                fg: window.crust
                active: !window.busy
                onClicked: window.apply()
            }
        }
    }
}
