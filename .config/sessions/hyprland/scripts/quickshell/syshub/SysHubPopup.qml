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
    readonly property color overlay0: _theme.overlay0
    readonly property color mauve: _theme.mauve
    readonly property color pink: _theme.pink
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    readonly property string mono: "JetBrains Mono"
    readonly property string home: Quickshell.env("HOME")
    readonly property string script: home + "/.config/hypr/scripts/syshub.py"
    readonly property string fixFile: home + "/.cache/syshub/fix.json"
    readonly property string fixLog: home + "/.cache/syshub/fix.log"

    property int page: 0
    property var sys: null
    property var checks: []
    property real shownScore: 0
    property real gx: 0
    property string fixId: ""
    property string fixStatus: ""
    property string fixTail: ""
    property real fixStartTs: 0
    readonly property bool scanning: scanProc.running
    readonly property var meta: sys ? sys.meta : null
    readonly property color scoreCol: shownScore >= 85 ? green : shownScore >= 60 ? peach : red

    Behavior on shownScore { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }

    function stCol(st) { return st === "ok" ? green : st === "warn" ? peach : st === "crit" ? red : blue }
    function rank(st) { return st === "crit" ? 0 : st === "warn" ? 1 : st === "info" ? 2 : 3 }
    function fmtB(b) { var g = b / 1073741824; return g >= 1 ? g.toFixed(1) + " GB" : (b / 1048576).toFixed(0) + " MB" }
    function fmtUp(sec) {
        var d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return (d > 0 ? d + "d " : "") + h + "h " + m + "m"
    }
    function ago(ts) {
        if (!ts) return "--"
        var d = Math.max(0, Math.floor(Date.now() / 1000 - ts))
        return d < 60 ? d + "s ago" : d < 3600 ? Math.floor(d / 60) + "m ago" : Math.floor(d / 3600) + "h ago"
    }
    function applyDoctor(txt) {
        var d
        try { d = JSON.parse(txt) } catch (e) { return }
        if (!d || !d.checks) return
        d.checks.sort(function (a, b) { return rank(a.status) - rank(b.status) })
        sys = d
        checks = d.checks
        shownScore = d.score
    }
    function startFix(id) {
        if (fixStatus === "running") return
        fixId = id; fixStatus = "running"; fixTail = ""
        fixStartTs = Date.now() / 1000
        fixStart.running = true
        pollTimer.restart()
    }
    function onFixPoll(txt) {
        var i = txt.indexOf("\n")
        if (i < 0) return
        fixTail = txt.substring(i + 1).trim()
        try {
            var st = JSON.parse(txt.substring(0, i))
            if (st.id === fixId && st.ts >= fixStartTs - 2) fixStatus = st.status
        } catch (e) {}
        if (fixStatus === "done" || fixStatus === "error") {
            pollTimer.stop()
            scanProc.running = true
            clearTimer.restart()
        }
    }

    Process {
        id: lastProc
        command: ["python3", root.script, "last"]
        stdout: StdioCollector { onStreamFinished: root.applyDoctor(text) }
    }
    Process {
        id: scanProc
        command: ["python3", root.script, "doctor"]
        stdout: StdioCollector { onStreamFinished: root.applyDoctor(text) }
    }
    Process { id: fixStart; command: ["python3", root.script, "fix", root.fixId] }
    Process {
        id: fixPoll
        command: ["sh", "-c", "cat '" + root.fixFile + "' 2>/dev/null; echo; tail -n 3 '" + root.fixLog + "' 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.onFixPoll(text) }
    }
    Timer { id: pollTimer; interval: 800; repeat: true; onTriggered: if (!fixPoll.running) fixPoll.running = true }
    Timer { id: clearTimer; interval: 7000; onTriggered: { root.fixStatus = ""; root.fixId = ""; root.fixTail = "" } }
    Timer { interval: 3200; running: true; repeat: true; onTriggered: glitch.start() }
    SequentialAnimation {
        id: glitch
        NumberAnimation { target: root; property: "gx"; to: root.s(4); duration: 45 }
        NumberAnimation { target: root; property: "gx"; to: -root.s(3); duration: 45 }
        NumberAnimation { target: root; property: "gx"; to: root.s(2); duration: 40 }
        NumberAnimation { target: root; property: "gx"; to: 0; duration: 60 }
    }

    Component.onCompleted: { lastProc.running = true; scanProc.running = true }

    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Escape)
            Quickshell.execDetached(["bash", root.home + "/.config/hypr/scripts/qs_manager.sh", "close"])
        else if (e.key === Qt.Key_1) root.page = 0
        else if (e.key === Qt.Key_2) root.page = 1
        else if (e.key === Qt.Key_R && !scanProc.running) scanProc.running = true
    }

    // ---------- reusable pieces ----------
    component Card: Rectangle {
        id: cd
        property var hub: null
        property string title: ""
        property color accent: hub.mauve
        default property alias body: slot.data
        radius: hub.s(14)
        color: Qt.alpha(hub.surface0, 0.55)
        border.width: 1
        border.color: Qt.alpha(cd.accent, 0.35)
        Rectangle {
            width: cd.hub.s(3); height: parent.height * 0.5; radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: cd.accent
        }
        Text {
            id: ttl
            x: cd.hub.s(18); y: cd.hub.s(12)
            text: cd.title
            color: cd.accent
            font.family: cd.hub.mono; font.pixelSize: cd.hub.s(10); font.bold: true
            font.letterSpacing: cd.hub.s(2)
        }
        Item {
            id: slot
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; top: ttl.bottom
                      leftMargin: cd.hub.s(18); rightMargin: cd.hub.s(18); bottomMargin: cd.hub.s(12); topMargin: cd.hub.s(6) }
        }
    }

    component Bar: Rectangle {
        id: br
        property var hub: null
        property real frac: 0
        property color c: hub.mauve
        height: hub.s(8); radius: height / 2
        color: Qt.alpha(hub.surface1, 0.9)
        Rectangle {
            height: parent.height; radius: height / 2
            width: br.width * Math.min(1, Math.max(0, br.frac))
            color: br.c
            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
        }
    }

    // ---------- panel ----------
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: root.s(20)
        color: Qt.alpha(root.crust, 0.94)
        border.width: 1
        border.color: Qt.alpha(root.mauve, 0.45)
        clip: true

        Canvas {
            anchors.fill: parent
            opacity: 0.07
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.strokeStyle = root.mauve
                c.lineWidth = 1
                var g = root.s(32)
                for (var x = 0; x < width; x += g) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, height); c.stroke() }
                for (var y = 0; y < height; y += g) { c.beginPath(); c.moveTo(0, y); c.lineTo(width, y); c.stroke() }
            }
        }

        Rectangle {
            id: beam
            width: parent.width; height: root.s(140)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.alpha(root.mauve, 0.10) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            NumberAnimation on y { from: -beam.height; to: panel.height; duration: 7000; loops: Animation.Infinite }
        }

        Repeater {
            model: 4
            delegate: Item {
                required property int index
                width: root.s(24); height: root.s(24)
                x: index % 2 === 0 ? root.s(10) : panel.width - width - root.s(10)
                y: index < 2 ? root.s(10) : panel.height - height - root.s(10)
                Rectangle {
                    width: parent.width; height: 2; color: root.pink; opacity: 0.8
                    y: index < 2 ? 0 : parent.height - 2
                }
                Rectangle {
                    width: 2; height: parent.height; color: root.pink; opacity: 0.8
                    x: index % 2 === 0 ? 0 : parent.width - 2
                }
            }
        }

        // ---------- sidebar ----------
        Rectangle {
            id: side
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: root.s(250)
            color: Qt.alpha(root.base, 0.55)
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(root.mauve, 0.25) }

            Item {
                x: root.s(26); y: root.s(34); width: parent.width - root.s(52); height: root.s(56)
                Text { x: root.gx; text: "SYSTEM//HUB"; color: root.pink; opacity: 0.8
                       font.family: root.mono; font.pixelSize: root.s(22); font.bold: true }
                Text { x: -root.gx; text: "SYSTEM//HUB"; color: root.blue; opacity: 0.8
                       font.family: root.mono; font.pixelSize: root.s(22); font.bold: true }
                Text { text: "SYSTEM//HUB"; color: root.text
                       font.family: root.mono; font.pixelSize: root.s(22); font.bold: true }
                Text { y: root.s(32); text: "ARCH  //  DIAGNOSTICS"; color: root.subtext0
                       font.family: root.mono; font.pixelSize: root.s(9); font.letterSpacing: root.s(2) }
            }

            Column {
                x: root.s(16); y: root.s(120)
                spacing: root.s(8)
                Repeater {
                    model: [
                        { n: "01", t: "OVERVIEW", on: true },
                        { n: "02", t: "DIAGNOSTICS", on: true },
                        { n: "03", t: "UPDATES", on: false },
                        { n: "04", t: "INSTALL", on: false }
                    ]
                    delegate: Rectangle {
                        id: tab
                        required property var modelData
                        required property int index
                        readonly property bool active: root.page === index
                        width: side.width - root.s(32); height: root.s(48); radius: root.s(10)
                        color: active ? Qt.alpha(root.mauve, 0.16) : tma.containsMouse && modelData.on ? Qt.alpha(root.surface1, 0.4) : "transparent"
                        border.width: active ? 1 : 0
                        border.color: Qt.alpha(root.mauve, 0.6)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: root.s(3); height: active ? parent.height * 0.6 : 0; radius: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.pink
                            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                        Text { x: root.s(18); anchors.verticalCenter: parent.verticalCenter
                               text: modelData.n; color: tab.active ? root.pink : root.overlay0
                               font.family: root.mono; font.pixelSize: root.s(11); font.bold: true }
                        Text { x: root.s(48); anchors.verticalCenter: parent.verticalCenter
                               text: modelData.t; color: modelData.on ? (tab.active ? root.text : root.subtext1) : root.overlay0
                               font.family: root.mono; font.pixelSize: root.s(12); font.bold: true; font.letterSpacing: root.s(1) }
                        Text { visible: !modelData.on; anchors { right: parent.right; rightMargin: root.s(14); verticalCenter: parent.verticalCenter }
                               text: "SOON"; color: root.overlay0
                               font.family: root.mono; font.pixelSize: root.s(8); font.letterSpacing: root.s(1) }
                        MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true
                                    onClicked: if (tab.modelData.on) root.page = tab.index }
                    }
                }
            }

            Text {
                anchors { left: parent.left; leftMargin: root.s(26); bottom: scanBtn.top; bottomMargin: root.s(10) }
                text: "LAST SCAN  " + root.ago(root.sys ? root.sys.ts : 0)
                color: root.subtext0
                font.family: root.mono; font.pixelSize: root.s(9); font.letterSpacing: root.s(1)
            }

            Rectangle {
                id: scanBtn
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: root.s(20) }
                height: root.s(52); radius: root.s(12)
                color: sma.containsMouse ? Qt.alpha(root.pink, 0.2) : Qt.alpha(root.pink, 0.08)
                border.width: 1; border.color: root.pink
                clip: true
                Behavior on color { ColorAnimation { duration: 150 } }
                Rectangle {
                    visible: root.scanning
                    width: root.s(70); height: parent.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 0.5; color: Qt.alpha(root.pink, 0.45) }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    NumberAnimation on x { running: root.scanning; from: -root.s(70); to: scanBtn.width; duration: 900; loops: Animation.Infinite }
                }
                Text {
                    anchors.centerIn: parent
                    text: root.scanning ? "SCANNING..." : "SCAN SYSTEM  [R]"
                    color: root.pink
                    font.family: root.mono; font.pixelSize: root.s(12); font.bold: true; font.letterSpacing: root.s(2)
                }
                MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true
                            onClicked: if (!scanProc.running) scanProc.running = true }
            }
        }

        // ---------- content ----------
        Item {
            id: content
            anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom; margins: root.s(30) }

            Item {
                id: header
                width: parent.width; height: root.s(60)
                Text {
                    text: root.page === 0 ? "OVERVIEW" : "DIAGNOSTICS"
                    color: root.text
                    font.family: root.mono; font.pixelSize: root.s(26); font.bold: true; font.letterSpacing: root.s(3)
                }
                Text {
                    y: root.s(36)
                    text: root.sys ? root.sys.counts.crit + " CRITICAL  /  " + root.sys.counts.warn + " WARNINGS  /  " + root.sys.counts.ok + " NOMINAL"
                                    : "ACQUIRING TELEMETRY..."
                    color: root.subtext0
                    font.family: root.mono; font.pixelSize: root.s(10); font.letterSpacing: root.s(2)
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1; color: Qt.alpha(root.mauve, 0.3)
                    clip: true
                    Rectangle {
                        visible: root.scanning
                        width: root.s(180); height: 3; y: -1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: root.pink }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        NumberAnimation on x { running: root.scanning; from: -root.s(180); to: header.width; duration: 1100; loops: Animation.Infinite }
                    }
                }
            }

            // ===== page 0: overview =====
            Item {
                id: pOverview
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: root.s(22) }
                opacity: root.page === 0 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }

                RowLayout {
                    anchors.fill: parent
                    spacing: root.s(28)

                    Item {
                        Layout.preferredWidth: root.s(330)
                        Layout.fillHeight: true

                        Item {
                            id: ringBox
                            width: root.s(320); height: root.s(320)
                            anchors.horizontalCenter: parent.horizontalCenter

                            Item {
                                anchors.fill: parent
                                RotationAnimator on rotation { from: 0; to: 360; duration: 90000; loops: Animation.Infinite }
                                Repeater {
                                    model: 72
                                    delegate: Item {
                                        required property int index
                                        anchors.fill: parent
                                        rotation: index * 5
                                        Rectangle {
                                            width: root.s(2)
                                            height: index % 6 === 0 ? root.s(14) : root.s(6)
                                            x: parent.width / 2 - width / 2; y: 0
                                            color: index % 6 === 0 ? root.scoreCol : root.overlay0
                                            opacity: index % 6 === 0 ? 0.95 : 0.5
                                        }
                                    }
                                }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width - root.s(56); height: width; radius: width / 2
                                color: "transparent"; border.width: 1; border.color: Qt.alpha(root.mauve, 0.22)
                            }
                            Canvas {
                                id: ring
                                anchors.fill: parent
                                anchors.margins: root.s(34)
                                property real v: root.shownScore
                                property color col: root.scoreCol
                                onVChanged: requestPaint()
                                onColChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onPaint: {
                                    var c = getContext("2d")
                                    c.clearRect(0, 0, width, height)
                                    var cx = width / 2, cy = height / 2, r = width / 2 - root.s(14)
                                    var a0 = -Math.PI / 2
                                    var a1 = a0 + 2 * Math.PI * Math.max(0.002, v / 100)
                                    c.lineCap = "round"
                                    c.lineWidth = root.s(12)
                                    c.strokeStyle = Qt.alpha(root.surface1, 0.85)
                                    c.beginPath(); c.arc(cx, cy, r, 0, 2 * Math.PI); c.stroke()
                                    c.lineWidth = root.s(28)
                                    c.strokeStyle = Qt.alpha(col, 0.13)
                                    c.beginPath(); c.arc(cx, cy, r, a0, a1); c.stroke()
                                    c.lineWidth = root.s(12)
                                    c.strokeStyle = col
                                    c.beginPath(); c.arc(cx, cy, r, a0, a1); c.stroke()
                                }
                            }
                            Column {
                                anchors.centerIn: parent
                                spacing: root.s(2)
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.sys ? Math.round(root.shownScore) : "--"
                                    color: root.scoreCol
                                    font.family: root.mono; font.pixelSize: root.s(64); font.bold: true
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "HEALTH INDEX"; color: root.subtext0
                                    font.family: root.mono; font.pixelSize: root.s(10); font.letterSpacing: root.s(3)
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: !root.sys ? "SCANNING" : root.shownScore >= 85 ? "NOMINAL" : root.shownScore >= 60 ? "DEGRADED" : "CRITICAL"
                                    color: root.scoreCol
                                    font.family: root.mono; font.pixelSize: root.s(13); font.bold: true; font.letterSpacing: root.s(3)
                                }
                            }
                        }

                        Row {
                            anchors { top: ringBox.bottom; topMargin: root.s(16); horizontalCenter: parent.horizontalCenter }
                            spacing: root.s(10)
                            Repeater {
                                model: [ { k: "ok", l: "OK" }, { k: "warn", l: "WARN" }, { k: "crit", l: "CRIT" }, { k: "info", l: "INFO" } ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: root.s(72); height: root.s(44); radius: root.s(10)
                                    color: Qt.alpha(root.stCol(modelData.k), 0.1)
                                    border.width: 1; border.color: Qt.alpha(root.stCol(modelData.k), 0.5)
                                    Column {
                                        anchors.centerIn: parent
                                        Text { anchors.horizontalCenter: parent.horizontalCenter
                                               text: root.sys ? root.sys.counts[modelData.k] : "-"
                                               color: root.stCol(modelData.k)
                                               font.family: root.mono; font.pixelSize: root.s(16); font.bold: true }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter
                                               text: modelData.l; color: root.subtext0
                                               font.family: root.mono; font.pixelSize: root.s(8); font.letterSpacing: root.s(1) }
                                    }
                                }
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        columns: 2
                        rowSpacing: root.s(14); columnSpacing: root.s(14)

                        Card {
                            hub: root; title: "MEMORY"; accent: root.blue
                            Layout.fillWidth: true; Layout.preferredHeight: root.s(112)
                            Text { text: root.meta ? root.fmtB(root.meta.mem_used) + " / " + root.fmtB(root.meta.mem_total) : "--"
                                   color: root.text; font.family: root.mono; font.pixelSize: root.s(15); font.bold: true }
                            Bar { hub: root; c: root.blue; width: parent.width; anchors.bottom: parent.bottom
                                  frac: root.meta && root.meta.mem_total > 0 ? root.meta.mem_used / root.meta.mem_total : 0 }
                        }
                        Card {
                            hub: root; title: "SWAP"; accent: root.sapphire
                            Layout.fillWidth: true; Layout.preferredHeight: root.s(112)
                            Text { text: root.meta ? (root.meta.swap_total > 0 ? root.fmtB(root.meta.swap_used) + " / " + root.fmtB(root.meta.swap_total) : "NONE") : "--"
                                   color: root.text; font.family: root.mono; font.pixelSize: root.s(15); font.bold: true }
                            Bar { hub: root; c: root.sapphire; width: parent.width; anchors.bottom: parent.bottom
                                  frac: root.meta && root.meta.swap_total > 0 ? root.meta.swap_used / root.meta.swap_total : 0 }
                        }
                        Card {
                            hub: root; title: "LOAD AVERAGE"; accent: root.peach
                            Layout.fillWidth: true; Layout.preferredHeight: root.s(112)
                            Text { text: root.meta ? root.meta.load[0].toFixed(2) + "  " + root.meta.load[1].toFixed(2) + "  " + root.meta.load[2].toFixed(2) : "--"
                                   color: root.text; font.family: root.mono; font.pixelSize: root.s(18); font.bold: true }
                            Text { anchors.bottom: parent.bottom; text: "1m   5m   15m"; color: root.subtext0
                                   font.family: root.mono; font.pixelSize: root.s(9); font.letterSpacing: root.s(1) }
                        }
                        Card {
                            hub: root; title: "UPTIME // KERNEL"; accent: root.green
                            Layout.fillWidth: true; Layout.preferredHeight: root.s(112)
                            Text { text: root.meta ? root.fmtUp(root.meta.uptime) : "--"
                                   color: root.text; font.family: root.mono; font.pixelSize: root.s(18); font.bold: true }
                            Text { anchors.bottom: parent.bottom; text: root.meta ? root.meta.kernel : ""; color: root.subtext0
                                   font.family: root.mono; font.pixelSize: root.s(10) }
                        }
                        Card {
                            hub: root; title: "STORAGE"; accent: root.pink
                            Layout.fillWidth: true; Layout.columnSpan: 2; Layout.preferredHeight: root.s(170)
                            Column {
                                anchors.fill: parent
                                spacing: root.s(12)
                                Repeater {
                                    model: root.meta ? root.meta.disks : []
                                    delegate: Item {
                                        required property var modelData
                                        width: parent.width; height: root.s(34)
                                        Text { text: modelData.mount; color: root.text
                                               font.family: root.mono; font.pixelSize: root.s(12); font.bold: true }
                                        Text { anchors.right: parent.right
                                               text: root.fmtB(modelData.used) + " / " + root.fmtB(modelData.total) + "  (" + modelData.pct + "%)"
                                               color: root.subtext1; font.family: root.mono; font.pixelSize: root.s(11) }
                                        Bar { hub: root; width: parent.width; anchors.bottom: parent.bottom
                                              c: modelData.pct >= 90 ? root.red : modelData.pct >= 75 ? root.peach : root.pink
                                              frac: modelData.pct / 100 }
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true; Layout.columnSpan: 2 }
                    }
                }
            }

            // ===== page 1: diagnostics =====
            Item {
                id: pDoctor
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: root.s(18) }
                opacity: root.page === 1 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 220 } }

                ListView {
                    id: lv
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              bottom: fixConsole.visible ? fixConsole.top : parent.bottom; bottomMargin: root.s(10) }
                    clip: true
                    spacing: root.s(10)
                    model: root.checks
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property color sc: root.stCol(modelData.status)
                        width: ListView.view.width; height: root.s(68); radius: root.s(12)
                        color: Qt.alpha(root.surface0, 0.55)
                        border.width: 1; border.color: Qt.alpha(sc, 0.35)
                        opacity: 0; x: root.s(40)
                        Component.onCompleted: enter.start()
                        SequentialAnimation {
                            id: enter
                            PauseAnimation { duration: Math.min(row.index, 12) * 50 }
                            ParallelAnimation {
                                NumberAnimation { target: row; property: "opacity"; to: 1; duration: 300 }
                                NumberAnimation { target: row; property: "x"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                            }
                        }
                        Rectangle {
                            width: root.s(3); height: parent.height * 0.55; radius: 2
                            anchors.verticalCenter: parent.verticalCenter; color: row.sc
                        }
                        Item {
                            id: led
                            x: root.s(22); anchors.verticalCenter: parent.verticalCenter
                            width: root.s(16); height: root.s(16)
                            Rectangle {
                                id: halo
                                anchors.centerIn: parent
                                width: root.s(16); height: width; radius: width / 2
                                color: Qt.alpha(row.sc, 0.25)
                                SequentialAnimation on scale {
                                    running: row.modelData.status === "warn" || row.modelData.status === "crit"
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 1.9; duration: 900; easing.type: Easing.OutQuad }
                                    NumberAnimation { to: 1.0; duration: 100 }
                                }
                            }
                            Rectangle { anchors.centerIn: parent; width: root.s(8); height: width; radius: width / 2; color: row.sc }
                        }
                        Column {
                            anchors { left: led.right; leftMargin: root.s(18); right: fixBtn.left; rightMargin: root.s(14); verticalCenter: parent.verticalCenter }
                            spacing: root.s(5)
                            Row {
                                spacing: root.s(10)
                                Text { text: row.modelData.title.toUpperCase(); color: root.text
                                       font.family: root.mono; font.pixelSize: root.s(13); font.bold: true; font.letterSpacing: root.s(1) }
                                Rectangle {
                                    height: root.s(16); width: tagT.width + root.s(12); radius: root.s(4)
                                    color: Qt.alpha(row.sc, 0.15); border.width: 1; border.color: Qt.alpha(row.sc, 0.6)
                                    Text { id: tagT; anchors.centerIn: parent; text: row.modelData.status.toUpperCase(); color: row.sc
                                           font.family: root.mono; font.pixelSize: root.s(8); font.bold: true; font.letterSpacing: root.s(1) }
                                }
                            }
                            Text { width: parent.width; text: row.modelData.detail; color: root.subtext1; elide: Text.ElideRight
                                   font.family: root.mono; font.pixelSize: root.s(11) }
                        }
                        Rectangle {
                            id: fixBtn
                            visible: row.modelData.fix !== null && row.modelData.fix !== undefined
                            readonly property bool mine: root.fixId === row.modelData.id
                            anchors { right: parent.right; rightMargin: root.s(16); verticalCenter: parent.verticalCenter }
                            width: root.s(160); height: root.s(36); radius: root.s(9)
                            color: fma.containsMouse ? Qt.alpha(row.sc, 0.28) : Qt.alpha(row.sc, 0.1)
                            border.width: 1; border.color: row.sc
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Text {
                                anchors.centerIn: parent
                                text: fixBtn.mine && root.fixStatus === "running" ? "WORKING..."
                                    : fixBtn.mine && root.fixStatus === "done" ? "DONE"
                                    : fixBtn.mine && root.fixStatus === "error" ? "FAILED"
                                    : (row.modelData.fix ? row.modelData.fix.toUpperCase() : "")
                                color: row.sc
                                font.family: root.mono; font.pixelSize: root.s(10); font.bold: true; font.letterSpacing: root.s(1)
                            }
                            MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true
                                        onClicked: root.startFix(row.modelData.id) }
                        }
                    }
                }

                Rectangle {
                    id: fixConsole
                    visible: root.fixStatus !== ""
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: root.s(86); radius: root.s(12)
                    color: Qt.alpha(root.base, 0.9)
                    border.width: 1; border.color: Qt.alpha(root.fixStatus === "error" ? root.red : root.green, 0.6)
                    Text {
                        x: root.s(16); y: root.s(10)
                        text: "FIX // " + root.fixId.toUpperCase() + " // " + root.fixStatus.toUpperCase()
                        color: root.fixStatus === "error" ? root.red : root.green
                        font.family: root.mono; font.pixelSize: root.s(10); font.bold: true; font.letterSpacing: root.s(2)
                    }
                    Text {
                        x: root.s(16); y: root.s(28); width: parent.width - root.s(32)
                        text: root.fixTail; color: root.subtext1; elide: Text.ElideRight; maximumLineCount: 3
                        wrapMode: Text.WrapAnywhere
                        font.family: root.mono; font.pixelSize: root.s(10)
                    }
                }
            }

            Text {
                anchors { right: parent.right; bottom: parent.bottom }
                text: "1/2 PAGES   R RESCAN   ESC CLOSE"
                color: root.overlay0
                font.family: root.mono; font.pixelSize: root.s(9); font.letterSpacing: root.s(1)
            }
        }
    }
}
