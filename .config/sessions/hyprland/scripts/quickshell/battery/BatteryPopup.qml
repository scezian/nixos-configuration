import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // --- RECEIVE THE DBUS LIST FROM MAIN.QML ---
    property var notifModel

    // --- Notification timestamps ---
    property real nowSec: Math.floor(Date.now() / 1000)
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: window.nowSec = Math.floor(Date.now() / 1000)
    }
    function formatTime(t, now) {
        if (!t || t <= 0) return "";
        var diff = Math.max(0, now - t);
        if (diff < 60) return "just now";
        if (diff < 3600) return Math.floor(diff / 60) + "m ago";
        var d = new Date(t * 1000);
        var n = new Date(now * 1000);
        var clock = ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2);
        var startToday = new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime() / 1000;
        if (t >= startToday) return clock;
        if (t >= startToday - 86400) return "Yesterday " + clock;
        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return d.getDate() + " " + months[d.getMonth()] + " " + clock;
    }

    // --- Responsive Scaling Logic ---
    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    function s(val) {
        return scaler.s(val);
    }

    // -------------------------------------------------------------------------
    // REUSABLE PIECES
    // -------------------------------------------------------------------------

    // Soft radial glow, painted only when its colour/size changes
    component GlowBlob: Canvas {
        property color glow: "white"
        onGlowChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            var g = ctx.createRadialGradient(width / 2, height / 2, 0, width / 2, height / 2, width / 2);
            g.addColorStop(0, Qt.rgba(glow.r, glow.g, glow.b, 1.0));
            g.addColorStop(0.5, Qt.rgba(glow.r, glow.g, glow.b, 0.35));
            g.addColorStop(1, Qt.rgba(glow.r, glow.g, glow.b, 0.0));
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, width, height);
        }
    }

    // Glass slider with glowing knob and a live value bubble
    component GlowSlider: Item {
        id: gs
        property real value: 0
        property color c1: "white"
        property color c2: "white"
        property real unit: 1
        property bool muted: false
        property bool animateFill: true
        readonly property bool isHovered: gsMa.containsMouse
        readonly property bool isPressed: gsMa.pressed
        signal pressedAt(int pct)
        signal draggedTo(int pct)
        signal released()

        implicitHeight: unit * 26

        function pctAt(mx) {
            var h = track.height;
            return Math.max(0, Math.min(100, Math.round(((mx - h / 2) / Math.max(1, width - h)) * 100)));
        }

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: gs.unit * 14
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.30)
            border.color: Qt.rgba(1, 1, 1, 0.08)
            border.width: 1

            Rectangle {
                id: fillBar
                height: parent.height
                radius: height / 2
                width: height + (parent.width - height) * (gs.value / 100)
                opacity: gs.muted ? 0.45 : (gs.isHovered ? 1.0 : 0.92)
                Behavior on width { enabled: gs.animateFill && !gs.isPressed; NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: gs.muted ? Qt.rgba(1, 1, 1, 0.25) : gs.c1 }
                    GradientStop { position: 1.0; color: gs.muted ? Qt.rgba(1, 1, 1, 0.40) : gs.c2 }
                }

                // glossy top highlight
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.margins: gs.unit * 2
                    height: parent.height * 0.35
                    radius: height / 2
                    color: Qt.rgba(1, 1, 1, 0.22)
                }
            }
        }

        Rectangle {
            id: knob
            anchors.verticalCenter: parent.verticalCenter
            width: gs.unit * (gs.isPressed ? 24 : (gs.isHovered ? 22 : 18))
            height: width
            radius: width / 2
            color: "#ffffff"
            x: fillBar.width - width / 2
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width + gs.unit * 12
                height: width
                radius: width / 2
                color: gs.muted ? Qt.rgba(1, 1, 1, 0.3) : gs.c2
                opacity: gs.isPressed ? 0.38 : 0.2
                z: -1
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
        }

        Rectangle {
            width: bubbleText.implicitWidth + gs.unit * 14
            height: gs.unit * 22
            radius: gs.unit * 8
            x: knob.x + knob.width / 2 - width / 2
            y: -height - gs.unit * 2
            color: Qt.rgba(0, 0, 0, 0.65)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            opacity: gs.isPressed ? 1 : 0
            scale: gs.isPressed ? 1 : 0.8
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            Text {
                id: bubbleText
                anchors.centerIn: parent
                text: Math.round(gs.value) + "%"
                color: "#ffffff"
                font.family: "JetBrains Mono"
                font.weight: Font.Bold
                font.pixelSize: gs.unit * 11
            }
        }

        MouseArea {
            id: gsMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => gs.pressedAt(gs.pctAt(mouse.x))
            onPositionChanged: (mouse) => { if (pressed) gs.draggedTo(gs.pctAt(mouse.x)); }
            onReleased: gs.released()
        }
    }

    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2

    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color red: _theme.red
    readonly property color maroon: _theme.maroon
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color green: _theme.green
    readonly property color teal: _theme.teal
    readonly property color sapphire: _theme.sapphire
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // STATE & POLLING
    // -------------------------------------------------------------------------
    property int batCapacity: 0
    property string batStatus: "Unknown"
    property string powerProfile: "balanced"

    property int upHours: 0
    property int upMins: 0

    property real sysVolume: 0
    property bool sysMuted: false
    property real sysBrightness: 0

    property string currentUserName: ""

    property bool dndEnabled: false

    // State object for collapsible notification groups
    property var collapsedGroups: ({})

    function toggleGroup(groupName) {
        let temp = Object.assign({}, collapsedGroups);
        temp[groupName] = !temp[groupName];
        collapsedGroups = temp;
    }

    function isCollapsed(groupName) {
        return collapsedGroups[groupName] === true;
    }

    // Anti-Jitter Sync States
    property bool isDraggingVol: false
    property bool isDraggingBri: false

    Timer { id: volSyncDelay; interval: 800; onTriggered: window.isDraggingVol = false; triggeredOnStart: true; }
    Timer { id: briSyncDelay; interval: 800; onTriggered: window.isDraggingBri = false; triggeredOnStart: true; }

    readonly property bool isCharging: batStatus === "Charging"
    readonly property bool isDanger: !isCharging && batCapacity < 15

    // Unified hue for Battery
    readonly property color batColorStart: {
        if (isCharging) return window.green;
        if (batCapacity >= 70) return window.blue;
        if (batCapacity >= 30) return window.yellow;
        return window.red;
    }
    readonly property color batColorEnd: Qt.lighter(batColorStart, 1.15)

    // Unified hue for Performance Profile
    readonly property color profileStart: {
        if (powerProfile === "performance") return window.red;
        if (powerProfile === "power-saver") return window.green;
        return window.blue;
    }
    readonly property color profileEnd: Qt.lighter(profileStart, 1.15)

    // Ambient Blobs - aesthetic pairs derived from battery state
    readonly property color ambientPrimary: window.batColorStart
    readonly property color ambientSecondary: {
        if (isCharging) return window.sapphire;
        if (batCapacity >= 70) return window.mauve;
        if (batCapacity >= 30) return window.peach;
        return window.maroon;
    }

    property real animCapacity: 0
    Behavior on animCapacity { NumberAnimation { duration: 1200; easing.type: Easing.OutQuint } }

    onAnimCapacityChanged: batCanvas.requestPaint()
    onBatColorStartChanged: batCanvas.requestPaint()
    onIsChargingChanged: batCanvas.requestPaint()

    // --- Notification card helpers ---
    function appColor(name) {
        var n = (name || "").toLowerCase();
        if (n === "battery") return window.ambientPrimary;
        var pal = [window.peach, window.mauve, window.teal, window.sapphire, window.pink, window.yellow, window.green, window.blue];
        var h = 0;
        for (var i = 0; i < n.length; i++) h = (h * 31 + n.charCodeAt(i)) % 997;
        return pal[h % pal.length];
    }
    function appIcon(name) {
        var n = (name || "").toLowerCase();
        if (n === "battery") return "󰁹";
        if (n.indexOf("firefox") >= 0) return "\uf269";
        if (n.indexOf("spotify") >= 0) return "\uf1bc";
        if (n.indexOf("telegram") >= 0) return "\uf2c6";
        if (n.indexOf("discord") >= 0) return "\uf392";
        if (n.indexOf("mail") >= 0 || n.indexOf("bot") >= 0) return "\uf0e0";
        return "󰂚";
    }
    function countFor(name) {
        if (!notifModel) return 0;
        var c = 0;
        for (var i = 0; i < notifModel.count; i++) {
            if (notifModel.get(i).appName === name) c++;
        }
        return c;
    }

    // --- INIT DND STATE FROM CACHE ---
    Process {
        id: dndInit
        running: true
        command: ["bash", "-c", "mkdir -p ~/.cache && cat ~/.cache/qs_dnd 2>/dev/null || echo '0'"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.dndEnabled = (this.text.trim() === "1");
            }
        }
    }

    Process {
        id: userPoller
        command: ["bash", "-c", "echo $USER"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                window.currentUserName = this.text.trim();
            }
        }
    }

    Process {
        id: sysPoller
        property double holdUntil: 0
        command: ["bash", "-c",
            "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -n1 || echo '0'; " +
            "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -n1 || echo 'Unknown'; " +
            "m=$(cat /run/power_mode 2>/dev/null); case $m in saver|extreme) echo power-saver;; *) powerprofilesctl get 2>/dev/null || echo 'balanced';; esac; " +
            "awk '{print int($1/3600)\"h \"int(($1%3600)/60)\"m\"}' /proc/uptime 2>/dev/null || echo '0h 0m'; " +
            "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print int($2*100), ($3==\"[MUTED]\"?\"off\":\"on\")}' || echo '0 on'; " +
            "brightnessctl -m 2>/dev/null | awk -F, '{print substr($4, 1, length($4)-1)}' || echo '0'"
        ]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 6) {
                    if (window.batCapacity !== parseInt(lines[0])) {
                        window.batCapacity = parseInt(lines[0]);
                        window.animCapacity = window.batCapacity;
                    }
                    window.batStatus = lines[1];
                    if (Date.now() > sysPoller.holdUntil) window.powerProfile = lines[2];

                    let upParts = lines[3].split("h ");
                    if (upParts.length === 2) {
                        window.upHours = parseInt(upParts[0]) || 0;
                        window.upMins = parseInt(upParts[1].replace("m", "")) || 0;
                    }

                    if (!window.isDraggingVol) {
                        let volParts = (lines[4] || "0 on").trim().split(" ");
                        window.sysVolume = parseInt(volParts[0]) || 0;
                        window.sysMuted = (volParts[1] === "off");
                    }

                    if (!window.isDraggingBri) {
                        window.sysBrightness = parseInt(lines[5]) || 0;
                    }
                }
            }
        }
    }
    Timer {
        interval: 1500; running: true; repeat: true; triggeredOnStart: true;
        onTriggered: sysPoller.running = true
    }

    // --- Ambient motion drivers ---
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; duration: 90000; loops: Animation.Infinite; running: true
    }

    property real ringOrbit: 0
    NumberAnimation on ringOrbit {
        from: 0; to: 360; duration: 14000; loops: Animation.Infinite; running: true
    }

    // Energy comet travelling along the ring (charging, or on hover). Only runs when needed.
    property real flowPhase: 0
    NumberAnimation on flowPhase {
        from: 0; to: 1
        duration: window.isCharging ? 1500 : 1900
        loops: Animation.Infinite
        running: window.isCharging || heroMa.containsMouse
    }
    onFlowPhaseChanged: {
        if (window.isCharging || heroMa.containsMouse) batCanvas.requestPaint();
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introTop: 0
    property real introNotifs: 0
    property real introCore: 0
    property real introSliders: 0
    property real introActions: 0
    property real introProfiles: 0

    ParallelAnimation {
        running: true

        NumberAnimation { target: window; property: "introMain"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }

        SequentialAnimation {
            PauseAnimation { duration: 100 }
            NumberAnimation { target: window; property: "introTop"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: window; property: "introNotifs"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutQuart }
        }

        SequentialAnimation {
            PauseAnimation { duration: 250 }
            NumberAnimation { target: window; property: "introCore"; from: 0; to: 1.0; duration: 900; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }

        SequentialAnimation {
            PauseAnimation { duration: 350 }
            NumberAnimation { target: window; property: "introSliders"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutQuart }
        }

        SequentialAnimation {
            PauseAnimation { duration: 450 }
            NumberAnimation { target: window; property: "introActions"; from: 0; to: 1.0; duration: 800; easing.type: Easing.OutExpo }
        }

        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: window; property: "introProfiles"; from: 0; to: 1.0; duration: 850; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: window; property: "introMain"; to: 0; duration: 400; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introTop"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introNotifs"; to: 0; duration: 300; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introCore"; to: 0; duration: 350; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introSliders"; to: 0; duration: 250; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introActions"; to: 0; duration: 200; easing.type: Easing.InQuart }
        NumberAnimation { target: window; property: "introProfiles"; to: 0; duration: 150; easing.type: Easing.InQuart }
    }

    // Helper: Safely clear an entire group of notifications by AppName
    function clearGroup(appName) {
        if (!notifModel) return;
        for (let i = notifModel.count - 1; i >= 0; i--) {
            if (notifModel.get(i).appName === appName) {
                notifModel.remove(i);
            }
        }
    }

    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Item {
        anchors.fill: parent
        scale: 0.92 + (0.08 * introMain)
        opacity: introMain
        transform: Translate { y: window.s(15) * (1 - introMain) }

        // ---------------------------------------------------------------
        // GLASS PANEL (translucent so the Hyprland layer blur shows through)
        // ---------------------------------------------------------------
        Rectangle {
            id: panel
            anchors.fill: parent
            radius: window.s(26)
            clip: true
            border.width: 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(window.surface0, 0.80) }
                GradientStop { position: 1.0; color: Qt.alpha(window.base, 0.86) }
            }

            HoverHandler { id: panelHover }

            // Aurora blobs
            GlowBlob {
                width: panel.width * 0.95; height: width
                x: (panel.width / 2 - width / 2) + Math.cos(window.globalOrbitAngle * 2) * window.s(170)
                y: (panel.height / 2 - height / 2) + Math.sin(window.globalOrbitAngle * 2) * window.s(130)
                opacity: 0.28
                glow: window.ambientPrimary
                Behavior on glow { ColorAnimation { duration: 1000 } }
            }
            GlowBlob {
                width: panel.width * 1.05; height: width
                x: (panel.width / 2 - width / 2) + Math.sin(window.globalOrbitAngle * 1.5) * window.s(-170)
                y: (panel.height / 2 - height / 2) + Math.cos(window.globalOrbitAngle * 1.5) * window.s(-130)
                opacity: 0.22
                glow: window.ambientSecondary
                Behavior on glow { ColorAnimation { duration: 1000 } }
            }

            // Cursor spotlight
            GlowBlob {
                width: window.s(320); height: width
                x: panelHover.point.position.x - width / 2
                y: panelHover.point.position.y - height / 2
                glow: window.ambientSecondary
                opacity: panelHover.hovered ? 0.20 : 0.0
                Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 400 } }
                Behavior on glow { ColorAnimation { duration: 1000 } }
            }

            // Rising sparkles
            Repeater {
                model: 16
                Rectangle {
                    property real seed: (index * 0.6180339) % 1.0
                    property real prog: 0
                    width: window.s(2 + (index % 3)); height: width; radius: width / 2
                    x: seed * parent.width + Math.sin(prog * Math.PI * 4) * window.s(10)
                    y: parent.height * (1 - prog)
                    opacity: 0.5 * Math.sin(Math.PI * prog)
                    color: index % 2 === 0 ? window.ambientPrimary : window.ambientSecondary
                    SequentialAnimation on prog {
                        loops: Animation.Infinite
                        PauseAnimation { duration: (index * 700) % 6000 }
                        NumberAnimation { from: 0; to: 1; duration: 9000 + (index * 1100) % 8000 }
                    }
                }
            }

            // Occasional light sweep
            Rectangle {
                id: sweep
                width: window.s(170)
                height: panel.height * 1.7
                y: -panel.height * 0.35
                rotation: 18
                opacity: 0.07
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#ffffff" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                SequentialAnimation on x {
                    loops: Animation.Infinite
                    running: true
                    PauseAnimation { duration: 7000 }
                    NumberAnimation { from: -window.s(220); to: panel.width + window.s(80); duration: 2400; easing.type: Easing.InOutSine }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ==========================================
                // LEFT SIDE: NOTIFICATION CENTER
                // ==========================================
                Item {
                    Layout.preferredWidth: window.s(320)
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(20)
                        anchors.rightMargin: window.s(14)
                        spacing: window.s(12)

                        // --- Header & DND Toggle ---
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(40)
                            spacing: window.s(10)

                            transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                            opacity: introTop

                            Text {
                                text: "Notifications"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(18)
                                color: window.text
                            }

                            Rectangle {
                                visible: window.notifModel && window.notifModel.count > 0
                                Layout.preferredWidth: countText.implicitWidth + window.s(14)
                                Layout.preferredHeight: window.s(20)
                                radius: height / 2
                                color: Qt.alpha(window.ambientPrimary, 0.20)
                                Text {
                                    id: countText
                                    anchors.centerIn: parent
                                    text: window.notifModel ? window.notifModel.count : 0
                                    font.family: "JetBrains Mono"
                                    font.weight: Font.Bold
                                    font.pixelSize: window.s(11)
                                    color: window.ambientPrimary
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // DND Toggle Button
                            Rectangle {
                                Layout.preferredWidth: dndMa.containsMouse ? window.s(40) + dndText.implicitWidth + window.s(8) : window.s(40)
                                Layout.preferredHeight: window.s(40)
                                radius: window.s(14)
                                color: window.dndEnabled ? Qt.alpha(window.red, 0.16) : (dndMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                                border.color: window.dndEnabled ? window.red : (dndMa.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08))
                                border.width: 1
                                clip: true

                                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: window.s(11)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: window.s(8)

                                    Text {
                                        id: dndText
                                        text: window.dndEnabled ? "Silent" : "Mute"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(13)
                                        color: window.dndEnabled ? window.red : window.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: dndMa.containsMouse ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(18)
                                        color: window.dndEnabled ? window.red : (dndMa.containsMouse ? window.text : window.subtext0)
                                        text: window.dndEnabled ? "󰂛" : "󰂚"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: dndMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.dndEnabled = !window.dndEnabled;
                                        Quickshell.execDetached(["sh", "-c", "mkdir -p ~/.cache && echo '" + (window.dndEnabled ? "1" : "0") + "' > ~/.cache/qs_dnd"]);
                                    }
                                }
                            }
                        }

                        // --- Silent mode banner ---
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.dndEnabled ? window.s(32) : 0
                            visible: Layout.preferredHeight > 0
                            radius: window.s(11)
                            color: Qt.alpha(window.red, 0.12)
                            border.color: Qt.alpha(window.red, 0.35)
                            border.width: 1
                            opacity: window.dndEnabled ? 1 : 0
                            clip: true
                            Behavior on Layout.preferredHeight { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                            Behavior on opacity { NumberAnimation { duration: 250 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: window.s(8)
                                Text { text: "󰂛"; font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(15); color: window.red; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "Silent mode is on"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(11); color: window.red; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }

                        // --- Zero State ---
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: !window.notifModel || window.notifModel.count === 0
                            opacity: introNotifs

                            Column {
                                anchors.centerIn: parent
                                spacing: window.s(10)

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.family: "Iosevka Nerd Font"
                                    font.pixelSize: window.s(46)
                                    color: window.ambientPrimary
                                    opacity: 0.55
                                    text: window.dndEnabled ? "󰂛" : "󰂚"
                                    SequentialAnimation on y {
                                        loops: Animation.Infinite; running: true
                                        NumberAnimation { to: -window.s(5); duration: 1800; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 0; duration: 1800; easing.type: Easing.InOutSine }
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    font.family: "JetBrains Mono"
                                    font.weight: Font.Medium
                                    font.pixelSize: window.s(14)
                                    color: window.subtext0
                                    text: "You're all caught up."
                                }
                            }
                        }

                        // --- Notification List ---
                        ListView {
                            id: notifList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: window.notifModel
                            spacing: window.s(8)
                            clip: true

                            opacity: introNotifs
                            transform: Translate { y: window.s(20) * (1 - introNotifs) }

                            ScrollBar.vertical: ScrollBar {
                                active: notifList.moving || notifList.movingVertically
                                width: window.s(4)
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle { implicitWidth: window.s(4); radius: window.s(2); color: Qt.rgba(1, 1, 1, 0.22) }
                            }

                            add: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 400; easing.type: Easing.OutQuint }
                                    NumberAnimation { property: "x"; from: window.s(-40); to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 500; easing.type: Easing.OutBack }
                                }
                            }
                            remove: Transition {
                                ParallelAnimation {
                                    NumberAnimation { property: "opacity"; to: 0.0; duration: 300; easing.type: Easing.OutQuint }
                                    NumberAnimation { property: "x"; to: window.s(50); duration: 300; easing.type: Easing.InQuad }
                                    NumberAnimation { property: "scale"; to: 0.9; duration: 300; easing.type: Easing.OutQuint }
                                }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "y"; duration: 400; easing.type: Easing.OutExpo }
                            }

                            // --- Grouping ---
                            section.property: "appName"
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                id: sectionItem
                                width: ListView.view.width
                                height: window.s(42)
                                property color ac: window.appColor(section)
                                property int groupCount: {
                                    var _c = window.notifModel ? window.notifModel.count : 0;
                                    return window.countFor(section);
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: window.s(8)
                                    anchors.bottomMargin: window.s(2)
                                    color: headerMa.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
                                    radius: window.s(10)
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: window.s(8)
                                        anchors.rightMargin: window.s(6)
                                        spacing: window.s(8)

                                        MouseArea {
                                            id: headerMa
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.toggleGroup(section)

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: window.s(8)

                                                Text {
                                                    font.family: "Iosevka Nerd Font"
                                                    font.pixelSize: window.s(15)
                                                    color: sectionItem.ac
                                                    text: "󰅀"
                                                    rotation: window.isCollapsed(section) ? -90 : 0
                                                    Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                                }

                                                Text {
                                                    text: section.toUpperCase()
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Black
                                                    font.pixelSize: window.s(11)
                                                    font.letterSpacing: window.s(1.5)
                                                    color: window.text
                                                    verticalAlignment: Text.AlignVCenter
                                                }

                                                Rectangle {
                                                    Layout.preferredWidth: Math.max(window.s(20), grpCountText.implicitWidth + window.s(10))
                                                    Layout.preferredHeight: window.s(18)
                                                    radius: height / 2
                                                    color: Qt.alpha(sectionItem.ac, 0.18)
                                                    Text {
                                                        id: grpCountText
                                                        anchors.centerIn: parent
                                                        text: sectionItem.groupCount
                                                        font.family: "JetBrains Mono"
                                                        font.weight: Font.Bold
                                                        font.pixelSize: window.s(10)
                                                        color: sectionItem.ac
                                                    }
                                                }

                                                Item { Layout.fillWidth: true }
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: window.s(26)
                                            Layout.preferredHeight: window.s(26)
                                            radius: window.s(13)
                                            color: groupClearMa.containsMouse ? Qt.alpha(window.red, 0.16) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Text {
                                                anchors.centerIn: parent
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(14)
                                                color: groupClearMa.containsMouse ? window.red : window.overlay1
                                                text: "󰅖"
                                                Behavior on color { ColorAnimation { duration: 150 } }
                                            }

                                            MouseArea {
                                                id: groupClearMa
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: window.clearGroup(section)
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Individual Notification Card ---
                            delegate: Item {
                                id: delegateWrapper
                                width: ListView.view.width
                                property bool isHidden: window.isCollapsed(model.appName)
                                property color ac: window.appColor(model.appName)
                                height: isHidden ? 0 : innerCard.height
                                visible: height > 0
                                opacity: isHidden ? 0 : 1
                                clip: true

                                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                                Rectangle {
                                    id: innerCard
                                    width: parent.width
                                    height: Math.max(cardRow.implicitHeight + window.s(24), window.s(56))
                                    radius: window.s(16)
                                    color: cardHover.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.055)
                                    border.color: cardHover.containsMouse ? Qt.alpha(delegateWrapper.ac, 0.55) : Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    // hover colour wash from the left
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: parent.radius
                                        opacity: cardHover.containsMouse ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Qt.alpha(delegateWrapper.ac, 0.16) }
                                            GradientStop { position: 0.6; color: "transparent" }
                                        }
                                    }

                                    MouseArea {
                                        id: cardHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                    }

                                    // accent bar that grows in on hover
                                    Rectangle {
                                        width: window.s(3)
                                        height: cardHover.containsMouse ? parent.height * 0.6 : 0
                                        radius: width / 2
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: delegateWrapper.ac
                                        Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                                    }

                                    RowLayout {
                                        id: cardRow
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: window.s(12)
                                        spacing: window.s(10)

                                        Rectangle {
                                            Layout.alignment: Qt.AlignTop
                                            Layout.preferredWidth: window.s(34)
                                            Layout.preferredHeight: window.s(34)
                                            radius: window.s(11)
                                            color: Qt.alpha(delegateWrapper.ac, 0.18)
                                            border.color: Qt.alpha(delegateWrapper.ac, 0.38)
                                            border.width: 1
                                            scale: cardHover.containsMouse ? 1.08 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                            Text {
                                                anchors.centerIn: parent
                                                font.family: "Iosevka Nerd Font"
                                                font.pixelSize: window.s(17)
                                                color: delegateWrapper.ac
                                                text: window.appIcon(model.appName)
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: window.s(3)

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: window.s(8)

                                                Text {
                                                    text: model.summary || "Notification"
                                                    font.family: "JetBrains Mono"
                                                    font.weight: Font.Bold
                                                    font.pixelSize: window.s(13)
                                                    color: window.text
                                                    Layout.fillWidth: true
                                                    wrapMode: Text.Wrap
                                                }

                                                Text {
                                                    text: window.formatTime(model.time, window.nowSec)
                                                    visible: text !== ""
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: window.s(10)
                                                    color: window.overlay1
                                                }

                                                Rectangle {
                                                    Layout.preferredWidth: window.s(22)
                                                    Layout.preferredHeight: window.s(22)
                                                    radius: window.s(11)
                                                    color: itemClearMa.containsMouse ? Qt.alpha(window.red, 0.18) : "transparent"
                                                    Behavior on color { ColorAnimation { duration: 150 } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        font.family: "Iosevka Nerd Font"
                                                        font.pixelSize: window.s(12)
                                                        color: itemClearMa.containsMouse ? window.red : window.overlay1
                                                        text: "󰅖"
                                                        Behavior on color { ColorAnimation { duration: 150 } }
                                                    }

                                                    MouseArea {
                                                        id: itemClearMa
                                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (window.notifModel) window.notifModel.remove(index);
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                text: model.body || ""
                                                font.family: "JetBrains Mono"
                                                font.weight: Font.Medium
                                                font.pixelSize: window.s(11)
                                                color: window.subtext0
                                                Layout.fillWidth: true
                                                wrapMode: Text.Wrap
                                                visible: text !== ""
                                                textFormat: Text.PlainText
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Divider ---
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: window.s(30)
                    Layout.bottomMargin: window.s(30)
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.16) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                }

                // ==========================================
                // RIGHT SIDE: HARDWARE & BATTERY CORE
                // ==========================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: window.s(22)
                        spacing: window.s(12)

                        // --- TOP ROW: uptime pill + logout ---
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(42)
                            transform: Translate { y: window.s(-20) * (1.0 - introTop) }
                            opacity: introTop

                            Rectangle {
                                Layout.preferredHeight: window.s(38)
                                Layout.preferredWidth: uptimeRow.implicitWidth + window.s(28)
                                radius: height / 2
                                color: Qt.rgba(1, 1, 1, 0.06)
                                border.color: Qt.rgba(1, 1, 1, 0.09)
                                border.width: 1

                                Row {
                                    id: uptimeRow
                                    anchors.centerIn: parent
                                    spacing: window.s(7)

                                    Text {
                                        text: "\uf017"
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(15)
                                        color: window.ambientPrimary
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 1000 } }
                                    }
                                    Text {
                                        text: "up"
                                        font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: window.s(12)
                                        color: window.subtext0
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: window.upHours.toString().padStart(2, '0')
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16)
                                        color: window.text
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: ":"
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16)
                                        color: window.ambientPrimary
                                        anchors.verticalCenter: parent.verticalCenter
                                        property real pulse: 1.0
                                        opacity: pulse
                                        SequentialAnimation on pulse {
                                            loops: Animation.Infinite; running: true
                                            NumberAnimation { to: 0.2; duration: 800; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                                        }
                                    }
                                    Text {
                                        text: window.upMins.toString().padStart(2, '0')
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(16)
                                        color: window.text
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }

                            // Expanding logout button
                            Rectangle {
                                id: logoutBtn
                                Layout.preferredWidth: logoutMa.containsMouse ? window.s(42) + usernameText.implicitWidth + window.s(12) : window.s(42)
                                Layout.preferredHeight: window.s(42)
                                radius: window.s(15)
                                color: logoutMa.containsMouse ? Qt.alpha(window.red, 0.14) : Qt.rgba(1, 1, 1, 0.05)
                                border.color: logoutMa.containsMouse ? Qt.alpha(window.red, 0.55) : Qt.rgba(1, 1, 1, 0.09)
                                border.width: 1
                                clip: true

                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: window.s(13)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: window.s(12)

                                    Text {
                                        id: usernameText
                                        text: window.currentUserName
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(14)
                                        color: window.text
                                        anchors.verticalCenter: parent.verticalCenter
                                        opacity: logoutMa.containsMouse ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Text {
                                        font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                        color: logoutMa.containsMouse ? window.red : window.subtext0
                                        text: "󰍃"
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                }

                                MouseArea {
                                    id: logoutMa
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        exitAnim.start();
                                        Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/exit.sh"]);
                                        Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]);
                                    }
                                }
                            }
                        }

                        // --- CENTRAL CORE & BATTERY RING ---
                        Item {
                            id: ringBox
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: window.s(250)
                            readonly property real ringSize: Math.min(width, height)

                            opacity: introCore
                            transform: Translate { y: window.s(25) * (1 - introCore) }
                            scale: 0.9 + (0.1 * introCore)

                            // Blurred halo behind the ring
                            Item {
                                id: haloSrc
                                anchors.centerIn: parent
                                width: ringBox.ringSize * 0.78
                                height: width
                                visible: false
                                layer.enabled: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: window.isDanger ? window.red : window.ambientPrimary
                                    Behavior on color { ColorAnimation { duration: 600 } }
                                }
                            }
                            MultiEffect {
                                id: haloFx
                                source: haloSrc
                                anchors.fill: haloSrc
                                autoPaddingEnabled: true
                                blurEnabled: true
                                blurMax: 64
                                blur: 1.0
                                opacity: window.isDanger ? 0.55 : 0.34
                                property real haloScale: 1.0
                                scale: haloScale
                                Behavior on opacity { NumberAnimation { duration: 600 } }
                                SequentialAnimation on haloScale {
                                    loops: Animation.Infinite; running: true
                                    NumberAnimation {
                                        to: heroMa.containsMouse ? 1.18 : (window.isDanger ? 1.12 : 1.07)
                                        duration: heroMa.containsMouse ? 800 : (window.isDanger ? 550 : 2200)
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        to: 1.0
                                        duration: heroMa.containsMouse ? 800 : (window.isDanger ? 550 : 2200)
                                        easing.type: Easing.InOutSine
                                    }
                                }
                            }

                            // Inner glass disc
                            Rectangle {
                                anchors.centerIn: parent
                                width: ringBox.ringSize - window.s(104)
                                height: width
                                radius: width / 2
                                color: Qt.rgba(0, 0, 0, 0.18)
                                border.color: Qt.rgba(1, 1, 1, 0.07)
                                border.width: 1
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.08) }
                                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.12) }
                                }
                            }

                            // Ring canvas
                            Canvas {
                                id: batCanvas
                                anchors.centerIn: parent
                                width: ringBox.ringSize
                                height: width
                                onWidthChanged: requestPaint()

                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);

                                    var cx = width / 2;
                                    var cy = height / 2;
                                    var R = (width / 2) - window.s(34);
                                    var start = -Math.PI / 2;
                                    var frac = Math.max(0.002, window.animCapacity / 100);
                                    var end = start + frac * 2 * Math.PI;
                                    var c1 = window.batColorStart.toString();
                                    var c2 = window.batColorEnd.toString();

                                    ctx.lineCap = "round";

                                    // tick bezel
                                    var n = 72;
                                    for (var i = 0; i < n; i++) {
                                        var a = start + (i / n) * 2 * Math.PI;
                                        var lit = (i / n) <= (window.animCapacity / 100);
                                        var r1 = R + window.s(20);
                                        var r2 = r1 + (lit ? window.s(7) : window.s(4));
                                        ctx.beginPath();
                                        ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
                                        ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2);
                                        ctx.lineWidth = window.s(1.6);
                                        ctx.strokeStyle = lit ? c1 : "#ffffff";
                                        ctx.globalAlpha = lit ? 0.75 : 0.14;
                                        ctx.stroke();
                                    }

                                    // track
                                    ctx.globalAlpha = 0.08;
                                    ctx.lineWidth = window.s(13);
                                    ctx.strokeStyle = "#ffffff";
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, R, 0, 2 * Math.PI);
                                    ctx.stroke();

                                    // layered glow
                                    var gw = [window.s(36), window.s(28), window.s(21)];
                                    var ga = [0.05, 0.08, 0.13];
                                    for (var g = 0; g < 3; g++) {
                                        ctx.globalAlpha = ga[g];
                                        ctx.lineWidth = gw[g];
                                        ctx.strokeStyle = c1;
                                        ctx.beginPath();
                                        ctx.arc(cx, cy, R, start, end);
                                        ctx.stroke();
                                    }

                                    // main arc
                                    var fillGrad = ctx.createLinearGradient(0, height, width, 0);
                                    fillGrad.addColorStop(0, c1);
                                    fillGrad.addColorStop(1, c2);
                                    ctx.globalAlpha = 1.0;
                                    ctx.lineWidth = window.s(13);
                                    ctx.strokeStyle = fillGrad;
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, R, start, end);
                                    ctx.stroke();

                                    // glossy inner line
                                    ctx.globalAlpha = 0.28;
                                    ctx.lineWidth = window.s(3);
                                    ctx.strokeStyle = "#ffffff";
                                    ctx.beginPath();
                                    ctx.arc(cx, cy, R - window.s(2.5), start, end);
                                    ctx.stroke();

                                    // energy comet
                                    var active = window.isCharging || heroMa.containsMouse;
                                    if (active && (end - start) > 0.15) {
                                        var span = end - start;
                                        var ph = window.flowPhase;
                                        var center = window.isCharging ? (start + ph * span) : (end - ph * span);
                                        var env = Math.sin(ph * Math.PI);
                                        var widths = [0.55, 0.28];
                                        var lws = [window.s(13), window.s(13)];
                                        var alphas = [0.22, 0.55];
                                        for (var k = 0; k < 2; k++) {
                                            var sA = Math.max(start, center - widths[k] / 2);
                                            var eA = Math.min(end, center + widths[k] / 2);
                                            if (sA < eA) {
                                                ctx.beginPath();
                                                ctx.arc(cx, cy, R, sA, eA);
                                                ctx.lineWidth = lws[k];
                                                ctx.strokeStyle = "#ffffff";
                                                ctx.globalAlpha = alphas[k] * env;
                                                ctx.stroke();
                                            }
                                        }
                                    }

                                    // end cap knob
                                    var kx = cx + Math.cos(end) * R;
                                    var ky = cy + Math.sin(end) * R;
                                    ctx.globalAlpha = 0.28;
                                    ctx.fillStyle = c2;
                                    ctx.beginPath();
                                    ctx.arc(kx, ky, window.s(13), 0, 2 * Math.PI);
                                    ctx.fill();
                                    ctx.globalAlpha = 1.0;
                                    ctx.fillStyle = "#ffffff";
                                    ctx.beginPath();
                                    ctx.arc(kx, ky, window.s(5.5), 0, 2 * Math.PI);
                                    ctx.fill();
                                }
                            }

                            // Orbiting satellite
                            Item {
                                anchors.centerIn: parent
                                width: ringBox.ringSize
                                height: width
                                rotation: window.ringOrbit

                                Rectangle {
                                    width: window.s(6); height: width; radius: width / 2
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: window.s(-1)
                                    color: window.ambientPrimary
                                    Behavior on color { ColorAnimation { duration: 1000 } }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 3; height: width; radius: width / 2
                                        color: parent.color
                                        opacity: 0.28
                                    }
                                }
                            }

                            // Centre read-out
                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: window.s(4)

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: window.s(6)

                                    Text {
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(26)
                                        color: window.batColorStart
                                        text: window.isCharging ? "󰂄" : (window.batCapacity > 20 ? "󰁹" : "󰂃")
                                        Behavior on color { ColorAnimation { duration: 400 } }
                                        SequentialAnimation on scale {
                                            loops: Animation.Infinite; running: window.isCharging || window.isDanger
                                            NumberAnimation { to: 1.18; duration: window.isDanger ? 450 : 800; easing.type: Easing.InOutSine }
                                            NumberAnimation { to: 1.0; duration: window.isDanger ? 450 : 800; easing.type: Easing.InOutSine }
                                        }
                                    }

                                    Text {
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Black
                                        font.pixelSize: window.s(54)
                                        color: window.text
                                        text: Math.round(window.animCapacity) + "%"
                                    }
                                }

                                Rectangle {
                                    id: statusPill
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: statusText.implicitWidth + window.s(26)
                                    Layout.preferredHeight: window.s(24)
                                    radius: height / 2
                                    color: Qt.alpha(window.batColorStart, 0.14)
                                    border.color: Qt.alpha(window.batColorStart, 0.38)
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 400 } }
                                    Behavior on border.color { ColorAnimation { duration: 400 } }

                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(11)
                                        font.letterSpacing: window.s(2)
                                        color: window.isDanger ? window.red : window.batColorStart
                                        text: window.batStatus.toUpperCase()
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                }
                            }

                            MouseArea {
                                id: heroMa
                                anchors.centerIn: parent
                                width: ringBox.ringSize
                                height: width
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: batCanvas.requestPaint()
                            }
                        }

                        // 1. HARDWARE CONTROLS DOCK (Sliders)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(104)
                            radius: window.s(18)
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            opacity: introSliders
                            transform: Translate { y: window.s(20) * (1.0 - introSliders) }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: window.s(14)
                                spacing: window.s(10)

                                // Brightness
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: window.s(12)

                                    Item {
                                        Layout.preferredWidth: window.s(32)
                                        Layout.preferredHeight: window.s(32)
                                        Text {
                                            anchors.centerIn: parent
                                            text: window.sysBrightness > 66 ? "󰃠" : (window.sysBrightness > 33 ? "󰃟" : "󰃞")
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(22)
                                            color: window.batColorStart
                                            Behavior on color { ColorAnimation { duration: 300 } }
                                        }
                                    }

                                    GlowSlider {
                                        id: briSlider
                                        Layout.fillWidth: true
                                        unit: window.s(1)
                                        value: window.sysBrightness
                                        c1: window.batColorStart
                                        c2: window.batColorEnd
                                        animateFill: !window.isDraggingBri

                                        Timer {
                                            id: briCmdThrottle
                                            interval: 50
                                            property int targetPct: -1
                                            onTriggered: {
                                                if (targetPct >= 0) {
                                                    Quickshell.execDetached(["brightnessctl", "set", targetPct + "%"]);
                                                    targetPct = -1;
                                                }
                                            }
                                        }

                                        function updateBri(pct) {
                                            window.sysBrightness = pct;
                                            briCmdThrottle.targetPct = pct;
                                            if (!briCmdThrottle.running) briCmdThrottle.start();
                                        }

                                        onPressedAt: (pct) => { briSyncDelay.stop(); window.isDraggingBri = true; updateBri(pct); }
                                        onDraggedTo: (pct) => updateBri(pct)
                                        onReleased: briSyncDelay.restart()
                                    }

                                    Text {
                                        Layout.preferredWidth: window.s(38)
                                        horizontalAlignment: Text.AlignRight
                                        text: Math.round(window.sysBrightness) + "%"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                        color: window.subtext0
                                    }
                                }

                                // Volume
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: window.s(12)

                                    Rectangle {
                                        Layout.preferredWidth: window.s(32)
                                        Layout.preferredHeight: window.s(32)
                                        radius: window.s(16)
                                        color: volIconMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"
                                        border.color: volIconMa.containsMouse ? window.profileStart : "transparent"
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        Behavior on border.color { ColorAnimation { duration: 150 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: window.sysMuted || window.sysVolume === 0 ? "󰖁" : (window.sysVolume > 50 ? "󰕾" : "󰖀")
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(22)
                                            color: window.sysMuted ? window.overlay1 : window.profileStart
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        MouseArea {
                                            id: volIconMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                volSyncDelay.stop();
                                                window.isDraggingVol = true;
                                                window.sysMuted = !window.sysMuted;
                                                Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                                                volSyncDelay.restart();
                                            }
                                        }
                                    }

                                    GlowSlider {
                                        id: volSlider
                                        Layout.fillWidth: true
                                        unit: window.s(1)
                                        value: window.sysVolume
                                        muted: window.sysMuted
                                        c1: window.profileStart
                                        c2: window.profileEnd
                                        animateFill: !window.isDraggingVol

                                        Timer {
                                            id: volCmdThrottle
                                            interval: 50
                                            property int targetPct: -1
                                            onTriggered: {
                                                if (targetPct >= 0) {
                                                    if (targetPct > 0 && window.sysMuted) {
                                                        window.sysMuted = false;
                                                        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"]);
                                                    }
                                                    Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", targetPct + "%"]);
                                                    targetPct = -1;
                                                }
                                            }
                                        }

                                        function updateVol(pct) {
                                            window.sysVolume = pct;
                                            volCmdThrottle.targetPct = pct;
                                            if (!volCmdThrottle.running) volCmdThrottle.start();
                                        }

                                        onPressedAt: (pct) => { volSyncDelay.stop(); window.isDraggingVol = true; updateVol(pct); }
                                        onDraggedTo: (pct) => updateVol(pct)
                                        onReleased: volSyncDelay.restart()
                                    }

                                    Text {
                                        Layout.preferredWidth: window.s(38)
                                        horizontalAlignment: Text.AlignRight
                                        text: window.sysMuted ? "mute" : Math.round(window.sysVolume) + "%"
                                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: window.s(12)
                                        color: window.sysMuted ? window.overlay1 : window.subtext0
                                    }
                                }
                            }
                        }

                        // 2. SYSTEM ACTIONS DOCK (hold to confirm)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(62)
                            spacing: window.s(12)

                            Repeater {
                                model: ListModel {
                                    ListElement { cmd: "bash ~/.config/hypr/scripts/lock.sh"; icon: "\uf023"; baseColor: "mauve"; weight: 1.0 }
                                    ListElement { cmd: "bash ~/.config/hypr/scripts/lock.sh & systemctl suspend"; icon: "\uf186"; baseColor: "blue"; weight: 1.0 }
                                    ListElement { cmd: "systemctl reboot"; icon: "󰑓"; baseColor: "yellow"; weight: 2.5 }
                                    ListElement { cmd: "systemctl poweroff -i"; icon: "\uf011"; baseColor: "red"; weight: 3.5 }
                                }

                                delegate: Rectangle {
                                    id: actionCapsule
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: window.s(18)

                                    opacity: introActions
                                    transform: Translate { y: window.s(30) * (1.0 - introActions) + (index * window.s(12) * (1.0 - introActions)) - (actionMa.containsMouse && !actionCapsule.triggered ? window.s(3) : 0) }

                                    property color c1: window[baseColor] || window.surface1
                                    property color c2: Qt.lighter(c1, 1.2)

                                    color: actionMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.055)
                                    border.color: actionMa.containsMouse ? c1 : Qt.rgba(1, 1, 1, 0.10)
                                    border.width: actionMa.containsMouse ? 2 : 1
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on border.color { ColorAnimation { duration: 200 } }

                                    scale: actionMa.pressed ? (0.98 - (0.01 * weight)) : (actionMa.containsMouse ? 1.06 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 400; easing.type: Easing.OutQuart } }

                                    property real fillLevel: 0.0
                                    property bool triggered: false
                                    property real flashOpacity: 0.0

                                    // soft coloured under-glow on hover
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width * 1.1
                                        height: parent.height * 1.1
                                        radius: parent.radius + window.s(4)
                                        color: actionCapsule.c1
                                        opacity: actionMa.containsMouse ? 0.14 : 0.0
                                        z: -1
                                        Behavior on opacity { NumberAnimation { duration: 250 } }
                                    }

                                    Canvas {
                                        id: actionWaveCanvas
                                        anchors.fill: parent

                                        property real wavePhase: 0.0
                                        NumberAnimation on wavePhase {
                                            running: actionCapsule.fillLevel > 0.0 && actionCapsule.fillLevel < 1.0
                                            loops: Animation.Infinite
                                            from: 0; to: Math.PI * 2; duration: 800
                                        }
                                        onWavePhaseChanged: requestPaint()
                                        Connections { target: actionCapsule; function onFillLevelChanged() { actionWaveCanvas.requestPaint() } }

                                        onPaint: {
                                            var ctx = getContext("2d");
                                            ctx.clearRect(0, 0, width, height);
                                            if (actionCapsule.fillLevel <= 0.001) return;

                                            var r = actionCapsule.radius;
                                            var fillY = height * (1.0 - actionCapsule.fillLevel);
                                            ctx.save();
                                            ctx.beginPath();
                                            ctx.moveTo(r, 0);
                                            ctx.lineTo(width - r, 0);
                                            ctx.arcTo(width, 0, width, r, r);
                                            ctx.lineTo(width, height - r);
                                            ctx.arcTo(width, height, width - r, height, r);
                                            ctx.lineTo(r, height);
                                            ctx.arcTo(0, height, 0, height - r, r);
                                            ctx.lineTo(0, r);
                                            ctx.arcTo(0, 0, r, 0, r);
                                            ctx.closePath();
                                            ctx.clip();

                                            ctx.beginPath();
                                            ctx.moveTo(0, fillY);
                                            if (actionCapsule.fillLevel < 0.99) {
                                                var waveAmp = window.s(10) * Math.sin(actionCapsule.fillLevel * Math.PI);
                                                var cp1y = fillY + Math.sin(wavePhase) * waveAmp;
                                                var cp2y = fillY + Math.cos(wavePhase + Math.PI) * waveAmp;
                                                ctx.bezierCurveTo(width * 0.33, cp2y, width * 0.66, cp1y, width, fillY);
                                                ctx.lineTo(width, height);
                                                ctx.lineTo(0, height);
                                            } else {
                                                ctx.lineTo(width, 0);
                                                ctx.lineTo(width, height);
                                                ctx.lineTo(0, height);
                                            }
                                            ctx.closePath();

                                            var grad = ctx.createLinearGradient(0, 0, 0, height);
                                            grad.addColorStop(0, actionCapsule.c1.toString());
                                            grad.addColorStop(1, actionCapsule.c2.toString());
                                            ctx.fillStyle = grad;
                                            ctx.fill();
                                            ctx.restore();
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent; radius: actionCapsule.radius; color: "#ffffff"
                                        opacity: actionCapsule.flashOpacity
                                        PropertyAnimation on opacity { id: cardFlashAnim; to: 0; duration: 500; easing.type: Easing.OutExpo }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(24)
                                        color: actionMa.containsMouse ? window.text : window.subtext0
                                        text: icon
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }

                                    Item {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                        height: actionCapsule.height * actionCapsule.fillLevel
                                        clip: true

                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: (actionCapsule.height / 2) - (height / 2) - (actionCapsule.height - parent.height)
                                            font.family: "Iosevka Nerd Font"
                                            font.pixelSize: window.s(24)
                                            color: window.crust
                                            text: icon
                                        }
                                    }

                                    MouseArea {
                                        id: actionMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: actionCapsule.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor

                                        onPressed: {
                                            if (!actionCapsule.triggered) {
                                                drainAnim.stop();
                                                fillAnim.start();
                                            }
                                        }
                                        onReleased: {
                                            if (!actionCapsule.triggered && actionCapsule.fillLevel < 1.0) {
                                                fillAnim.stop();
                                                drainAnim.start();
                                            }
                                        }
                                    }

                                    NumberAnimation {
                                        id: fillAnim; target: actionCapsule; property: "fillLevel"; to: 1.0
                                        duration: (550 * weight) * (1.0 - actionCapsule.fillLevel); easing.type: Easing.InSine
                                        onFinished: {
                                            actionCapsule.triggered = true; actionCapsule.flashOpacity = 0.6; cardFlashAnim.start();
                                            exitAnim.start(); exitTimer.start();
                                        }
                                    }

                                    NumberAnimation {
                                        id: drainAnim; target: actionCapsule; property: "fillLevel"; to: 0.0
                                        duration: 1500 * actionCapsule.fillLevel; easing.type: Easing.OutQuad
                                    }

                                    Timer {
                                        id: exitTimer; interval: 500
                                        onTriggered: { Quickshell.execDetached(["sh", "-c", cmd]); Quickshell.execDetached(["sh", "-c", "echo 'close' > /tmp/qs_widget_state"]); }
                                    }
                                }
                            }
                        }

                        // 3. POWER PROFILES DOCK
                        Rectangle {
                            id: profileDock
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(54)
                            radius: window.s(18)
                            color: Qt.rgba(1, 1, 1, 0.05)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            opacity: introProfiles
                            transform: Translate { y: window.s(20) * (1.0 - introProfiles) }

                            // sliding pill with glow
                            Item {
                                id: sliderPill
                                width: (parent.width - window.s(6)) / 3
                                height: parent.height - window.s(6)
                                y: window.s(3)
                                x: {
                                    if (window.powerProfile === "performance") return window.s(3);
                                    if (window.powerProfile === "balanced") return width + window.s(3);
                                    return (width * 2) + window.s(3);
                                }
                                Behavior on x { NumberAnimation { duration: 450; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width + window.s(14)
                                    height: parent.height + window.s(14)
                                    radius: window.s(20)
                                    color: window.profileStart
                                    opacity: 0.22
                                    Behavior on color { ColorAnimation { duration: 400 } }
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: window.s(15)
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: window.profileStart; Behavior on color { ColorAnimation { duration: 400 } } }
                                        GradientStop { position: 1.0; color: window.profileEnd; Behavior on color { ColorAnimation { duration: 400 } } }
                                    }

                                    Rectangle {
                                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                                        anchors.margins: window.s(3)
                                        height: parent.height * 0.4
                                        radius: window.s(12)
                                        color: Qt.rgba(1, 1, 1, 0.20)
                                    }
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: window.s(3)
                                spacing: 0

                                Repeater {
                                    model: ListModel {
                                        ListElement { name: "performance"; icon: "󰓅"; label: "Perform" }
                                        ListElement { name: "balanced"; icon: "󰗑"; label: "Balance" }
                                        ListElement { name: "power-saver"; icon: "󰌪"; label: "Saver" }
                                    }

                                    delegate: Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: window.s(8)
                                            scale: profileMa.containsMouse && window.powerProfile !== name ? 1.06 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                                            Text {
                                                font.family: "Iosevka Nerd Font"; font.pixelSize: window.s(18)
                                                color: window.powerProfile === name ? window.crust : (profileMa.containsMouse ? window.text : window.subtext0)
                                                text: icon
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                            Text {
                                                font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: window.s(13)
                                                color: window.powerProfile === name ? window.crust : (profileMa.containsMouse ? window.text : window.subtext0)
                                                text: label
                                                Behavior on color { ColorAnimation { duration: 200 } }
                                            }
                                        }

                                        MouseArea {
                                            id: profileMa
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: { sysPoller.holdUntil = Date.now() + 3000; window.powerProfile = name; Quickshell.execDetached(["bash", "-c", name === "power-saver" ? "sudo -n /usr/local/bin/power_mode saver" : "sudo -n /usr/local/bin/power_mode normal; powerprofilesctl set " + name]); }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // top edge light + glass rim, drawn over everything
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: window.s(30)
                anchors.rightMargin: window.s(30)
                height: 1
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.30) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: panel.radius
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.11)
                border.width: 1
            }
        }
    }
}
