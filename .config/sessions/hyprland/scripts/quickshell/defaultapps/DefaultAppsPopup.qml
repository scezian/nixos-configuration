import QtQuick.Effects
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
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

    property real uiBoost: 1.2
    function s(val) {
        return scaler.s(val) * uiBoost;
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
    readonly property color blue: _theme.blue
    readonly property color pink: _theme.pink
    readonly property color teal: _theme.teal
    readonly property color red: _theme.red
    readonly property color card: Qt.alpha(_theme.mantle, 0.50)
    readonly property color cardBorder: Qt.alpha(_theme.surface1, 0.55)

    readonly property string helper: Quickshell.env("HOME") + "/.config/hypr/scripts/default_apps.py"
    readonly property var modOrder: ["SUPER", "CTRL", "ALT", "SHIFT"]

    // ---------------- state ----------------
    property string page: "apps"            // apps | mine | all
    property bool busy: false
    property bool statusError: false
    property string statusText: "Pick a category, then click an app to make it the default."

    property var cats: []
    property int sel: 0
    property bool loaded: false
    readonly property var cat: (cats.length > sel) ? cats[sel] : null

    property var kb: ({ shortcuts: [], builtin: [], live: [], apps: [], cats: [] })
    property bool kbLoaded: false
    property bool kbLiveOk: true
    property string filterText: ""
    property string appFilter: ""
    property var edit: null
    property string editError: ""
    property var conflict: null

    readonly property string pageTitle: page === "apps" ? "Default apps" : (page === "mine" ? "Shortcuts" : "All binds")
    readonly property string pageHint: page === "apps" ? "Choose what opens each kind of file or link"
        : (page === "mine" ? "Launcher shortcuts you manage, plus built-in launcher binds you can take over"
        : "Everything Hyprland has bound right now")

    readonly property var rows: kb.shortcuts.concat(kb.builtin)
    readonly property var liveRows: {
        var q = filterText.trim().toLowerCase();
        if (q === "") return kb.live;
        return kb.live.filter(function (b) { return (b.combo + " " + b.desc + " " + b.src).toLowerCase().indexOf(q) !== -1; });
    }
    readonly property var appRows: {
        var q = appFilter.trim().toLowerCase();
        if (q === "") return kb.apps;
        var toks = q.split(/\s+/);
        var subseq = function (t, w) { var i = 0; for (var j = 0; j < w.length && i < t.length; j++) if (w[j] === t[i]) i++; return i === t.length; };
        return kb.apps.filter(function (a) {
            var hay = ((a.name || "") + " " + (a.id || "") + " " + (a.exec || "")).toLowerCase();
            var words = hay.split(/[^a-z0-9]+/);
            return toks.every(function (t) {
                if (hay.indexOf(t) !== -1) return true;
                if (t.length < 4) return false;
                return words.some(function (w) { return w.length >= t.length && w.length - t.length <= 2 && subseq(t, w); });
            });
        });
    }
    readonly property string comboPreview: {
        if (!edit) return "";
        var parts = [];
        for (var i = 0; i < modOrder.length; i++)
            if (edit.mods.indexOf(modOrder[i]) !== -1) parts.push(modOrder[i]);
        if (edit.key !== "") parts.push(edit.key.length === 1 ? edit.key.toUpperCase() : edit.key);
        return parts.join(" + ");
    }

    onPageChanged: {
        statusError = false;
        if (page === "apps") {
            statusText = "Pick a category, then click an app to make it the default.";
        } else {
            statusText = page === "mine" ? "Changes apply instantly and are undone if Hyprland rejects them."
                : "Read-only view of the live binds.";
            if (!kbLoaded) refreshKeys();
        }
    }

    function parseOut(t) {
        try { return JSON.parse(t.trim()); } catch (e) { return null; }
    }

    function note(msg, isError) {
        statusError = isError;
        statusText = msg;
    }

    // ---------------- default apps logic ----------------
    function refresh() { reader.running = true; }

    function loadData(txt) {
        var d = parseOut(txt);
        if (!d || !d.length) { note("Couldn't read the app list.", true); return; }
        cats = d;
        loaded = true;
        if (sel >= cats.length) sel = 0;
    }

    function setDefault(app) {
        if (busy || !cat) return;
        busy = true;
        note("Setting " + app.name + "...", false);
        applier.pendingText = cat.label + " is now " + app.name;
        applier.command = ["python3", helper, "set", cat.id, app.id];
        applier.running = true;
    }

    function resetCat() {
        if (busy || !cat) return;
        busy = true;
        note("Resetting " + cat.label + "...", false);
        applier.pendingText = cat.label + " reset to the system default";
        applier.command = ["python3", helper, "reset", cat.id];
        applier.running = true;
    }

    function iconSource(name) {
        if (!name) return "";
        if (name.charAt(0) === "/") return "file://" + name;
        var p = "";
        try { p = Quickshell.iconPath(name, true); } catch (e) { p = ""; }
        return p || "";
    }

    // ---------------- keybinds logic ----------------
    function refreshKeys() { keysReader.running = true; }

    function loadKeys(txt) {
        var d = parseOut(txt);
        if (!d || !d.ok) { note("Couldn't read keybinds.", true); return; }
        kb = d;
        kbLiveOk = d.liveOk;
        kbLoaded = true;
    }

    function capLabel(p) {
        if (p === "SUPER") return "Super";
        if (p === "CTRL") return "Ctrl";
        if (p === "ALT") return "Alt";
        if (p === "SHIFT") return "Shift";
        return p;
    }

    function setEdit(patch) {
        var o = {};
        for (var k in edit) o[k] = edit[k];
        for (var p in patch) o[p] = patch[p];
        edit = o;
    }

    function toggleMod(m) {
        var mods = edit.mods.slice();
        var i = mods.indexOf(m);
        if (i === -1) mods.push(m); else mods.splice(i, 1);
        setEdit({ mods: mods });
        conflict = null;
        editError = "";
    }

    function newShortcut() {
        edit = { id: "", kind: "new", label: "", mods: ["SUPER"], key: "", type: "category", target: "files",
                 origCombo: "", origCmd: "", origin: "", confidence: "" };
        conflict = null;
        editError = "";
        appFilter = "";
    }

    function openEditor(row) {
        var parts = row.combo.split(" + ");
        edit = { id: row.id || "", kind: row.kind, label: row.label, mods: parts.slice(0, -1),
                 key: parts[parts.length - 1], type: row.type, target: row.target, origCombo: row.combo,
                 origCmd: row.command || "", origin: row.origin || "", confidence: row.confidence || "" };
        conflict = null;
        editError = "";
        appFilter = "";
    }

    function saveEdit(take) {
        if (busy || !edit) return;
        var payload = { id: edit.id, label: edit.label, mods: edit.mods, key: edit.key, type: edit.type, target: edit.target };
        var args = ["python3", helper, "key-save", JSON.stringify(payload)];
        if (take || (edit.kind === "builtin" && comboPreview === edit.origCombo)) args.push("--takeover");
        busy = true;
        editError = "";
        conflict = null;
        kbWriter.mode = "save";
        kbWriter.command = args;
        kbWriter.running = true;
    }

    function deleteEdit() {
        if (busy || !edit || edit.id === "") return;
        busy = true;
        editError = "";
        kbWriter.mode = "delete";
        kbWriter.command = ["python3", helper, "key-delete", edit.id];
        kbWriter.running = true;
    }

    function tryEdit() {
        if (busy || !edit) return;
        editError = "";
        tryRunner.command = ["python3", helper, "try", JSON.stringify({ type: edit.type, target: edit.target })];
        tryRunner.running = true;
    }

    function finishWrite(txt) {
        busy = false;
        var r = parseOut(txt);
        if (!r) { editError = "No response from the helper."; return; }
        if (r.ok) {
            edit = null;
            note(r.warn ? r.warn : (kbWriter.mode === "delete" ? "Shortcut deleted." : "Shortcut saved and active."), false);
            refreshKeys();
        } else if (r.conflict) {
            conflict = r.conflict;
            editError = r.conflict.combo + " is already used by: " + r.conflict.desc;
        } else {
            editError = r.error || "Something went wrong.";
        }
    }

    function finishTry(txt) {
        var r = parseOut(txt);
        if (r && r.ok) note("Launched. If nothing opened, check the target.", false);
        else editError = (r && r.error) ? r.error : "Couldn't run it.";
    }

    Component.onCompleted: refresh()

    // ---------------- processes ----------------
    Process {
        id: reader
        command: ["python3", window.helper, "list"]
        stdout: StdioCollector { onStreamFinished: window.loadData(this.text) }
    }
    Process {
        id: keysReader
        command: ["python3", window.helper, "keys"]
        stdout: StdioCollector { onStreamFinished: window.loadKeys(this.text) }
    }
    Process {
        id: applier
        property string pendingText: ""
        stdout: StdioCollector {
            onStreamFinished: {
                window.busy = false;
                var r = window.parseOut(this.text);
                if (r && r.ok) {
                    window.note(applier.pendingText, false);
                    window.refresh();
                } else {
                    window.note(r && r.error ? r.error : "The helper didn't respond.", true);
                }
            }
        }
    }
    Process {
        id: kbWriter
        property string mode: "save"
        stdout: StdioCollector { onStreamFinished: window.finishWrite(this.text) }
    }
    Process {
        id: tryRunner
        stdout: StdioCollector { onStreamFinished: window.finishTry(this.text) }
    }

    // ---------------- reusable pieces (no outer ids inside) ----------------
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        property color onColor: "#cba6f7"
        property color offColor: "#313244"
        property color fgOn: "#11111b"
        property color fgOff: "#cdd6f4"
        property real px: 12
        signal clicked()

        implicitWidth: lbl.implicitWidth + px * 2.4
        implicitHeight: px * 2.5
        radius: height / 2
        color: on ? onColor : (ma.containsMouse ? Qt.lighter(offColor, 1.2) : offColor)
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: lbl
            anchors.centerIn: parent
            text: chip.label
            color: chip.on ? chip.fgOn : chip.fgOff
            font.family: "JetBrains Mono"
            font.pixelSize: chip.px
            font.bold: true
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

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
        Layout.preferredHeight: px * 3.0
        radius: height / 2.6
        color: !active ? Qt.alpha(fill, 0.35) : (bma.containsMouse ? fillHover : fill)
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
            id: bma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
    }

    component NavItem: Rectangle {
        id: nav
        property string label: ""
        property bool on: false
        property color onColor: "#cba6f7"
        property color hoverColor: "#313244"
        property color fgOn: "#11111b"
        property color fgOff: "#cdd6f4"
        property color dot: "#a6adc8"
        property real px: 13
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: px * 3.4
        radius: px
        color: on ? onColor : (nma.containsMouse ? hoverColor : "transparent")
        Behavior on color { ColorAnimation { duration: 140 } }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: nav.px * 1.2
            spacing: nav.px * 0.9
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: nav.px * 0.7
                height: width
                radius: width / 2
                color: nav.on ? nav.fgOn : nav.dot
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: nav.label
                color: nav.on ? nav.fgOn : nav.fgOff
                font.family: "JetBrains Mono"
                font.pixelSize: nav.px
                font.bold: true
            }
        }
        MouseArea {
            id: nma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nav.clicked()
        }
    }

    component KeyCap: Rectangle {
        id: cap
        property string label: ""
        property color fill: "#45475a"
        property color fg: "#cdd6f4"
        property real px: 10
        implicitWidth: ct.implicitWidth + px * 1.6
        implicitHeight: px * 2.2
        radius: px * 0.6
        color: fill
        Text {
            id: ct
            anchors.centerIn: parent
            text: cap.label
            color: cap.fg
            font.family: "JetBrains Mono"
            font.pixelSize: cap.px
            font.bold: true
        }
    }

    component StyledField: TextField {
        id: tf
        property color bg: "#313244"
        property color fg: "#cdd6f4"
        property color hintColor: "#a6adc8"
        property color accent: "#cba6f7"
        property real px: 12
        color: fg
        placeholderTextColor: hintColor
        selectionColor: accent
        selectedTextColor: "#11111b"
        font.family: "JetBrains Mono"
        font.pixelSize: px
        leftPadding: px
        rightPadding: px
        implicitHeight: px * 2.8
        background: Rectangle {
            radius: height / 3
            color: tf.bg
            border.width: tf.activeFocus ? 2 : 0
            border.color: tf.accent
        }
    }

    // soft drifting nebula cloud (radial gradient, fades to nothing at its edge)
    component Glow: Item {
        id: gl
        property color tint: "#cba6f7"
        property real strength: 0.28
        property real size: 600
        property real baseX: 0
        property real baseY: 0
        property real ampX: 40
        property real ampY: 30
        property int period: 20000
        property real dx: 0
        property real dy: 0
        width: size
        height: size
        x: baseX + dx
        y: baseY + dy

        SequentialAnimation on dx {
            running: gl.visible
            loops: Animation.Infinite
            NumberAnimation { from: -gl.ampX; to: gl.ampX; duration: gl.period; easing.type: Easing.InOutSine }
            NumberAnimation { from: gl.ampX; to: -gl.ampX; duration: gl.period; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on dy {
            running: gl.visible
            loops: Animation.Infinite
            NumberAnimation { from: gl.ampY; to: -gl.ampY; duration: gl.period * 1.3; easing.type: Easing.InOutSine }
            NumberAnimation { from: -gl.ampY; to: gl.ampY; duration: gl.period * 1.3; easing.type: Easing.InOutSine }
        }

        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: gl.size / 2
                    centerY: gl.size / 2
                    centerRadius: gl.size / 2
                    focalX: gl.size / 2
                    focalY: gl.size / 2
                    GradientStop { position: 0.0; color: Qt.alpha(gl.tint, Math.min(0.85, gl.strength * 1.6)) }
                    GradientStop { position: 0.55; color: Qt.alpha(gl.tint, Math.min(0.5, gl.strength * 0.8)) }
                    GradientStop { position: 1.0; color: Qt.alpha(gl.tint, 0.0) }
                }
                startX: 0
                startY: 0
                PathLine { x: gl.size; y: 0 }
                PathLine { x: gl.size; y: gl.size }
                PathLine { x: 0; y: gl.size }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // ---------------- background: base + nebula + stars ----------------
    Rectangle {
        anchors.fill: parent
        radius: window.s(24)
        color: Qt.alpha(window.crust, 0.97)
        border.width: 1
        border.color: Qt.alpha(window.mauve, 0.55)
    }

    // breathing frame
    Rectangle {
        anchors.fill: parent
        anchors.margins: -window.s(1)
        radius: window.s(25)
        color: "transparent"
        border.width: window.s(2)
        border.color: window.mauve
        opacity: 0.25
        SequentialAnimation on opacity {
            running: window.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.18; to: 0.6; duration: 3200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.6; to: 0.18; duration: 3200; easing.type: Easing.InOutSine }
        }
    }

    Item {
        anchors.fill: parent
        anchors.margins: window.s(2)
        clip: true

        Glow { tint: window.mauve; strength: 0.50; size: window.s(800); baseX: -window.s(220); baseY: -window.s(260); ampX: window.s(46); ampY: window.s(34); period: 21000 }
        Glow { tint: window.blue; strength: 0.44; size: window.s(860); baseX: window.width - window.s(560); baseY: window.height - window.s(470); ampX: window.s(50); ampY: window.s(38); period: 26000 }
        Glow { tint: window.pink; strength: 0.36; size: window.s(640); baseX: window.width * 0.52; baseY: -window.s(300); ampX: window.s(40); ampY: window.s(30); period: 18000 }
        Glow { tint: window.teal; strength: 0.28; size: window.s(600); baseX: -window.s(180); baseY: window.height - window.s(330); ampX: window.s(36); ampY: window.s(30); period: 23000 }
        Glow { tint: window.mauve; strength: 0.24; size: window.s(480); baseX: window.width * 0.42; baseY: window.height * 0.38; ampX: window.s(60); ampY: window.s(40); period: 29000 }
        Glow { tint: window.pink; strength: 0.30; size: window.s(520); baseX: window.width - window.s(380); baseY: window.height * 0.15; ampX: window.s(48); ampY: window.s(36); period: 24000 }
        Glow { tint: window.teal; strength: 0.22; size: window.s(460); baseX: window.width * 0.25; baseY: -window.s(200); ampX: window.s(42); ampY: window.s(30); period: 27000 }

        Repeater {
            model: 90
            delegate: Rectangle {
                required property int index
                x: (((index * 7919 + 13) % 1000) / 1000) * (window.width - window.s(8)) + window.s(4)
                y: (((index * 104729 + 71) % 997) / 997) * (window.height - window.s(8)) + window.s(4)
                width: index % 11 === 0 ? window.s(4) : (index % 6 === 0 ? window.s(2.8) : window.s(1.6))
                height: width
                radius: width / 2
                color: index % 3 === 0 ? window.pink : (index % 3 === 1 ? window.blue : window.text)
                opacity: 0.4
                SequentialAnimation on opacity {
                    running: window.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: 0.12; to: 0.85; duration: 1800 + (index % 7) * 430; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.85; to: 0.12; duration: 1800 + (index % 7) * 430; easing.type: Easing.InOutSine }
                }
            }
        }
    }

    // ---------------- layout: sidebar + main ----------------
    RowLayout {
        anchors.fill: parent
        anchors.margins: window.s(18)
        spacing: window.s(16)

        // ===== sidebar =====
        Rectangle {
            Layout.preferredWidth: window.s(224)
            Layout.fillHeight: true
            radius: window.s(20)
            color: window.card
            border.width: 1
            border.color: window.cardBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: window.s(14)
                spacing: window.s(4)

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: window.s(8)
                    spacing: window.s(10)
                    Rectangle {
                        Layout.preferredWidth: window.s(40)
                        Layout.preferredHeight: window.s(40)
                        radius: window.s(12)
                        color: Qt.alpha(window.mauve, 0.92)
                        Rectangle {
                            anchors.centerIn: parent
                            width: window.s(20)
                            height: window.s(20)
                            radius: window.s(6)
                            color: "transparent"
                            border.width: window.s(2)
                            border.color: window.crust
                            Rectangle {
                                anchors.centerIn: parent
                                width: window.s(6)
                                height: window.s(6)
                                radius: window.s(2)
                                color: window.crust
                            }
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Defaults"
                            color: window.text
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(15)
                            font.bold: true
                        }
                        Text {
                            text: "& keybinds"
                            color: window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(10)
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: window.cardBorder
                    Layout.bottomMargin: window.s(8)
                }

                Text {
                    text: "DEFAULTS"
                    color: window.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(9)
                    font.bold: true
                    leftPadding: window.s(6)
                }
                NavItem {
                    label: "Default apps"
                    px: window.s(13)
                    on: window.page === "apps"
                    onColor: window.mauve
                    hoverColor: Qt.alpha(window.surface1, 0.7)
                    fgOn: window.crust
                    fgOff: window.text
                    dot: window.subtext0
                    onClicked: window.page = "apps"
                }

                Text {
                    text: "KEYBINDS"
                    color: window.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(9)
                    font.bold: true
                    leftPadding: window.s(6)
                    topPadding: window.s(10)
                }
                NavItem {
                    label: "Shortcuts"
                    px: window.s(13)
                    on: window.page === "mine"
                    onColor: window.mauve
                    hoverColor: Qt.alpha(window.surface1, 0.7)
                    fgOn: window.crust
                    fgOff: window.text
                    dot: window.subtext0
                    onClicked: window.page = "mine"
                }
                NavItem {
                    label: "All binds"
                    px: window.s(13)
                    on: window.page === "all"
                    onColor: window.mauve
                    hoverColor: Qt.alpha(window.surface1, 0.7)
                    fgOn: window.crust
                    fgOff: window.text
                    dot: window.subtext0
                    onClicked: window.page = "all"
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    id: profileCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: profCol.implicitHeight + window.s(24)
                    radius: window.s(14)
                    color: Qt.alpha(window.surface0, 0.5)
                    border.width: 1
                    border.color: window.statusError ? Qt.alpha(window.red, 0.6) : window.cardBorder

                    function saveName() {
                        var n = nameField.text.trim();
                        if (n === "") return;
                        nameWriter.pending = n;
                        nameWriter.running = false;
                        nameWriter.running = true;
                        window.note("Username set to " + n, false);
                    }

                    Component.onCompleted: nameReader.running = true
                    Process {
                        id: nameReader
                        command: ["bash", "-c", "cat ~/.config/hypr/display_name 2>/dev/null"]
                        stdout: StdioCollector {
                            onStreamFinished: {
                                var t = this.text.trim();
                                if (t !== "") nameField.text = t;
                            }
                        }
                    }
                    Process {
                        id: nameWriter
                        property string pending: ""
                        command: ["python3", "-c", "import sys,pathlib; pathlib.Path.home().joinpath('.config/hypr/display_name').write_text(sys.argv[1])", pending]
                    }

                    // ambient avatar backdrop
                    Image {
                        id: ambSrc
                        width: parent.width * 1.7
                        height: parent.height * 1.7
                        x: -parent.width * 0.35
                        y: -parent.height * 0.35
                        source: "file:///usr/share/sddm/faces/scez.face.icon"
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(128, 128)
                        cache: false
                        visible: false
                        SequentialAnimation on x {
                            running: window.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: -profileCard.width * 0.5; to: -profileCard.width * 0.2; duration: 14000; easing.type: Easing.InOutSine }
                            NumberAnimation { from: -profileCard.width * 0.2; to: -profileCard.width * 0.5; duration: 14000; easing.type: Easing.InOutSine }
                        }
                        SequentialAnimation on y {
                            running: window.visible
                            loops: Animation.Infinite
                            NumberAnimation { from: -profileCard.height * 0.2; to: -profileCard.height * 0.5; duration: 17000; easing.type: Easing.InOutSine }
                            NumberAnimation { from: -profileCard.height * 0.5; to: -profileCard.height * 0.2; duration: 17000; easing.type: Easing.InOutSine }
                        }
                    }
                    Rectangle {
                        id: ambMask
                        anchors.fill: parent
                        radius: profileCard.radius
                        color: "black"
                        visible: false
                        layer.enabled: true
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: ambSrc
                        autoPaddingEnabled: false
                        blurEnabled: true
                        blur: 1.0
                        blurMax: 64
                        saturation: 0.35
                        brightness: 0.0
                        maskEnabled: true
                        maskSource: ambMask
                        opacity: 0.95
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: profileCard.radius
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(window.crust, 0.10) }
                            GradientStop { position: 1.0; color: Qt.alpha(window.crust, 0.55) }
                        }
                    }

                    ColumnLayout {
                        id: profCol
                        anchors.fill: parent
                        anchors.margins: window.s(12)
                        spacing: window.s(8)

                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: window.s(72)
                            Layout.preferredHeight: window.s(72)
                            Image {
                                id: avImg
                                anchors.fill: parent
                                source: "file:///usr/share/sddm/faces/scez.face.icon"
                                fillMode: Image.PreserveAspectCrop
                                cache: false
                                sourceSize: Qt.size(256, 256)
                                visible: false
                            }
                            Rectangle {
                                id: avMask
                                anchors.fill: parent
                                radius: width / 2
                                color: "black"
                                visible: false
                                layer.enabled: true
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: avImg
                                maskEnabled: true
                                maskSource: avMask
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: window.s(2)
                                border.color: window.mauve
                            }
                            Process {
                                id: avatarOpener
                                command: ["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh toggle avatar"]
                            }
                            Rectangle {
                                id: pencilBtn
                                width: window.s(24)
                                height: width
                                radius: width / 2
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: -window.s(4)
                                anchors.bottomMargin: -window.s(2)
                                color: pencilMa.containsMouse ? window.pink : window.mauve
                                border.width: window.s(2)
                                border.color: window.crust
                                scale: pencilMa.containsMouse ? 1.15 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u270E"
                                    color: window.crust
                                    font.pixelSize: window.s(13)
                                    font.bold: true
                                }
                                MouseArea {
                                    id: pencilMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { avatarOpener.running = false; avatarOpener.running = true; }
                                }
                            }
                        }

                        StyledField {
                            id: nameField
                            Layout.fillWidth: true
                            placeholderText: "Username"
                            horizontalAlignment: TextInput.AlignHCenter
                            onAccepted: profileCard.saveName()
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: window.s(30)
                            radius: window.s(10)
                            color: setMa.containsMouse ? Qt.alpha(window.mauve, 0.9) : window.mauve
                            Text {
                                anchors.centerIn: parent
                                text: "Set username"
                                color: window.crust
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(11)
                                font.bold: true
                            }
                            MouseArea {
                                id: setMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: profileCard.saveName()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: window.statusText
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                            color: window.statusError ? window.red : window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(9)
                        }
                    }
                }
            }
        }

        // ===== main =====
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: window.s(14)

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: window.s(74)
                radius: window.s(18)
                color: window.card
                border.width: 1
                border.color: window.cardBorder

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: window.s(20)
                    anchors.rightMargin: window.s(18)
                    spacing: window.s(12)
                    ColumnLayout {
                        spacing: window.s(2)
                        Text {
                            text: window.pageTitle
                            color: window.text
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(21)
                            font.bold: true
                        }
                        Text {
                            text: window.pageHint
                            color: window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(11)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Chip {
                        visible: window.page === "mine"
                        label: "+ New shortcut"
                        px: window.s(12)
                        onColor: window.mauve
                        offColor: window.mauve
                        fgOff: window.crust
                        onClicked: window.newShortcut()
                    }
                    StyledField {
                        visible: window.page === "all"
                        Layout.preferredWidth: window.s(260)
                        px: window.s(12)
                        bg: Qt.alpha(window.surface0, 0.8)
                        fg: window.text
                        hintColor: window.subtext0
                        accent: window.mauve
                        placeholderText: "Search binds..."
                        text: window.filterText
                        onTextEdited: window.filterText = text
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ======================= DEFAULT APPS =======================
                RowLayout {
                    anchors.fill: parent
                    visible: window.page === "apps"
                    spacing: window.s(14)

                    Rectangle {
                        Layout.preferredWidth: window.s(236)
                        Layout.fillHeight: true
                        radius: window.s(18)
                        color: window.card
                        border.width: 1
                        border.color: window.cardBorder

                        ListView {
                            id: catList
                            anchors.fill: parent
                            anchors.margins: window.s(8)
                            clip: true
                            spacing: window.s(3)
                            boundsBehavior: Flickable.StopAtBounds
                            model: window.cats
                            ScrollBar.vertical: ScrollBar { }

                            delegate: Rectangle {
                                id: catRow
                                required property var modelData
                                required property int index

                                width: catList.width - window.s(8)
                                height: window.s(46)
                                radius: window.s(13)
                                color: catMa.containsMouse ? window.surface1 : (window.sel === catRow.index ? Qt.alpha(window.mauve, 0.16) : "transparent")
                                border.width: window.sel === catRow.index ? 1 : 0
                                border.color: window.mauve
                                Behavior on color { ColorAnimation { duration: 120 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: window.s(14)
                                    anchors.rightMargin: window.s(14)
                                    spacing: 0
                                    Item { Layout.fillHeight: true }
                                    Text {
                                        text: catRow.modelData.label
                                        color: window.text
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(13)
                                        font.bold: true
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: catRow.modelData.currentName
                                        color: window.subtext0
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(10)
                                        elide: Text.ElideRight
                                    }
                                    Item { Layout.fillHeight: true }
                                }
                                MouseArea {
                                    id: catMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: window.sel = catRow.index
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: window.s(18)
                        color: window.card
                        border.width: 1
                        border.color: window.cardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: window.s(12)
                            spacing: window.s(8)

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: window.s(4)
                                Text {
                                    text: window.cat ? window.cat.label : ""
                                    color: window.text
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(16)
                                    font.bold: true
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: window.cat ? ("  " + window.cat.hint) : ""
                                    color: window.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(11)
                                    elide: Text.ElideRight
                                }
                                Chip {
                                    visible: window.cat !== null && window.cat.current !== ""
                                    label: "Reset"
                                    px: window.s(11)
                                    offColor: Qt.alpha(window.surface0, 0.9)
                                    fgOff: window.subtext0
                                    onClicked: window.resetCat()
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ListView {
                                    id: appList
                                    anchors.fill: parent
                                    clip: true
                                    spacing: window.s(4)
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: window.cat ? window.cat.apps : []
                                    ScrollBar.vertical: ScrollBar { }

                                    delegate: Rectangle {
                                        id: appRow
                                        required property var modelData
                                        readonly property bool isCurrent: window.cat !== null && appRow.modelData.id === window.cat.current

                                        width: appList.width - window.s(8)
                                        height: window.s(56)
                                        radius: window.s(13)
                                        color: rowMa.containsMouse ? window.surface1 : (appRow.isCurrent ? Qt.alpha(window.mauve, 0.14) : Qt.alpha(window.surface0, 0.35))
                                        border.width: appRow.isCurrent ? 1 : 0
                                        border.color: window.mauve
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: window.s(12)
                                            anchors.rightMargin: window.s(14)
                                            spacing: window.s(12)

                                            Item {
                                                Layout.preferredWidth: window.s(36)
                                                Layout.preferredHeight: window.s(36)
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: window.s(10)
                                                    color: Qt.alpha(window.surface1, 0.8)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: appRow.modelData.name.charAt(0).toUpperCase()
                                                        color: window.mauve
                                                        font.family: "JetBrains Mono"
                                                        font.pixelSize: window.s(15)
                                                        font.bold: true
                                                    }
                                                }
                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: window.s(3)
                                                    source: window.iconSource(appRow.modelData.icon)
                                                    sourceSize: Qt.size(64, 64)
                                                    fillMode: Image.PreserveAspectFit
                                                    asynchronous: true
                                                    visible: status === Image.Ready
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: appRow.modelData.name
                                                    color: window.text
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: window.s(13)
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: appRow.modelData.id
                                                    color: window.subtext0
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: window.s(10)
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                visible: appRow.isCurrent
                                                Layout.preferredWidth: window.s(78)
                                                Layout.preferredHeight: window.s(22)
                                                radius: height / 2
                                                color: Qt.alpha(window.mauve, 0.22)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "DEFAULT"
                                                    color: window.mauve
                                                    font.family: "JetBrains Mono"
                                                    font.pixelSize: window.s(10)
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: rowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.setDefault(appRow.modelData)
                                        }
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: window.loaded && appList.count === 0
                                    text: "No installed apps handle this type"
                                    color: window.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(12)
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !window.loaded
                                    text: "Loading..."
                                    color: window.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(12)
                                }
                            }
                        }
                    }
                }

                // ======================= SHORTCUTS (list + editor) =======================
                RowLayout {
                    anchors.fill: parent
                    visible: window.page === "mine"
                    spacing: window.s(14)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: window.s(18)
                        color: window.card
                        border.width: 1
                        border.color: window.cardBorder

                        ListView {
                            id: mineList
                            anchors.fill: parent
                            anchors.margins: window.s(8)
                            clip: true
                            spacing: window.s(4)
                            boundsBehavior: Flickable.StopAtBounds
                            model: window.rows
                            ScrollBar.vertical: ScrollBar { }

                            delegate: Rectangle {
                                id: kRow
                                required property var modelData
                                readonly property bool picked: !!window.edit && window.edit.origCombo === kRow.modelData.combo

                                width: mineList.width - window.s(8)
                                height: window.s(58)
                                radius: window.s(13)
                                color: kMa.containsMouse ? window.surface1 : (kRow.picked ? Qt.alpha(window.mauve, 0.14) : Qt.alpha(window.surface0, 0.35))
                                border.width: kRow.picked ? 1 : 0
                                border.color: window.mauve
                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: window.s(12)
                                    anchors.rightMargin: window.s(12)
                                    spacing: window.s(12)

                                    Row {
                                        Layout.preferredWidth: window.s(150)
                                        spacing: window.s(4)
                                        Repeater {
                                            model: kRow.modelData.combo.split(" + ")
                                            delegate: KeyCap {
                                                required property string modelData
                                                label: window.capLabel(modelData)
                                                px: window.s(10)
                                                fill: Qt.alpha(window.surface2, 0.8)
                                                fg: window.text
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        Text {
                                            Layout.fillWidth: true
                                            text: kRow.modelData.label
                                            color: window.text
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(12)
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: kRow.modelData.targetText
                                            color: window.subtext0
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(10)
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Rectangle {
                                        visible: kRow.modelData.kind === "builtin"
                                        Layout.preferredWidth: window.s(66)
                                        Layout.preferredHeight: window.s(20)
                                        radius: height / 2
                                        color: Qt.alpha(window.subtext0, 0.2)
                                        Text {
                                            anchors.centerIn: parent
                                            text: "BUILT-IN"
                                            color: window.subtext0
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: window.s(9)
                                            font.bold: true
                                        }
                                    }
                                }
                                MouseArea {
                                    id: kMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: window.openEditor(kRow.modelData)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: window.kbLoaded && window.rows.length === 0
                            text: "No shortcuts yet. Press + New shortcut."
                            color: window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(12)
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !window.kbLoaded
                            text: "Loading..."
                            color: window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(12)
                        }
                    }

                    // ---- editor ----
                    Rectangle {
                        Layout.fillHeight: true
                        Layout.preferredWidth: window.s(404)
                        Layout.minimumWidth: window.s(390)
                        radius: window.s(18)
                        color: window.card
                        border.width: 1
                        border.color: window.cardBorder

                        Text {
                            anchors.centerIn: parent
                            width: parent.width - window.s(48)
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            visible: !window.edit
                            text: "Select a shortcut to edit it, or press + New shortcut.\nBuilt-in binds keep their exact command until you change it."
                            color: window.subtext0
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(12)
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: window.s(16)
                            spacing: window.s(8)
                            visible: !!window.edit

                            Text {
                                text: !window.edit ? "" : (window.edit.kind === "new" ? "New shortcut"
                                      : (window.edit.kind === "builtin" ? "Take over built-in bind" : "Edit shortcut"))
                                color: window.text
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(14)
                                font.bold: true
                            }

                            Rectangle {
                                visible: !!window.edit && window.edit.kind === "builtin"
                                Layout.fillWidth: true
                                Layout.preferredHeight: origCol.implicitHeight + window.s(16)
                                radius: window.s(10)
                                color: Qt.alpha(window.surface0, 0.55)
                                border.width: 1
                                border.color: window.cardBorder
                                ColumnLayout {
                                    id: origCol
                                    anchors.fill: parent
                                    anchors.margins: window.s(8)
                                    spacing: window.s(2)
                                    Text {
                                        text: !window.edit ? "" : ("Currently runs  (" + window.edit.origin + ")")
                                        color: window.subtext0
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(9)
                                        font.bold: true
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: window.edit ? window.edit.origCmd : ""
                                        wrapMode: Text.WrapAnywhere
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        color: window.text
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(10)
                                    }
                                }
                            }

                            StyledField {
                                Layout.fillWidth: true
                                px: window.s(12)
                                bg: Qt.alpha(window.surface0, 0.9)
                                fg: window.text
                                hintColor: window.subtext0
                                accent: window.mauve
                                placeholderText: "Name (e.g. File manager)"
                                text: window.edit ? window.edit.label : ""
                                onTextEdited: window.setEdit({ label: text })
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: window.s(6)
                                Repeater {
                                    model: window.modOrder
                                    delegate: Chip {
                                        required property string modelData
                                        label: window.capLabel(modelData)
                                        px: window.s(11)
                                        on: !!window.edit && window.edit.mods.indexOf(modelData) !== -1
                                        onColor: window.mauve
                                        offColor: Qt.alpha(window.surface0, 0.9)
                                        fgOn: window.crust
                                        fgOff: window.text
                                        onClicked: window.toggleMod(modelData)
                                    }
                                }
                                StyledField {
                                    Layout.fillWidth: true
                                    px: window.s(12)
                                    bg: Qt.alpha(window.surface0, 0.9)
                                    fg: window.text
                                    hintColor: window.subtext0
                                    accent: window.mauve
                                    placeholderText: "Key (E, Return, F5...)"
                                    text: window.edit ? window.edit.key : ""
                                    onTextEdited: { window.setEdit({ key: text.trim() }); window.conflict = null; window.editError = ""; }
                                }
                            }

                            Text {
                                text: window.comboPreview !== "" ? ("Bind: " + window.comboPreview) : "Choose modifiers and a key"
                                color: window.subtext0
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(11)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: window.s(6)
                                Text {
                                    text: "Launches"
                                    color: window.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(11)
                                }
                                Chip {
                                    label: "Default app"
                                    px: window.s(10)
                                    on: !!window.edit && window.edit.type === "category"
                                    onColor: window.surface2
                                    offColor: Qt.alpha(window.surface0, 0.9)
                                    fgOn: window.text
                                    fgOff: window.subtext0
                                    onClicked: window.setEdit({ type: "category", target: "files" })
                                }
                                Chip {
                                    label: "Specific app"
                                    px: window.s(10)
                                    on: !!window.edit && window.edit.type === "app"
                                    onColor: window.surface2
                                    offColor: Qt.alpha(window.surface0, 0.9)
                                    fgOn: window.text
                                    fgOff: window.subtext0
                                    onClicked: window.setEdit({ type: "app", target: "" })
                                }
                                Chip {
                                    label: "Command"
                                    px: window.s(10)
                                    on: !!window.edit && window.edit.type === "custom"
                                    onColor: window.surface2
                                    offColor: Qt.alpha(window.surface0, 0.9)
                                    fgOn: window.text
                                    fgOff: window.subtext0
                                    onClicked: window.setEdit({ type: "custom", target: "" })
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: window.s(80)

                                ListView {
                                    id: catPick
                                    anchors.fill: parent
                                    visible: !!window.edit && window.edit.type === "category"
                                    clip: true
                                    spacing: window.s(2)
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: window.kb.cats
                                    ScrollBar.vertical: ScrollBar { }
                                    delegate: Rectangle {
                                        id: cpRow
                                        required property var modelData
                                        readonly property bool chosen: !!window.edit && window.edit.target === cpRow.modelData.id
                                        width: catPick.width - window.s(8)
                                        height: window.s(32)
                                        radius: window.s(8)
                                        color: cpMa.containsMouse ? window.surface1 : (cpRow.chosen ? Qt.alpha(window.mauve, 0.18) : "transparent")
                                        border.width: cpRow.chosen ? 1 : 0
                                        border.color: window.mauve
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: window.s(10)
                                            anchors.rightMargin: window.s(10)
                                            spacing: window.s(8)
                                            Text {
                                                text: "Default " + cpRow.modelData.label.toLowerCase()
                                                color: window.text
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: window.s(11)
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignRight
                                                text: "→ " + cpRow.modelData.currentName
                                                color: window.subtext0
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: window.s(10)
                                                elide: Text.ElideRight
                                            }
                                        }
                                        MouseArea {
                                            id: cpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.setEdit({ target: cpRow.modelData.id })
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    visible: !!window.edit && window.edit.type === "app"
                                    spacing: window.s(6)
                                    StyledField {
                                        Layout.fillWidth: true
                                        px: window.s(11)
                                        bg: Qt.alpha(window.surface0, 0.9)
                                        fg: window.text
                                        hintColor: window.subtext0
                                        accent: window.mauve
                                        placeholderText: "Search installed apps..."
                                        text: window.appFilter
                                        onTextEdited: window.appFilter = text
                                    }
                                    ListView {
                                        id: appPick
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: window.s(2)
                                        boundsBehavior: Flickable.StopAtBounds
                                        model: window.appRows
                                        ScrollBar.vertical: ScrollBar { }
                                        delegate: Rectangle {
                                            id: apRow
                                            required property var modelData
                                            readonly property bool chosen: !!window.edit && window.edit.target === apRow.modelData.id
                                            width: appPick.width - window.s(8)
                                            height: window.s(30)
                                            radius: window.s(8)
                                            color: apMa.containsMouse ? window.surface1 : (apRow.chosen ? Qt.alpha(window.mauve, 0.18) : "transparent")
                                            border.width: apRow.chosen ? 1 : 0
                                            border.color: window.mauve
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.left: parent.left
                                                anchors.leftMargin: window.s(10)
                                                anchors.right: parent.right
                                                anchors.rightMargin: window.s(10)
                                                text: apRow.modelData.name
                                                color: window.text
                                                font.family: "JetBrains Mono"
                                                font.pixelSize: window.s(11)
                                                elide: Text.ElideRight
                                            }
                                            MouseArea {
                                                id: apMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: window.setEdit({ target: apRow.modelData.id })
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    visible: !!window.edit && window.edit.type === "custom"
                                    spacing: window.s(6)
                                    StyledField {
                                        Layout.fillWidth: true
                                        px: window.s(11)
                                        bg: Qt.alpha(window.surface0, 0.9)
                                        fg: window.text
                                        hintColor: window.subtext0
                                        accent: window.mauve
                                        placeholderText: "Shell command, e.g. pavucontrol"
                                        text: window.edit ? window.edit.target : ""
                                        onTextEdited: { window.setEdit({ target: text }); window.editError = ""; window.conflict = null; }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Runs through your shell when the shortcut is pressed. Use Try to test it first."
                                        color: window.subtext0
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: window.s(10)
                                    }
                                    Item { Layout.fillHeight: true }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: window.editError !== ""
                                text: window.editError
                                wrapMode: Text.WordWrap
                                color: window.red
                                font.family: "JetBrains Mono"
                                font.pixelSize: window.s(10)
                            }
                            ActionButton {
                                visible: !!window.conflict && window.conflict.canTakeOver
                                label: "Replace the existing bind"
                                px: window.s(11)
                                fill: Qt.alpha(window.red, 0.28)
                                fillHover: Qt.alpha(window.red, 0.7)
                                active: !window.busy
                                onClicked: window.saveEdit(true)
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: window.s(8)
                                ActionButton {
                                    label: window.busy ? "Working..." : (!!window.edit && window.edit.kind === "builtin" && window.comboPreview === window.edit.origCombo ? "Take over" : "Save")
                                    px: window.s(12)
                                    fill: window.mauve
                                    fillHover: Qt.lighter(window.mauve, 1.12)
                                    fg: window.crust
                                    active: !window.busy
                                    onClicked: window.saveEdit(false)
                                }
                                ActionButton {
                                    label: "Try"
                                    px: window.s(12)
                                    fill: Qt.alpha(window.surface1, 0.9)
                                    active: !window.busy
                                    onClicked: window.tryEdit()
                                }
                                ActionButton {
                                    visible: !!window.edit && window.edit.id !== ""
                                    label: "Delete"
                                    px: window.s(12)
                                    fill: Qt.alpha(window.surface0, 0.9)
                                    fillHover: Qt.alpha(window.red, 0.85)
                                    active: !window.busy
                                    onClicked: window.deleteEdit()
                                }
                                ActionButton {
                                    label: "Cancel"
                                    px: window.s(12)
                                    fill: Qt.alpha(window.surface0, 0.9)
                                    onClicked: { window.edit = null; window.editError = ""; window.conflict = null; }
                                }
                            }
                        }
                    }
                }

                // ======================= ALL BINDS =======================
                Rectangle {
                    anchors.fill: parent
                    visible: window.page === "all"
                    radius: window.s(18)
                    color: window.card
                    border.width: 1
                    border.color: window.cardBorder

                    ListView {
                        id: allList
                        anchors.fill: parent
                        anchors.margins: window.s(8)
                        clip: true
                        spacing: window.s(2)
                        boundsBehavior: Flickable.StopAtBounds
                        model: window.liveRows
                        ScrollBar.vertical: ScrollBar { }

                        delegate: Rectangle {
                            id: aRow
                            required property var modelData
                            width: allList.width - window.s(8)
                            height: window.s(38)
                            radius: window.s(9)
                            color: aMa.containsMouse ? Qt.alpha(window.surface1, 0.6) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: window.s(10)
                                anchors.rightMargin: window.s(10)
                                spacing: window.s(12)
                                Row {
                                    Layout.preferredWidth: window.s(190)
                                    spacing: window.s(4)
                                    Repeater {
                                        model: aRow.modelData.combo.split(" + ")
                                        delegate: KeyCap {
                                            required property string modelData
                                            label: window.capLabel(modelData)
                                            px: window.s(9)
                                            fill: Qt.alpha(window.surface2, 0.7)
                                            fg: window.text
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: aRow.modelData.desc
                                    color: window.text
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(10)
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.preferredWidth: window.s(150)
                                    horizontalAlignment: Text.AlignRight
                                    text: aRow.modelData.src
                                    color: window.subtext0
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(9)
                                    elide: Text.ElideLeft
                                }
                            }
                            MouseArea {
                                id: aMa
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - window.s(48)
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        visible: window.kbLoaded && window.liveRows.length === 0
                        text: window.kbLiveOk ? "No binds match." : "Couldn't read live binds from Hyprland (hyprctl binds)."
                        color: window.subtext0
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(12)
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !window.kbLoaded
                        text: "Loading..."
                        color: window.subtext0
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(12)
                    }
                }
            }
        }
    }
}
