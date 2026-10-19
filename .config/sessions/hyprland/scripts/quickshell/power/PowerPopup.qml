import QtQuick
import QtQuick.Window
import QtQuick.Layouts
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

    // ---------- small reusable controls (self-contained: they only use their own properties) ----------
    component Toggle: Rectangle {
        id: tg
        property var hub: null
        property bool on: false
        signal flipped()
        width: hub.s(46); height: hub.s(26); radius: height / 2
        color: tg.on ? hub.mauve : hub.surface1
        Behavior on color { ColorAnimation { duration: 180 } }
        Rectangle {
            width: tg.height - tg.hub.s(6); height: width; radius: width / 2
            y: tg.hub.s(3)
            x: tg.on ? tg.width - width - tg.hub.s(3) : tg.hub.s(3)
            color: tg.on ? tg.hub.crust : tg.hub.subtext0
            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 180 } }
        }
        MouseArea { anchors.fill: parent; onClicked: tg.flipped() }
    }

    component Stepper: Row {
        id: sp
        property var hub: null
        property int value: 0
        property int from: 0
        property int to: 100
        property int step: 1
        property string suffix: ""
        property bool pad2: false
        signal edited(int v)
        spacing: hub.s(6)
        Rectangle {
            width: sp.hub.s(26); height: sp.hub.s(26); radius: sp.hub.s(7)
            color: mMa.containsMouse ? Qt.alpha(sp.hub.mauve, 0.18) : "transparent"
            border.color: mMa.containsMouse ? sp.hub.mauve : sp.hub.surface1; border.width: 1
            Text { anchors.centerIn: parent; text: "\u2212"; font.pixelSize: sp.hub.s(15); color: sp.hub.subtext1 }
            MouseArea { id: mMa; anchors.fill: parent; hoverEnabled: true; onClicked: sp.edited(Math.max(sp.from, sp.value - sp.step)) }
        }
        Text {
            width: sp.hub.s(58); height: sp.hub.s(26)
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: (sp.pad2 && sp.value < 10 ? "0" : "") + sp.value + sp.suffix
            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: sp.hub.s(13); color: sp.hub.text
        }
        Rectangle {
            width: sp.hub.s(26); height: sp.hub.s(26); radius: sp.hub.s(7)
            color: pMa.containsMouse ? Qt.alpha(sp.hub.mauve, 0.18) : "transparent"
            border.color: pMa.containsMouse ? sp.hub.mauve : sp.hub.surface1; border.width: 1
            Text { anchors.centerIn: parent; text: "+"; font.pixelSize: sp.hub.s(15); color: sp.hub.subtext1 }
            MouseArea { id: pMa; anchors.fill: parent; hoverEnabled: true; onClicked: sp.edited(Math.min(sp.to, sp.value + sp.step)) }
        }
    }

    component Btn: Rectangle {
        id: bt
        property var hub: null
        property string label: ""
        property color accent: "white"
        signal clicked()
        implicitWidth: btText.implicitWidth + hub.s(32)
        implicitHeight: hub.s(38)
        radius: hub.s(10)
        color: btMa.containsMouse ? Qt.alpha(bt.accent, 0.2) : "transparent"
        border.color: btMa.containsMouse ? bt.accent : hub.surface1; border.width: 1
        scale: btMa.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { id: btText; anchors.centerIn: parent; text: bt.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: bt.hub.s(12); color: bt.accent }
        MouseArea { id: btMa; anchors.fill: parent; hoverEnabled: true; onClicked: bt.clicked() }
    }

    // ---------- state ----------
    readonly property string home: Quickshell.env("HOME")
    readonly property string daemon: home + "/.config/hypr/scripts/power_daemon.py"
    readonly property string mgr: home + "/.config/hypr/scripts/qs_manager.sh"
    readonly property string logoFile: "file://" + home + "/.config/hypr/scripts/quickshell/power/hyprpanel.png"

    property var cfg: ({
        sunset_enabled: false, sunset_temp: 4000, sunset_schedule: false, sunset_on_hour: 19, sunset_off_hour: 7,
        lock_auto: false, lock_timeout: 30, suspend_auto: false, suspend_timeout: 60, suspend_cmd: "systemctl suspend",
        battery_alerts: true, battery_warn: 20, battery_crit: 10 })
    property var stat: ({ running: false })
    property bool daemonUp: false
    property int downCount: 0
    property bool autoStarted: false
    property real pendingUntil: 0
    property real introBase: 0.0
    property real introContent: 0.0
    property real glow: 0.0
    property real logoRot: 0.0
    property real orbTime: 0.0

    readonly property int batPct: (stat.battery && stat.battery.present && stat.battery.percent !== null && stat.battery.percent !== undefined) ? stat.battery.percent : -1
    readonly property bool batCharging: stat.battery ? stat.battery.charging === true : false
    readonly property color batColor: batCharging ? green : (batPct >= 0 && batPct <= cfg.battery_crit) ? red : (batPct >= 0 && batPct <= cfg.battery_warn) ? peach : green

    function kelvinColor(k) {
        k = Math.max(1000, Math.min(10000, k));
        let t = k / 100, r, g, b;
        if (t <= 66) {
            r = 255;
            g = 99.4708025861 * Math.log(t) - 161.1195681661;
            b = t >= 66 ? 255 : (t <= 19 ? 0 : 138.5177312231 * Math.log(t - 10) - 305.0447927307);
        } else {
            r = 329.698727446 * Math.pow(t - 60, -0.1332047592);
            g = 288.1221695283 * Math.pow(t - 60, -0.0755148492);
            b = 255;
        }
        function c(v) { return Math.max(0, Math.min(255, v)) / 255; }
        return Qt.rgba(c(r), c(g), c(b), 1);
    }
    function tempName(k) { return k < 2600 ? "Candle" : k < 3600 ? "Warm" : k < 5200 ? "Neutral" : "Daylight"; }

    function setLocal(k, v) {
        let n = JSON.parse(JSON.stringify(root.cfg));
        n[k] = v;
        root.cfg = n;
        root.pendingUntil = Date.now() + 1500;
    }
    function setKey(k, v) {
        setLocal(k, v);
        Quickshell.execDetached(["python3", root.daemon, "set", k, JSON.stringify(v)]);
    }
    function requestClose() { closeSequence.start(); }

    Keys.onEscapePressed: { root.requestClose(); event.accepted = true; }

    // ---------- polling ----------
    Process {
        id: reader
        command: ["bash", "-c", "cat \"$HOME/.config/hyprpanel/config.json\" 2>/dev/null; echo '@@@'; cat \"$HOME/.cache/hyprpanel_status.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = this.text.split("@@@");
                try {
                    if (Date.now() >= root.pendingUntil && parts[0].trim() !== "")
                        root.cfg = Object.assign({}, root.cfg, JSON.parse(parts[0]));
                } catch (e) {}
                try {
                    let st = (parts.length > 1 && parts[1].trim() !== "") ? JSON.parse(parts[1]) : { running: false };
                    root.stat = st;
                    root.daemonUp = st.running === true && (Date.now() - (st.ts || 0)) < 25000;
                    if (root.daemonUp) { root.downCount = 0; }
                    else {
                        root.downCount += 1;
                        if (root.downCount >= 3 && !root.autoStarted) {
                            root.autoStarted = true;
                            Quickshell.execDetached(["bash", "-c", "setsid -f python3 \"$HOME/.config/hypr/scripts/power_daemon.py\""]);
                        }
                    }
                } catch (e) { root.daemonUp = false; }
            }
        }
    }
    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!reader.running) reader.running = true; }
    }
    Timer {
        id: sendTimer
        interval: 220
        onTriggered: {
            if (!isFinite(root.cfg.sunset_temp)) return;
            root.pendingUntil = Date.now() + 1500;
            Quickshell.execDetached(["python3", root.daemon, "set", "sunset_temp", String(root.cfg.sunset_temp)]);
        }
    }

    // ---------- animation ----------
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
    SequentialAnimation on glow {
        loops: Animation.Infinite
        NumberAnimation { to: 1.0; duration: 2200; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 2200; easing.type: Easing.InOutSine }
    }
    NumberAnimation on logoRot { from: 0; to: 360; duration: 70000; loops: Animation.Infinite }
    Timer { interval: 33; running: true; repeat: true; onTriggered: root.orbTime += 0.033 * (Math.PI * 2 / 18) }

    // ---------- UI ----------
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

            // drifting orbs
            Item {
                anchors.fill: parent
                Repeater {
                    model: 3
                    delegate: Item {
                        id: orb
                        required property int index
                        readonly property real sz: root.s([520, 420, 360][index])
                        readonly property color oc: [root.mauve, root.blue, root.pink][index]
                        readonly property real t: root.orbTime
                        width: sz; height: sz
                        x: card.width  * [0.9, 0.1, 0.6][index] - sz / 2 + Math.sin(t * [1, 1, 2][index]) * root.s(90)
                        y: card.height * [0.05, 0.95, 0.5][index] - sz / 2 + Math.cos(t * [2, 1, 1][index]) * root.s(60)
                        opacity: 0.65 + 0.35 * Math.sin(t + index * 2.1)
                        Rectangle { anchors.fill: parent; radius: width / 2; color: orb.oc; opacity: 0.05 }
                        Rectangle { anchors.centerIn: parent; width: parent.width * 0.6; height: width; radius: width / 2; color: orb.oc; opacity: 0.07 }
                    }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.s(28)
                spacing: root.s(16)
                opacity: root.introContent
                transform: Translate { y: (1.0 - root.introContent) * root.s(14) }

                // ---- header ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.rightMargin: root.s(46)
                    spacing: root.s(16)

                    Item {
                        Layout.preferredWidth: root.s(64); Layout.preferredHeight: root.s(64)
                        Rectangle { anchors.centerIn: parent; width: parent.width * 1.3; height: width; radius: width / 2; color: root.mauve; opacity: 0.08 + 0.07 * root.glow }
                        Rectangle { anchors.centerIn: parent; width: parent.width * 1.15; height: width; radius: width / 2; color: root.pink; opacity: 0.07 }
                        Image {
                            anchors.fill: parent
                            source: root.logoFile
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true; asynchronous: true
                            rotation: root.logoRot
                        }
                    }
                    ColumnLayout {
                        spacing: root.s(4)
                        Text { text: "Power & Display"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(30); color: root.text }
                        Text { text: "night light  \u00b7  idle  \u00b7  battery"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                    }
                    Item { Layout.fillWidth: true }
                    Btn {
                        visible: !root.daemonUp
                        hub: root; label: "Start service"; accent: root.green
                        onClicked: Quickshell.execDetached(["bash", "-c", "setsid -f python3 \"$HOME/.config/hypr/scripts/power_daemon.py\""])
                    }
                }

                // ---- cards ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: root.s(16)

                    // ===== NIGHT LIGHT =====
                    Rectangle {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: 11
                        radius: root.s(16)
                        clip: true
                        color: Qt.alpha(root.surface0, 0.45)
                        border.color: root.surface1; border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: root.s(22)
                            spacing: root.s(14)

                            RowLayout {
                                Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: root.s(2)
                                    Text { text: "NIGHT LIGHT"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 1.5; color: root.mauve }
                                    Text { text: "Warm the screen to reduce eye strain"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                                }
                                Item { Layout.fillWidth: true }
                                Toggle { hub: root; on: root.cfg.sunset_enabled; onFlipped: root.setKey("sunset_enabled", !root.cfg.sunset_enabled) }
                            }

                            // live tint preview
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: root.s(96)
                                radius: root.s(12)
                                color: root.kelvinColor(root.cfg.sunset_temp)
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.color: Qt.alpha(root.text, 0.12); border.width: 1
                                Column {
                                    anchors.centerIn: parent
                                    spacing: root.s(2)
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.cfg.sunset_temp + "K"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(30); color: "#1b1b1b" }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.tempName(root.cfg.sunset_temp); font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: "#2b2b2b" }
                                }
                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius
                                    color: Qt.alpha(root.crust, 0.62)
                                    opacity: root.cfg.sunset_enabled ? 0 : 1
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                    Text { anchors.centerIn: parent; text: "OFF"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(20); font.letterSpacing: 4; color: root.subtext0 }
                                }
                            }

                            // temperature slider
                            Item {
                                id: tslider
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.s(34)
                                readonly property real frac: Math.max(0, Math.min(1, (root.cfg.sunset_temp - 2000) / 4500))
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: root.s(10); radius: height / 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0;  color: root.kelvinColor(2000) }
                                        GradientStop { position: 0.33; color: root.kelvinColor(3500) }
                                        GradientStop { position: 0.66; color: root.kelvinColor(5000) }
                                        GradientStop { position: 1.0;  color: root.kelvinColor(6500) }
                                    }
                                }
                                Rectangle {
                                    id: handle
                                    width: root.s(22); height: width; radius: width / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: tslider.frac * (tslider.width - width)
                                    color: root.kelvinColor(root.cfg.sunset_temp)
                                    border.color: root.mauve; border.width: 3
                                    scale: tma.pressed ? 1.15 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120 } }
                                }
                                MouseArea {
                                    id: tma
                                    anchors.fill: parent
                                    function setFrom(mx) {
                                        let f = Math.max(0, Math.min(1, (mx - handle.width / 2) / (tslider.width - handle.width)));
                                        if (isNaN(f)) return;
                                        root.setLocal("sunset_temp", Math.round((2000 + f * 4500) / 50) * 50);
                                        sendTimer.restart();
                                    }
                                    onPressed: (m) => setFrom(m.x)
                                    onPositionChanged: (m) => { if (pressed) setFrom(m.x); }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "2000K"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                Item { Layout.fillWidth: true }
                                Text { text: "6500K"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                            }

                            // presets
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(8)
                                Repeater {
                                    model: [{ n: "Candle", k: 2500 }, { n: "Warm", k: 3200 }, { n: "Neutral", k: 4500 }, { n: "Daylight", k: 6500 }]
                                    delegate: Rectangle {
                                        id: ps
                                        required property var modelData
                                        readonly property bool act: root.cfg.sunset_temp === ps.modelData.k
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: root.s(34)
                                        radius: root.s(9)
                                        color: ps.act ? Qt.alpha(root.mauve, 0.2) : (psMa.containsMouse ? Qt.alpha(root.mauve, 0.1) : "transparent")
                                        border.color: (ps.act || psMa.containsMouse) ? root.mauve : root.surface1; border.width: 1
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: root.s(7)
                                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: root.s(10); height: width; radius: width / 2; color: root.kelvinColor(ps.modelData.k) }
                                            Text { text: ps.modelData.n; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); font.weight: ps.act ? Font.Bold : Font.Normal; color: ps.act ? root.mauve : root.subtext1 }
                                        }
                                        MouseArea { id: psMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.setKey("sunset_temp", ps.modelData.k) }
                                    }
                                }
                            }

                            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.surface1 }

                            // schedule
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(12)
                                Toggle { hub: root; on: root.cfg.sunset_schedule; onFlipped: root.setKey("sunset_schedule", !root.cfg.sunset_schedule) }
                                ColumnLayout {
                                    spacing: root.s(2)
                                    Text { text: "Auto schedule"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    Text {
                                        text: root.cfg.sunset_schedule
                                              ? ("on at " + ("0" + root.cfg.sunset_on_hour).slice(-2) + ":00, off at " + ("0" + root.cfg.sunset_off_hour).slice(-2) + ":00")
                                              : "off: the toggle above is manual"
                                        font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0
                                    }
                                }
                                Item { Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: root.s(10)
                                opacity: root.cfg.sunset_schedule ? 1 : 0.4
                                Text { text: "ON"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                Stepper { hub: root; value: root.cfg.sunset_on_hour; from: 0; to: 23; step: 1; suffix: ":00"; pad2: true; onEdited: (v) => root.setKey("sunset_on_hour", v) }
                                Item { Layout.fillWidth: true }
                                Text { text: "OFF"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                Stepper { hub: root; value: root.cfg.sunset_off_hour; from: 0; to: 23; step: 1; suffix: ":00"; pad2: true; onEdited: (v) => root.setKey("sunset_off_hour", v) }
                            }
                        }
                    }

                    // ===== right column =====
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: 9
                        spacing: root.s(16)

                        // ----- IDLE & LOCK -----
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.preferredHeight: 5
                            radius: root.s(16)
                            clip: true
                            color: Qt.alpha(root.surface0, 0.45)
                            border.color: root.surface1; border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(22)
                                spacing: root.s(14)

                                Text { text: "IDLE & LOCK"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 1.5; color: root.mauve }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(12)
                                    ColumnLayout {
                                        spacing: root.s(2)
                                        Text { text: "Auto-lock"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                        Text { text: "after inactivity"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Stepper { hub: root; value: root.cfg.lock_timeout; from: 5; to: 240; step: 5; suffix: " min"; opacity: root.cfg.lock_auto ? 1 : 0.4; onEdited: (v) => root.setKey("lock_timeout", v) }
                                    Toggle { hub: root; on: root.cfg.lock_auto; onFlipped: root.setKey("lock_auto", !root.cfg.lock_auto) }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(12)
                                    ColumnLayout {
                                        spacing: root.s(2)
                                        Text { text: "Auto-suspend"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                        Text { text: "sleep after inactivity"; font.family: "JetBrains Mono"; font.pixelSize: root.s(10); color: root.subtext0 }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Stepper { hub: root; value: root.cfg.suspend_timeout; from: 5; to: 480; step: 5; suffix: " min"; opacity: root.cfg.suspend_auto ? 1 : 0.4; onEdited: (v) => root.setKey("suspend_timeout", v) }
                                    Toggle { hub: root; on: root.cfg.suspend_auto; onFlipped: root.setKey("suspend_auto", !root.cfg.suspend_auto) }
                                }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(10)
                                    Btn { hub: root; Layout.fillWidth: true; label: "Lock now"; accent: root.mauve; onClicked: Quickshell.execDetached(["bash", root.home + "/.config/hypr/scripts/lock.sh"]) }
                                    Btn { hub: root; Layout.fillWidth: true; label: "Suspend now"; accent: root.red; onClicked: Quickshell.execDetached(["bash", "-c", root.cfg.suspend_cmd]) }
                                }
                            }
                        }

                        // ----- BATTERY -----
                        Rectangle {
                            Layout.fillWidth: true; Layout.fillHeight: true
                            Layout.preferredHeight: 4
                            radius: root.s(16)
                            clip: true
                            color: Qt.alpha(root.surface0, 0.45)
                            border.color: root.surface1; border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: root.s(22)
                                spacing: root.s(20)

                                Item {
                                    Layout.preferredWidth: root.s(112); Layout.preferredHeight: root.s(112)
                                    Layout.alignment: Qt.AlignVCenter
                                    Canvas {
                                        id: ring
                                        anchors.fill: parent
                                        property real pct: Math.max(0, root.batPct)
                                        Behavior on pct { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                        onPctChanged: requestPaint()
                                        onPaint: {
                                            let ctx = getContext("2d");
                                            ctx.reset();
                                            let cx = width / 2, cy = height / 2, r = Math.min(width, height) / 2 - root.s(8);
                                            ctx.lineWidth = root.s(9);
                                            ctx.lineCap = "round";
                                            ctx.strokeStyle = String(root.surface1);
                                            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke();
                                            if (pct > 0) {
                                                ctx.strokeStyle = String(root.batColor);
                                                ctx.beginPath(); ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * pct / 100); ctx.stroke();
                                            }
                                        }
                                    }
                                    Connections { target: root; function onBatColorChanged() { ring.requestPaint(); } }
                                    Column {
                                        anchors.centerIn: parent
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.batPct >= 0 ? root.batPct + "%" : "--"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(24); color: root.text }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.batPct < 0 ? "no battery" : (root.batCharging ? "charging" : "on battery"); font.family: "JetBrains Mono"; font.pixelSize: root.s(9); color: root.batColor }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: root.s(10)
                                    Text { text: "BATTERY"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 1.5; color: root.mauve }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Low-battery alerts"; font.family: "JetBrains Mono"; font.pixelSize: root.s(12); color: root.text }
                                        Item { Layout.fillWidth: true }
                                        Toggle { hub: root; on: root.cfg.battery_alerts; onFlipped: root.setKey("battery_alerts", !root.cfg.battery_alerts) }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        opacity: root.cfg.battery_alerts ? 1 : 0.4
                                        Text { text: "Warn at"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                                        Item { Layout.fillWidth: true }
                                        Stepper { hub: root; value: root.cfg.battery_warn; from: 5; to: 95; step: 5; suffix: "%"; onEdited: (v) => root.setKey("battery_warn", v) }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        opacity: root.cfg.battery_alerts ? 1 : 0.4
                                        Text { text: "Critical at"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                                        Item { Layout.fillWidth: true }
                                        Stepper { hub: root; value: root.cfg.battery_crit; from: 1; to: 95; step: 1; suffix: "%"; onEdited: (v) => root.setKey("battery_crit", v) }
                                    }
                                    Btn { hub: root; Layout.fillWidth: true; label: "Send test alert"; accent: root.peach; onClicked: Quickshell.execDetached(["python3", root.daemon, "alert-test"]) }
                                }
                            }
                        }
                    }
                }

                // ---- footer ----
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Changes apply instantly  \u00b7  Esc close"; font.family: "JetBrains Mono"; font.pixelSize: root.s(11); color: root.subtext0 }
                    Item { Layout.fillWidth: true }
                    Btn { hub: root; label: "Open guide"; accent: root.mauve; onClicked: Quickshell.execDetached(["bash", root.mgr, "toggle", "guide"]) }
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
        }
    }
}
