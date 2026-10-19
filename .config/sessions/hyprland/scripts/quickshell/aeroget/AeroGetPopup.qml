import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: root
    focus: true

    property var notifModel: null
    property real layoutWidth: 0
    property real layoutHeight: 0

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

    readonly property string fMono: "JetBrains Mono"
    readonly property string fDisp: "Outfit"

    // ====================== reusable pieces ======================
    component PlaneGlyph: Canvas {
        id: pg
        property color c1: "white"
        property color c2: "gray"
        onC1Changed: requestPaint()
        onC2Changed: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d");
            ctx.reset();
            let w = width, h = height;
            ctx.fillStyle = String(pg.c1);
            ctx.beginPath(); ctx.moveTo(w, h * 0.5); ctx.lineTo(0, h * 0.05); ctx.lineTo(w * 0.32, h * 0.5); ctx.closePath(); ctx.fill();
            ctx.fillStyle = String(pg.c2);
            ctx.beginPath(); ctx.moveTo(w, h * 0.5); ctx.lineTo(w * 0.32, h * 0.5); ctx.lineTo(w * 0.12, h * 0.95); ctx.closePath(); ctx.fill();
        }
    }

    component FlapChar: Item {
        id: fc
        property string ch: " "
        property string shown: " "
        property color fg: "white"
        property color bg: "#111111"
        property real cw: 12
        property real chh: 20
        property int fontPx: 13
        property int scrambles: 0
        property real flipY: 1.0
        width: cw
        height: chh
        onChChanged: { fc.scrambles = 2 + Math.floor(Math.random() * 3); scr.restart(); }
        function randomChar() {
            const pool = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
            return pool.charAt(Math.floor(Math.random() * pool.length));
        }
        Timer {
            id: scr
            interval: 48; repeat: true
            onTriggered: {
                if (fc.scrambles > 0) { fc.shown = fc.randomChar(); fc.scrambles--; }
                else { fc.shown = fc.ch; scr.stop(); }
                flip.restart();
            }
        }
        SequentialAnimation {
            id: flip
            NumberAnimation { target: fc; property: "flipY"; to: 0.12; duration: 26 }
            NumberAnimation { target: fc; property: "flipY"; to: 1.0; duration: 44; easing.type: Easing.OutQuad }
        }
        Rectangle {
            anchors.fill: parent
            radius: 2
            color: fc.bg
            border.color: Qt.rgba(0, 0, 0, 0.5); border.width: 1
            transform: Scale { origin.x: fc.cw / 2; origin.y: fc.chh / 2; yScale: fc.flipY }
            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: parent.height / 2; radius: 2; color: Qt.rgba(1, 1, 1, 0.05) }
            Text { anchors.centerIn: parent; text: fc.shown; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: fc.fontPx; color: fc.fg }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: Qt.rgba(0, 0, 0, 0.65) }
        }
    }

    component FlapText: Row {
        id: ft
        property string text: ""
        property int len: 8
        property color fg: "white"
        property color bg: "#111111"
        property real cw: 12
        property real chh: 20
        property int fontPx: 13
        property bool rightAlign: false
        spacing: 2
        Repeater {
            model: ft.len
            delegate: FlapChar {
                required property int index
                ch: {
                    let t = ft.text.toUpperCase();
                    t = ft.rightAlign ? t.padStart(ft.len, " ") : t.padEnd(ft.len, " ");
                    return t.charAt(index) || " ";
                }
                fg: ft.fg
                bg: ft.bg
                cw: ft.cw
                chh: ft.chh
                fontPx: ft.fontPx
            }
        }
    }

    component Btn: Rectangle {
        id: bt
        property var hub: null
        property string label: ""
        property color accent: "white"
        signal clicked()
        implicitWidth: btText.implicitWidth + hub.s(26)
        implicitHeight: hub.s(30)
        radius: hub.s(3)
        color: btMa.containsMouse ? Qt.alpha(bt.accent, 0.2) : "transparent"
        border.color: btMa.containsMouse ? bt.accent : hub.surface2; border.width: 1
        scale: btMa.pressed ? 0.96 : 1.0
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { id: btText; anchors.centerIn: parent; text: bt.label; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: bt.hub.s(10); font.letterSpacing: 1.5; color: bt.accent }
        MouseArea { id: btMa; anchors.fill: parent; hoverEnabled: true; onClicked: bt.clicked() }
    }

    component TicketShape: Canvas {
        id: tk
        property color fillA: "#222222"
        property color fillB: "#333333"
        property color stubFill: "#000000"
        property color edge: "#555555"
        property color accent: "#8888ff"
        property real nx: width * 0.64
        property real nr: 11
        property real rad: 8
        property bool ghost: false
        onFillAChanged: requestPaint()
        onFillBChanged: requestPaint()
        onStubFillChanged: requestPaint()
        onEdgeChanged: requestPaint()
        onAccentChanged: requestPaint()
        onNxChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        function path(ctx) {
            let w = width, h = height, r = rad, x0 = tk.nx, q = tk.nr;
            ctx.beginPath();
            ctx.moveTo(r, 0);
            ctx.lineTo(x0 - q, 0);
            ctx.arc(x0, 0, q, Math.PI, 0, true);
            ctx.lineTo(w - r, 0);
            ctx.arcTo(w, 0, w, r, r);
            ctx.lineTo(w, h - r);
            ctx.arcTo(w, h, w - r, h, r);
            ctx.lineTo(x0 + q, h);
            ctx.arc(x0, h, q, 0, Math.PI, true);
            ctx.lineTo(r, h);
            ctx.arcTo(0, h, 0, h - r, r);
            ctx.lineTo(0, r);
            ctx.arcTo(0, 0, r, 0, r);
            ctx.closePath();
        }
        onPaint: {
            let ctx = getContext("2d");
            ctx.reset();
            let w = width, h = height, x0 = tk.nx, q = tk.nr;
            if (w < 8 || h < 8) return;
            if (!tk.ghost) {
                path(ctx);
                let g = ctx.createLinearGradient(0, 0, w, h);
                g.addColorStop(0, String(tk.fillA));
                g.addColorStop(1, String(tk.fillB));
                ctx.fillStyle = g;
                ctx.fill();
                ctx.save();
                path(ctx);
                ctx.clip();
                ctx.globalAlpha = 0.07;
                ctx.strokeStyle = String(tk.accent);
                ctx.lineWidth = 1;
                for (let k = 0; k < 7; k++) {
                    ctx.beginPath();
                    for (let x = 0; x <= x0; x += 6) {
                        let y = h * 0.5 + Math.sin(x / 38 + k * 0.7) * (30 + k * 9);
                        if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                    }
                    ctx.stroke();
                }
                ctx.globalAlpha = 1;
                ctx.fillStyle = String(tk.stubFill);
                ctx.fillRect(x0, 0, w - x0, h);
                ctx.fillStyle = String(tk.accent);
                ctx.fillRect(0, 0, x0, 4);
                ctx.restore();
            }
            path(ctx);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = String(tk.edge);
            if (tk.ghost && ctx.setLineDash) ctx.setLineDash([7, 5]);
            ctx.stroke();
            if (ctx.setLineDash) ctx.setLineDash([]);
            ctx.fillStyle = String(tk.edge);
            for (let y2 = q + 8; y2 < h - q - 8; y2 += 10) ctx.fillRect(x0 - 0.75, y2, 1.5, 5);
        }
    }

    component BarCode: Canvas {
        id: bc
        property int seed: 1
        property color col: "white"
        onSeedChanged: requestPaint()
        onColChanged: requestPaint()
        onWidthChanged: requestPaint()
        onPaint: {
            let ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = String(bc.col);
            let st = (bc.seed >>> 0) || 1, x = 0, on = true;
            while (x < width) {
                st = (st * 1664525 + 1013904223) >>> 0;
                let bw = 1 + ((st >>> 28) % 4);
                if (on) ctx.fillRect(x, 0, bw, height);
                x += bw + (on ? 1 : 0);
                on = !on;
            }
        }
    }

    // ====================== helpers ======================
    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    function fmtBytes(b) {
        if (!b || b <= 0) return "\u2014";
        let u = ["B", "KB", "MB", "GB", "TB"], i = 0, v = b;
        while (v >= 1024 && i < 4) { v /= 1024; i++; }
        return (v >= 100 || i === 0 ? v.toFixed(0) : v.toFixed(1)) + " " + u[i];
    }
    function fmtCompact(b) { return fmtBytes(b).replace(" ", ""); }
    function fmtEta(sec) {
        if (sec === undefined || sec === null || sec < 0 || !isFinite(sec)) return "--:--";
        let m = Math.floor(sec / 60), r = Math.floor(sec % 60);
        if (m > 99) return "99:59";
        return pad2(m) + ":" + pad2(r);
    }
    function isUrl(t) { return /^https?:\/\/[^\s]+$/i.test(t); }
    function hostOf(u) {
        let m = /^https?:\/\/(?:www\.|m\.)?([^\/:?#]+)/i.exec(u || "");
        return m ? m[1].toLowerCase() : "";
    }
    function hashStr(str) {
        let h = 2166136261;
        for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
        return h >>> 0;
    }
    function presetShort(id) {
        if (id === "best") return "BEST";
        if (id === "audio") return "MP3";
        let m = /^h(\d+)$/.exec(id || "");
        return m ? m[1] + "P" : (id || "").toUpperCase();
    }
    function shortDir(p) {
        if (!p) return "~";
        return p.indexOf(home) === 0 ? "~" + p.slice(home.length) : p;
    }
    function statusText(j) {
        if (j.status === "done") return "LANDED";
        if (j.status === "error") return "DELAYED";
        if (j.status === "cancelled") return "CANCELLED";
        if (j.status === "queued") return "BOARDING";
        if (j.phase === "merging" || j.phase === "converting") return "LANDING";
        if (j.status === "starting") return "BOARDING";
        if (j.status === "downloading" && !(j.percent > 0)) return "TAXIING";
        return "IN FLIGHT";
    }
    function statColor(st) {
        if (st === "BOARDING" || st === "TAXIING") return peach;
        if (st === "IN FLIGHT") return blue;
        if (st === "LANDING") return text;
        if (st === "LANDED") return green;
        if (st === "DELAYED") return red;
        return subtext1;
    }
    function rowFrom(j) {
        return {
            jid: j.id, title: j.title || j.url || "", uploader: j.uploader || "", host: hostOf(j.url || ""),
            stat: statusText(j), raw: j.status || "", pct: j.percent || 0, speed: j.speed || 0,
            eta: (j.eta === null || j.eta === undefined) ? -1 : j.eta,
            file: j.file || "", size: j.size || 0, err: j.error || "", thumb: j.thumb || "",
            presetLabel: presetShort(j.preset), phase: j.phase || ""
        };
    }
    function toast(t) { toastText = t; toastTimer.restart(); }
    function run(args) {
        Quickshell.execDetached(["python3", root.agent].concat(args));
        pollSoon.restart();
    }
    function requestClose() { closeSequence.start(); }

    // ---------- destination picker ----------
    property bool pickerOpen: false
    property string pickerPath: ""
    property bool pickerHidden: false
    property bool pickerNew: false
    property int pickerShown: 0
    ListModel { id: pickerModel }
    onPickerHiddenChanged: recount()
    onPickerNewChanged: { if (pickerNew) Qt.callLater(function () { pkNewInput.forceActiveFocus(); }); else urlInput.forceActiveFocus(); }

    function recount() {
        let n = 0;
        for (let i = 0; i < pickerModel.count; i++) { let e = pickerModel.get(i); if (!e.hid || pickerHidden) n++; }
        pickerShown = n;
    }
    function listDir(p) {
        listProc.command = ["bash", "-c", 'cd -- "$1" 2>/dev/null || exit 0; pwd -P; for d in */ .[!.]*/; do [ -d "$d" ] && printf "%s\\n" "${d%/}"; done', "_", p];
        listProc.running = true;
    }
    function openPicker() {
        pickerNew = false;
        pickerOpen = true;
        listDir(destDir !== "" ? destDir : home);
    }
    function enterDir(name) { listDir(pickerPath === "/" ? "/" + name : pickerPath + "/" + name); }
    function goUp() {
        let p = pickerPath;
        if (p === "" || p === "/") return;
        let i = p.lastIndexOf("/");
        listDir(i <= 0 ? "/" : p.substring(0, i));
    }
    function selectDir() {
        if (pickerPath === "") return;
        destDir = pickerPath;
        dirLockUntil = Date.now() + 1800;
        Quickshell.execDetached(["python3", agent, "cfg", "set", "dir", pickerPath]);
        pickerOpen = false;
        toast("DESTINATION SET");
        urlInput.forceActiveFocus();
    }
    function makeFolder(nm) {
        nm = nm.trim();
        if (nm === "" || nm.indexOf("/") >= 0 || nm === "." || nm === "..") { toast("INVALID FOLDER NAME"); return; }
        let full = (pickerPath === "/" ? "" : pickerPath) + "/" + nm;
        mkProc.made = full;
        mkProc.command = ["mkdir", "-p", "--", full];
        mkProc.running = true;
    }
    Process {
        id: listProc
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n");
                let p = (lines[0] || "").trim();
                if (p === "") { root.toast("CAN'T OPEN THAT FOLDER"); return; }
                root.pickerPath = p;
                pickerModel.clear();
                for (let i = 1; i < lines.length; i++) {
                    let n = lines[i];
                    if (n !== "") pickerModel.append({ name: n, hid: n.charAt(0) === "." });
                }
                root.recount();
            }
        }
    }
    Process {
        id: mkProc
        property string made: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) { pkNewInput.text = ""; root.pickerNew = false; root.listDir(made); }
            else root.toast("COULDN'T CREATE FOLDER");
        }
    }


    // ====================== state ======================
    readonly property string home: Quickshell.env("HOME")
    readonly property string agent: home + "/.config/hypr/scripts/aeroget.py"
    readonly property string mgr: home + "/.config/hypr/scripts/qs_manager.sh"

    property string phase: "idle"          // idle | loading | ready | denied
    property string pendingUrl: ""
    property string queuedUrl: ""
    property string errorText: ""
    property var info: ({})
    property int sel: 0
    property bool launching: false
    property bool clipForce: false
    property string toastText: ""
    property string destDir: ""
    property real dirLockUntil: 0
    property var dirs: []
    property real totalSpeed: 0
    property int activeCount: 0
    property int doneCount: 0
    property int queuedCount: 0
    property real avgPct: 0
    property real tm: 0
    property string clockStr: ""
    property int loadIdx: 0
    property real introBase: 0.0
    property real introContent: 0.0
    property real introBoard: 0.0
    property real glow: 0.0

    readonly property var curPreset: (info && info.presets && info.presets.length > sel) ? info.presets[sel] : null
    readonly property string classText: curPreset ? (curPreset.label + (curPreset.id === "best" ? " " + curPreset.detail : "")).toUpperCase() : ""
    readonly property string sizeText: curPreset ? fmtBytes(curPreset.est).toUpperCase() : ""
    readonly property real dialMaxMB: {
        let v = totalSpeed / 1048576 * 1.25;
        let st = [2, 5, 10, 25, 50, 100, 250, 500];
        for (let i = 0; i < st.length; i++) if (v <= st[i]) return st[i];
        return 1000;
    }
    readonly property var loadMsgs: ["SCANNING PASSPORT", "WEIGHING LUGGAGE", "CLEARING CUSTOMS", "CHECKING THE FORECAST", "ASSIGNING A SEAT"]

    Keys.onEscapePressed: (event) => { if (root.pickerOpen) { root.pickerOpen = false; urlInput.forceActiveFocus(); } else root.requestClose(); event.accepted = true; }
    Keys.onUpPressed: (event) => { if (root.phase === "ready" && root.sel > 0) root.sel--; event.accepted = true; }
    Keys.onDownPressed: (event) => { if (root.phase === "ready" && root.info.presets && root.sel < root.info.presets.length - 1) root.sel++; event.accepted = true; }
    onActiveFocusChanged: { if (activeFocus) urlInput.forceActiveFocus(); }

    // ====================== logic ======================
    ListModel { id: jobModel }

    function syncJobs(jobs) {
        let list = jobs.slice().reverse();
        let mapped = list.map(rowFrom);
        let want = mapped.map(function (m) { return m.jid; });
        for (let i = jobModel.count - 1; i >= 0; i--)
            if (want.indexOf(jobModel.get(i).jid) < 0) jobModel.remove(i);
        for (let i2 = 0; i2 < mapped.length; i2++) {
            if (i2 < jobModel.count && jobModel.get(i2).jid === mapped[i2].jid) { jobModel.set(i2, mapped[i2]); continue; }
            let found = -1;
            for (let k = i2 + 1; k < jobModel.count; k++) if (jobModel.get(k).jid === mapped[i2].jid) { found = k; break; }
            if (found >= 0) { jobModel.move(found, i2, 1); jobModel.set(i2, mapped[i2]); }
            else jobModel.insert(i2, mapped[i2]);
        }
        while (jobModel.count > mapped.length) jobModel.remove(jobModel.count - 1);
    }

    function applyList(d) {
        let jobs = d.jobs || [];
        let sp = 0, act = 0, sumP = 0, dn = 0, qd = 0;
        for (let i = 0; i < jobs.length; i++) {
            let j = jobs[i];
            if (j.status === "downloading" || j.status === "starting") { act++; sumP += (j.percent || 0); sp += (j.speed || 0); }
            else if (j.status === "queued") qd++;
            else if (j.status === "done") dn++;
        }
        root.totalSpeed = sp; root.activeCount = act; root.doneCount = dn; root.queuedCount = qd;
        root.avgPct = act > 0 ? sumP / act : 0;
        if (d.dir && Date.now() >= root.dirLockUntil) root.destDir = d.dir;
        syncJobs(jobs);
    }

    function analyze(u) {
        root.phase = "loading";
        root.errorText = "";
        if (infoProc.running) { root.queuedUrl = u; return; }
        startInfo(u);
    }
    function startInfo(u) {
        root.pendingUrl = u;
        infoProc.command = ["python3", root.agent, "info", u];
        infoProc.running = true;
    }
    function onInfo(d) {
        if (root.queuedUrl !== "") {
            let q = root.queuedUrl; root.queuedUrl = "";
            startInfo(q);
            return;
        }
        if (urlInput.text.trim() !== root.pendingUrl) return;
        if (d && d.ok) {
            root.info = d; root.sel = 0; root.phase = "ready";
        } else {
            root.errorText = (d && d.error) ? d.error : "Couldn't read that link";
            root.phase = "denied";
        }
    }
    function submit() {
        let t = urlInput.text.trim();
        if (t === "") { root.clipForce = true; clipProc.running = true; return; }
        if (!isUrl(t)) { toast("THAT'S NOT A LINK"); return; }
        if (root.phase === "ready" && root.info.url === t) { launch(); return; }
        debounce.stop();
        analyze(t);
    }
    function cycleDir() {
        if (!root.dirs || root.dirs.length === 0) return;
        let i = root.dirs.indexOf(root.destDir);
        let nxt = root.dirs[(i + 1) % root.dirs.length];
        root.destDir = nxt;
        root.dirLockUntil = Date.now() + 1800;
        Quickshell.execDetached(["python3", root.agent, "cfg", "set", "dir", nxt]);
    }
    function launch() {
        if (root.phase !== "ready" || root.launching) return;
        let p = root.curPreset;
        if (!p) return;
        root.launching = true;
        addProc.command = ["python3", root.agent, "add", root.info.url, p.id, "--dir", root.destDir,
                           "--title", root.info.title || "", "--thumb", root.info.thumb || "",
                           "--est", String(Math.round(p.est || 0)), "--uploader", root.info.uploader || "",
                           "--duration", root.info.duration_str || ""];
        addProc.running = true;
        let a = ticket.mapToItem(flightLayer, ticket.width * 0.55, ticket.height * 0.5);
        let b = board.mapToItem(flightLayer, board.width * 0.5, root.s(190));
        flightLayer.x0 = a.x; flightLayer.y0 = a.y; flightLayer.x1 = b.x; flightLayer.y1 = b.y;
        flightLayer.trail = [];
        flightLayer.visible = true;
        fadeTrail.stop();
        tearAnim.start();
        flyAnim.start();
    }
    function finishLaunch() {
        root.launching = false;
        urlInput.text = "";
        root.phase = "idle";
        urlInput.forceActiveFocus();
        tearReset.start();
    }

    // ====================== processes ======================
    Process {
        id: lister
        command: ["python3", root.agent, "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.applyList(JSON.parse(this.text)); } catch (e) {} }
        }
    }
    Process {
        id: infoProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try { d = JSON.parse(this.text); } catch (e) { d = { ok: false, error: "Couldn't read that link" }; }
                root.onInfo(d);
            }
        }
    }
    Process {
        id: addProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let d = JSON.parse(this.text);
                    if (!d.ok) root.toast((d.error || "COULDN'T QUEUE").toUpperCase());
                } catch (e) {}
                pollSoon.restart();
            }
        }
    }
    Process {
        id: clipProc
        command: ["wl-paste", "-n"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim();
                if (root.isUrl(t)) {
                    if (root.clipForce || urlInput.text === "") urlInput.text = t;
                } else if (root.clipForce) root.toast("CLIPBOARD HAS NO LINK");
                root.clipForce = false;
            }
        }
    }
    Process {
        id: dirsProc
        command: ["bash", "-c", "for d in DOWNLOAD VIDEOS MUSIC DESKTOP DOCUMENTS; do xdg-user-dir $d; done"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let seen = {}, out = [], lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let l = lines[i].trim();
                    if (l !== "" && l !== root.home && !seen[l]) { seen[l] = 1; out.push(l); }
                }
                root.dirs = out;
            }
        }
    }

    // ====================== timers ======================
    Timer { interval: 700; running: true; repeat: true; triggeredOnStart: true; onTriggered: { if (!lister.running) lister.running = true; } }
    Timer { id: pollSoon; interval: 260; onTriggered: { if (!lister.running) lister.running = true; } }
    Timer { id: debounce; interval: 450
        onTriggered: {
            let t = urlInput.text.trim();
            if (root.isUrl(t)) { if (!(root.phase === "ready" && root.info.url === t)) root.analyze(t); }
            else if (t !== "") root.phase = "idle";
        }
    }
    Timer { interval: 33; running: true; repeat: true; onTriggered: root.tm += 0.033 }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.clockStr = Qt.formatTime(new Date(), "HH:mm:ss") }
    Timer { interval: 1100; running: root.phase === "loading"; repeat: true; onTriggered: root.loadIdx = (root.loadIdx + 1) % root.loadMsgs.length }
    Timer { id: toastTimer; interval: 2600; onTriggered: root.toastText = "" }
    Timer { id: tearReset; interval: 620; onTriggered: readyPane.tear = 0 }
    Timer { id: fadeTrail; interval: 22; repeat: true
        onTriggered: {
            if (flightLayer.trail.length > 0) { flightLayer.trail.shift(); flightLayer.requestPaint(); }
            else { fadeTrail.stop(); flightLayer.visible = false; }
        }
    }

    // ====================== animations ======================
    Component.onCompleted: { startupSequence.start(); urlInput.forceActiveFocus(); }
    ParallelAnimation {
        id: startupSequence
        NumberAnimation { target: root; property: "introBase"; from: 0.0; to: 1.0; duration: 600; easing.type: Easing.OutExpo }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            NumberAnimation { target: root; property: "introContent"; from: 0.0; to: 1.0; duration: 800; easing.type: Easing.OutBack; easing.overshoot: 1.02 }
        }
        SequentialAnimation {
            PauseAnimation { duration: 320 }
            NumberAnimation { target: root; property: "introBoard"; from: 0.0; to: 1.0; duration: 900; easing.type: Easing.OutCubic }
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
        NumberAnimation { to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 1800; easing.type: Easing.InOutSine }
    }
    NumberAnimation { id: tearAnim; target: readyPane; property: "tear"; from: 0; to: 1; duration: 520; easing.type: Easing.InCubic
        onFinished: root.finishLaunch() }
    NumberAnimation { id: flyAnim; target: flightLayer; property: "planeT"; from: 0; to: 1; duration: 1150; easing.type: Easing.InOutSine
        onFinished: { fadeTrail.start(); pingAnim.restart(); pollSoon.restart(); } }

    // ====================== UI ======================
    Item {
        anchors.fill: parent
        opacity: root.introBase
        scale: 0.96 + 0.04 * root.introBase

        Rectangle {
            id: frame
            anchors.fill: parent
            radius: root.s(4)
            color: Qt.alpha(root.base, 0.82)
            border.color: root.surface1
            border.width: 1
            clip: true

            // ---------- backdrop: dot grid ----------
            Canvas {
                anchors.fill: parent
                opacity: 0.55
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = String(root.subtext1);
                    ctx.globalAlpha = 0.16;
                    let g = root.s(26);
                    for (let x = g; x < width; x += g)
                        for (let y = g; y < height; y += g) ctx.fillRect(x, y, 1.5, 1.5);
                }
            }

            // ---------- backdrop: cloud streaks ----------
            Repeater {
                model: 6
                delegate: Rectangle {
                    required property int index
                    readonly property real len: root.s([220, 340, 160, 280, 200, 380][index])
                    readonly property real sp: [14, 22, 9, 17, 12, 26][index]
                    readonly property real span: frame.width + len
                    width: len
                    height: root.s([3, 2, 4, 2, 3, 2][index])
                    radius: height / 2
                    y: frame.height * [0.14, 0.31, 0.47, 0.62, 0.78, 0.9][index]
                    x: ((index * 311 - root.tm * sp * 4) % span + span) % span - len
                    color: root.blue
                    opacity: 0.05
                }
            }

            // ---------- backdrop: radar ----------
            Item {
                id: radar
                width: root.s(560); height: width
                x: frame.width - width * 0.62
                y: frame.height * 0.44 - height / 2
                opacity: 0.55 * root.introBoard
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        anchors.centerIn: parent
                        width: radar.width * (0.25 + index * 0.25); height: width; radius: width / 2
                        color: "transparent"
                        border.color: root.blue; border.width: 1
                        opacity: 0.12
                    }
                }
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: root.blue; opacity: 0.1 }
                Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: root.blue; opacity: 0.1 }
                Canvas {
                    id: sweep
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onPaint: {
                        let ctx = getContext("2d");
                        ctx.reset();
                        let c = width / 2, r = width / 2 - 2, steps = 46;
                        for (let i = 0; i < steps; i++) {
                            ctx.beginPath();
                            ctx.moveTo(c, c);
                            ctx.arc(c, c, r, -(i + 1) * 0.026, -i * 0.026);
                            ctx.closePath();
                            ctx.fillStyle = String(root.blue);
                            ctx.globalAlpha = 0.26 * (1 - i / steps);
                            ctx.fill();
                        }
                        ctx.globalAlpha = 0.7;
                        ctx.strokeStyle = String(root.blue);
                        ctx.lineWidth = 1.5;
                        ctx.beginPath(); ctx.moveTo(c, c); ctx.lineTo(c + r, c); ctx.stroke();
                    }
                    NumberAnimation on rotation { from: 0; to: 360; duration: 7000; loops: Animation.Infinite }
                }
            }

            // ---------- header ----------
            Item {
                id: header
                anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                anchors.topMargin: root.s(18); anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
                height: root.s(54)
                opacity: root.introContent
                transform: Translate { y: (1.0 - root.introContent) * root.s(-14) }

                PlaneGlyph {
                    id: logoPlane
                    width: root.s(38); height: root.s(32)
                    c1: root.blue; c2: root.pink
                    x: 0
                    y: (parent.height - height) / 2 + Math.sin(root.tm * 1.4) * root.s(2.5)
                    rotation: -10 + 5 * Math.sin(root.tm * 1.1)
                }
                Column {
                    id: titleCol
                    anchors.left: logoPlane.right; anchors.leftMargin: root.s(14)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(2)
                    Text { text: "AEROGET"; font.family: root.fDisp; font.weight: Font.ExtraBold; font.pixelSize: root.s(26); font.letterSpacing: 7; color: root.text }
                    Text { text: "TERMINAL 1  \u00b7  GATE YT-DLP"; font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 2; color: root.subtext0 }
                }
                Item {
                    id: marquee
                    anchors.left: titleCol.right; anchors.leftMargin: root.s(40)
                    anchors.right: clockCol.left; anchors.rightMargin: root.s(30)
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.s(20)
                    clip: true
                    Text {
                        id: mtext
                        anchors.verticalCenter: parent.verticalCenter
                        text: "NOW BOARDING  ///  PASTE ANY LINK  ///  YOUTUBE \u00b7 VIMEO \u00b7 TWITCH \u00b7 SOUNDCLOUD \u00b7 1000+ SITES  ///  QUALITY UP TO 4K  ///  FLIGHTS KEEP GOING AFTER YOU CLOSE THIS WINDOW  ///"
                        font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 2; color: root.peach; opacity: 0.8
                        NumberAnimation on x { from: marquee.width; to: -mtext.implicitWidth; duration: 52000; loops: Animation.Infinite }
                    }
                    Rectangle { anchors.left: parent.left; width: root.s(30); height: parent.height; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Qt.alpha(root.base, 0.9) } GradientStop { position: 1; color: "transparent" } } }
                    Rectangle { anchors.right: parent.right; width: root.s(30); height: parent.height; gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Qt.alpha(root.base, 0.9) } } }
                }
                Column {
                    id: clockCol
                    anchors.right: escBtn.left; anchors.rightMargin: root.s(18)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.s(1)
                    Text { anchors.right: parent.right; text: root.clockStr; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(18); color: root.text }
                    Text { anchors.right: parent.right; text: "LOCAL TIME"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                }
                Rectangle {
                    id: escBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: root.s(48); height: root.s(30); radius: root.s(3)
                    color: escMa.containsMouse ? Qt.alpha(root.red, 0.16) : "transparent"
                    border.color: escMa.containsMouse ? root.red : root.surface2; border.width: 1
                    Text { anchors.centerIn: parent; text: "ESC"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 1.5; color: escMa.containsMouse ? root.red : root.subtext0 }
                    MouseArea { id: escMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.requestClose() }
                }
            }

            // ---------- left column ----------
            Item {
                id: leftCol
                anchors.top: header.bottom; anchors.topMargin: root.s(8)
                anchors.left: parent.left; anchors.leftMargin: root.s(26)
                anchors.bottom: runway.top; anchors.bottomMargin: root.s(12)
                width: root.s(590)

                // ----- check-in -----
                Item {
                    id: checkin
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    height: root.s(118)
                    opacity: root.introContent
                    transform: Translate { y: (1.0 - root.introContent) * root.s(18) }

                    Text { x: 0; y: 0; text: "CHECK-IN"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.blue }
                    Text { anchors.right: parent.right; y: 0; text: "STEP 01  \u00b7  PASTE A LINK"; font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 2; color: root.subtext1 }

                    TextInput {
                        id: urlInput
                        x: 0; y: root.s(20)
                        width: parent.width - root.s(176); height: root.s(58)
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: root.fDisp; font.weight: Font.DemiBold; font.pixelSize: root.s(38)
                        color: root.text
                        selectByMouse: true
                        clip: true
                        selectionColor: root.blue; selectedTextColor: root.crust
                        onAccepted: root.submit()
                        onTextChanged: {
                            let t = text.trim();
                            if (t === "") {
                                debounce.stop();
                                root.queuedUrl = "";
                                if (!root.launching && root.phase !== "idle") root.phase = "idle";
                            } else debounce.restart();
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: urlInput.text === ""
                            text: "Where to?"
                            font: urlInput.font
                            color: root.subtext1; opacity: 0.45 + 0.2 * root.glow
                        }
                    }

                    Row {
                        anchors.right: parent.right; y: root.s(34)
                        spacing: root.s(8)
                        Btn { hub: root; label: "PASTE"; accent: root.peach; onClicked: { root.clipForce = true; clipProc.running = true; } }
                        Btn { hub: root; label: "CHECK IN"; accent: root.blue; onClicked: root.submit() }
                    }

                    // underline
                    Rectangle { id: baseLine; x: 0; y: root.s(84); width: parent.width; height: 2; color: root.surface1 }
                    Rectangle {
                        x: 0; y: baseLine.y; height: 2
                        width: parent.width * (urlInput.activeFocus ? 1.0 : 0.16)
                        color: root.blue
                        Behavior on width { NumberAnimation { duration: 520; easing.type: Easing.OutExpo } }
                    }
                    Rectangle {
                        id: runner
                        y: baseLine.y - 1; height: 4; width: root.s(140)
                        visible: root.phase === "loading"
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: root.peach }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        NumberAnimation on x { running: root.phase === "loading"; from: -root.s(140); to: checkin.width; duration: 900; loops: Animation.Infinite; easing.type: Easing.InOutSine }
                    }

                    Text {
                        x: 0; y: root.s(94); width: parent.width
                        elide: Text.ElideRight
                        font.family: root.fMono; font.pixelSize: root.s(11); font.letterSpacing: 1
                        color: root.phase === "denied" ? root.red : (root.phase === "ready" ? root.green : root.subtext0)
                        text: root.phase === "loading" ? (root.loadMsgs[root.loadIdx] + " ...")
                            : root.phase === "ready" ? "CLEARED FOR BOARDING  \u00b7  \u2191\u2193 PICK A CABIN  \u00b7  ENTER TO TAKE OFF"
                            : root.phase === "denied" ? ("DENIED  \u00b7  " + root.errorText)
                            : (urlInput.text.trim() !== "" && !root.isUrl(urlInput.text.trim()) ? "THAT DOESN'T LOOK LIKE A LINK" : "PASTE A LINK \u2014 IT BOARDS BY ITSELF")
                    }
                }

                // ----- stage -----
                Item {
                    id: stage
                    anchors.top: checkin.bottom; anchors.topMargin: root.s(14)
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom

                    // ===== idle: live route map =====
                    Item {
                        id: idlePane
                        anchors.fill: parent
                        opacity: root.phase === "idle" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 240 } }
                        Canvas {
                            id: mapCanvas
                            anchors.fill: parent
                            property real t: root.tm
                            onTChanged: { if (visible) requestPaint(); }
                            onPaint: {
                                let ctx = getContext("2d");
                                ctx.reset();
                                let W = width, H = height;
                                const pts = [[0.10, 0.66, "NBO"], [0.26, 0.30, "LHR"], [0.46, 0.58, "DXB"], [0.64, 0.26, "NRT"], [0.86, 0.60, "SYD"], [0.40, 0.86, "JNB"], [0.78, 0.86, "SIN"]];
                                const routes = [[0, 2], [2, 3], [1, 4], [0, 1], [2, 4], [5, 2], [6, 3], [5, 6]];
                                ctx.font = Math.round(root.s(9)) + "px monospace";
                                for (let i = 0; i < routes.length; i++) {
                                    let a = pts[routes[i][0]], b = pts[routes[i][1]];
                                    let ax = a[0] * W, ay = a[1] * H, bx = b[0] * W, by = b[1] * H;
                                    let cx = (ax + bx) / 2, cy = Math.min(ay, by) - H * 0.24;
                                    ctx.fillStyle = String(root.subtext1);
                                    ctx.globalAlpha = 0.4;
                                    for (let k = 0; k <= 56; k += 2) {
                                        let u = k / 56, v = 1 - u;
                                        ctx.fillRect(v * v * ax + 2 * v * u * cx + u * u * bx - 1, v * v * ay + 2 * v * u * cy + u * u * by - 1, 2, 2);
                                    }
                                    let u0 = (t * 0.085 + i * 0.137) % 1;
                                    for (let k2 = 0; k2 < 20; k2++) {
                                        let uu = u0 - k2 * 0.011;
                                        if (uu < 0) break;
                                        let vv = 1 - uu;
                                        ctx.fillStyle = String(root.blue);
                                        ctx.globalAlpha = 0.85 * (1 - k2 / 20);
                                        let rr = Math.max(0.8, 2.6 - k2 * 0.1);
                                        ctx.beginPath();
                                        ctx.arc(vv * vv * ax + 2 * vv * uu * cx + uu * uu * bx, vv * vv * ay + 2 * vv * uu * cy + uu * uu * by, rr, 0, Math.PI * 2);
                                        ctx.fill();
                                    }
                                    let hv = 1 - u0;
                                    let hx = hv * hv * ax + 2 * hv * u0 * cx + u0 * u0 * bx, hy = hv * hv * ay + 2 * hv * u0 * cy + u0 * u0 * by;
                                    let dx = 2 * hv * (cx - ax) + 2 * u0 * (bx - cx), dy = 2 * hv * (cy - ay) + 2 * u0 * (by - cy);
                                    ctx.save();
                                    ctx.translate(hx, hy);
                                    ctx.rotate(Math.atan2(dy, dx));
                                    ctx.globalAlpha = 1;
                                    ctx.fillStyle = String(root.text);
                                    let z = root.s(7);
                                    ctx.beginPath(); ctx.moveTo(z, 0); ctx.lineTo(-z * 0.9, -z * 0.55); ctx.lineTo(-z * 0.3, 0); ctx.closePath(); ctx.fill();
                                    ctx.fillStyle = String(root.peach);
                                    ctx.beginPath(); ctx.moveTo(z, 0); ctx.lineTo(-z * 0.3, 0); ctx.lineTo(-z * 0.55, z * 0.4); ctx.closePath(); ctx.fill();
                                    ctx.restore();
                                }
                                for (let n = 0; n < pts.length; n++) {
                                    let px = pts[n][0] * W, py = pts[n][1] * H;
                                    let ph = (t * 0.7 + n * 0.31) % 1;
                                    ctx.strokeStyle = String(root.peach);
                                    ctx.globalAlpha = (1 - ph) * 0.5;
                                    ctx.lineWidth = 1;
                                    ctx.beginPath(); ctx.arc(px, py, 3 + ph * root.s(14), 0, Math.PI * 2); ctx.stroke();
                                    ctx.globalAlpha = 1;
                                    ctx.fillStyle = String(root.peach);
                                    ctx.beginPath(); ctx.arc(px, py, 3, 0, Math.PI * 2); ctx.fill();
                                    ctx.fillStyle = String(root.subtext0);
                                    ctx.fillText(pts[n][2], px + 7, py - 6);
                                }
                            }
                        }
                        Column {
                            anchors.left: parent.left; anchors.bottom: parent.bottom
                            anchors.leftMargin: root.s(4); anchors.bottomMargin: root.s(2)
                            spacing: root.s(3)
                            Text { text: "NO ACTIVE BOOKING"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.blue }
                            Text { text: "Copy a video link and open AeroGet \u2014 it checks in on its own."; font.family: root.fMono; font.pixelSize: root.s(10); color: root.subtext0 }
                        }
                    }

                    // ===== loading: ghost ticket + scanner =====
                    Item {
                        id: loadPane
                        anchors.fill: parent
                        opacity: root.phase === "loading" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        TicketShape {
                            id: ghostTicket
                            width: parent.width; height: root.s(350)
                            ghost: true; edge: root.blue; nx: width * 0.64
                            opacity: 0.35 + 0.25 * root.glow
                        }
                        Item {
                            width: ghostTicket.width; height: ghostTicket.height; clip: true
                            Rectangle {
                                width: root.s(90); height: parent.height
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "transparent" }
                                    GradientStop { position: 0.5; color: Qt.alpha(root.blue, 0.35) }
                                    GradientStop { position: 1.0; color: "transparent" }
                                }
                                NumberAnimation on x { running: root.phase === "loading"; from: -root.s(90); to: ghostTicket.width; duration: 1100; loops: Animation.Infinite; easing.type: Easing.InOutSine }
                            }
                        }
                        Column {
                            anchors.horizontalCenter: ghostTicket.horizontalCenter
                            y: ghostTicket.height / 2 - height / 2
                            spacing: root.s(8)
                            FlapText { anchors.horizontalCenter: parent.horizontalCenter; text: "CHECKING IN"; len: 11; cw: root.s(18); chh: root.s(30); fontPx: root.s(18); fg: root.peach; bg: root.crust }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: root.loadMsgs[root.loadIdx]; font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.subtext0 }
                        }
                    }

                    // ===== denied =====
                    Item {
                        id: deniedPane
                        anchors.fill: parent
                        opacity: root.phase === "denied" ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        Rectangle {
                            id: deniedStamp
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.s(70)
                            width: dsText.implicitWidth + root.s(48); height: root.s(70)
                            color: "transparent"; border.color: root.red; border.width: 4; radius: root.s(4)
                            rotation: -6
                            scale: root.phase === "denied" ? 1 : 2.2
                            Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                            Text { id: dsText; anchors.centerIn: parent; text: "DENIED BOARDING"; font.family: root.fDisp; font.weight: Font.ExtraBold; font.pixelSize: root.s(30); font.letterSpacing: 5; color: root.red }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.s(170); width: parent.width * 0.85
                            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
                            text: root.errorText
                            font.family: root.fMono; font.pixelSize: root.s(12); color: root.text
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: root.s(230)
                            text: "FIX THE LINK AND PRESS ENTER"
                            font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.subtext0
                        }
                    }

                    // ===== ready: boarding pass =====
                    Item {
                        id: readyPane
                        anchors.fill: parent
                        property real tear: 0
                        property real readyT: root.phase === "ready" ? 1 : 0
                        Behavior on readyT { NumberAnimation { duration: 560; easing.type: Easing.OutCubic } }
                        visible: readyT > 0.01 || tear > 0

                        Item {
                            id: ticket
                            readonly property real nx: width * 0.64
                            width: parent.width; height: root.s(350)
                            y: (1 - readyPane.readyT) * root.s(46)
                            opacity: readyPane.readyT * (1 - readyPane.tear)
                            scale: (0.94 + 0.06 * readyPane.readyT) * (1 - 0.3 * readyPane.tear)
                            transform: Rotation {
                                origin.x: ticket.width / 2; origin.y: ticket.height / 2
                                axis { x: 1; y: 0; z: 0 }
                                angle: 78 * readyPane.tear
                            }

                            Rectangle { x: root.s(5); y: root.s(8); width: parent.width - root.s(6); height: parent.height; radius: root.s(10); color: "#000000"; opacity: 0.10 }
                            Rectangle { x: root.s(3); y: root.s(4); width: parent.width - root.s(3); height: parent.height; radius: root.s(9); color: "#000000"; opacity: 0.12 }

                            TicketShape {
                                anchors.fill: parent
                                fillA: Qt.lighter(root.surface0, 1.12)
                                fillB: root.surface0
                                stubFill: Qt.alpha(root.crust, 0.55)
                                edge: root.surface2
                                accent: root.blue
                                nx: ticket.nx
                            }

                            // ---- main section ----
                            Item {
                                id: mainArea
                                x: 0; y: 0; width: ticket.nx; height: ticket.height

                                Text { x: root.s(22); y: root.s(16); text: "BOARDING PASS"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.blue }
                                Text { anchors.right: parent.right; anchors.rightMargin: root.s(22); y: root.s(16); text: "SEAT " + (root.hashStr(root.info.url || "") % 38 + 1) + String.fromCharCode(65 + root.hashStr(root.info.title || "") % 6); font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 2; color: root.subtext0 }

                                // passenger photo
                                Item {
                                    id: photoBox
                                    x: root.s(22); y: root.s(40); width: root.s(176); height: root.s(99)
                                    Rectangle { anchors.fill: parent; color: root.crust }
                                    Image {
                                        anchors.fill: parent
                                        source: (root.info.thumb && root.info.thumb !== "") ? "file://" + root.info.thumb : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true; smooth: true
                                    }
                                    Rectangle { anchors.fill: parent; color: "transparent"; border.color: root.surface2; border.width: 1 }
                                    // corner brackets
                                    Repeater {
                                        model: 4
                                        delegate: Item {
                                            required property int index
                                            x: (index % 2 === 0) ? root.s(-3) : photoBox.width - root.s(11) + root.s(3)
                                            y: (index < 2) ? root.s(-3) : photoBox.height - root.s(11) + root.s(3)
                                            width: root.s(11); height: root.s(11)
                                            Rectangle { x: 0; y: (index < 2) ? 0 : parent.height - 2; width: parent.width; height: 2; color: root.peach }
                                            Rectangle { x: (index % 2 === 0) ? 0 : parent.width - 2; y: 0; width: 2; height: parent.height; color: root.peach }
                                        }
                                    }
                                    // scanner line
                                    Rectangle {
                                        width: parent.width; height: 2
                                        y: ((root.tm * 0.45) % 1) * photoBox.height
                                        visible: root.phase === "ready"
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 0.5; color: root.blue }
                                            GradientStop { position: 1.0; color: "transparent" }
                                        }
                                        opacity: 0.85
                                    }
                                    // stamp
                                    Rectangle {
                                        id: stamp
                                        property real st: 0
                                        anchors.centerIn: parent
                                        width: stampText.implicitWidth + root.s(16); height: root.s(30)
                                        color: Qt.alpha(root.crust, 0.4)
                                        border.color: root.green; border.width: 3; radius: root.s(3)
                                        rotation: -12
                                        scale: 2.4 - 1.4 * st
                                        opacity: Math.min(1, st * 1.6)
                                        Text { id: stampText; anchors.centerIn: parent; text: "CLEARED"; font.family: root.fDisp; font.weight: Font.ExtraBold; font.pixelSize: root.s(15); font.letterSpacing: 3; color: root.green }
                                        SequentialAnimation {
                                            id: stampAnim
                                            PauseAnimation { duration: 380 }
                                            NumberAnimation { target: stamp; property: "st"; from: 0; to: 1; duration: 280; easing.type: Easing.OutBack }
                                        }
                                    }
                                    Connections { target: root; function onPhaseChanged() { if (root.phase === "ready") { stamp.st = 0; stampAnim.restart(); } } }
                                }

                                // fields beside photo
                                Column {
                                    x: photoBox.x + photoBox.width + root.s(18); y: root.s(40)
                                    width: ticket.nx - x - root.s(20)
                                    spacing: root.s(7)
                                    Column {
                                        width: parent.width; spacing: root.s(1)
                                        Text { text: "FROM"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                        Text { width: parent.width; elide: Text.ElideRight; text: root.hostOf(root.info.url).toUpperCase(); font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    }
                                    Column {
                                        width: parent.width; spacing: root.s(1)
                                        Text { text: "AIRLINE"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                        Text { width: parent.width; elide: Text.ElideRight; text: (root.info.uploader || "UNKNOWN").toUpperCase(); font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.text }
                                    }
                                    Column {
                                        width: parent.width; spacing: root.s(1)
                                        Text { text: "FLIGHT TIME"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                        Text { text: root.info.live ? "LIVE" : (root.info.duration_str || "--:--"); font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(13); color: root.peach }
                                    }
                                }

                                // destination (title)
                                Text { x: root.s(22); y: root.s(152); text: "TO"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                Text {
                                    x: root.s(22); y: root.s(164)
                                    width: ticket.nx - root.s(44); height: root.s(56)
                                    text: root.info.title || ""
                                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                    font.family: root.fDisp; font.weight: Font.DemiBold; font.pixelSize: root.s(20)
                                    color: root.text
                                }

                                // class / weight / dest
                                Row {
                                    x: root.s(22); y: root.s(238)
                                    spacing: root.s(16)
                                    Column {
                                        spacing: root.s(4)
                                        Text { text: "CLASS"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                        FlapText { text: root.classText; len: 10; cw: root.s(10); chh: root.s(18); fontPx: root.s(11); fg: root.peach; bg: root.crust }
                                    }
                                    Column {
                                        spacing: root.s(4)
                                        Text { text: "WEIGHT"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                        FlapText { text: root.sizeText; len: 8; cw: root.s(10); chh: root.s(18); fontPx: root.s(11); fg: root.green; bg: root.crust }
                                    }
                                    Column {
                                        spacing: root.s(4)
                                        Text { text: "DEST \u25b8"; font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1 }
                                        Text {
                                            id: destTxt
                                            width: root.s(70); elide: Text.ElideMiddle
                                            height: root.s(18); verticalAlignment: Text.AlignVCenter
                                            text: root.shortDir(root.destDir)
                                            font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(11)
                                            color: destMa.containsMouse ? root.blue : root.text
                                            MouseArea { id: destMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openPicker() }
                                        }
                                    }
                                }

                                // barcode
                                BarCode {
                                    id: barcode
                                    x: root.s(22); y: root.s(298)
                                    width: ticket.nx - root.s(44); height: root.s(30)
                                    seed: root.hashStr((root.info.url || "") + (root.info.title || ""))
                                    col: root.text
                                    opacity: 0.8
                                }
                                Rectangle {
                                    x: barcode.x + ((root.tm * 0.35) % 1) * barcode.width; y: barcode.y - root.s(3)
                                    width: 2; height: barcode.height + root.s(6)
                                    color: root.red; opacity: 0.85
                                    visible: root.phase === "ready"
                                }
                            }

                            // ---- stub: cabin classes ----
                            Item {
                                id: stubArea
                                x: ticket.nx; y: 0; width: ticket.width - ticket.nx; height: ticket.height

                                Text { x: root.s(18); y: root.s(16); text: "CABIN CLASS"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.peach }

                                Item {
                                    id: classList
                                    x: 0; y: root.s(40); width: stubArea.width
                                    height: (root.info.presets ? root.info.presets.length : 0) * root.s(30)
                                    Rectangle {
                                        x: root.s(8); width: classList.width - root.s(16); height: root.s(28)
                                        y: root.sel * root.s(30) + 1
                                        radius: root.s(3)
                                        color: Qt.alpha(root.blue, 0.16); border.color: root.blue; border.width: 1
                                        Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                    }
                                    Repeater {
                                        model: root.info.presets || []
                                        delegate: Item {
                                            id: cr
                                            required property var modelData
                                            required property int index
                                            readonly property bool on: index === root.sel
                                            width: classList.width; height: root.s(30)
                                            y: index * height
                                            Rectangle {
                                                x: root.s(20); anchors.verticalCenter: parent.verticalCenter
                                                width: root.s(10); height: width; radius: width / 2
                                                color: "transparent"; border.color: cr.on ? root.blue : root.subtext1; border.width: 1.5
                                                Rectangle { anchors.centerIn: parent; width: parent.width - root.s(5); height: width; radius: width / 2; color: root.blue; scale: cr.on ? 1 : 0; Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } } }
                                            }
                                            Text {
                                                x: root.s(38); anchors.verticalCenter: parent.verticalCenter
                                                text: cr.modelData.label + (cr.modelData.id === "best" ? "  " + cr.modelData.detail : "")
                                                font.family: root.fMono; font.pixelSize: root.s(11); font.weight: cr.on ? Font.Bold : Font.Normal
                                                color: cr.on ? root.text : (crMa.containsMouse ? root.text : root.subtext0)
                                            }
                                            Text {
                                                anchors.right: parent.right; anchors.rightMargin: root.s(18); anchors.verticalCenter: parent.verticalCenter
                                                text: root.fmtCompact(cr.modelData.est)
                                                font.family: root.fMono; font.pixelSize: root.s(9); color: cr.on ? root.peach : root.subtext1
                                            }
                                            MouseArea { id: crMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.sel = cr.index }
                                        }
                                    }
                                }

                                // take off
                                Item {
                                    id: tkBtn
                                    x: root.s(18); width: stubArea.width - root.s(36); height: root.s(48)
                                    y: stubArea.height - height - root.s(18)
                                    scale: tkMa.pressed ? 0.96 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 90 } }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: parent.width + root.s(10) * root.glow; height: parent.height + root.s(10) * root.glow
                                        radius: root.s(5); color: "transparent"
                                        border.color: root.blue; border.width: 1; opacity: 0.35 * (1 - root.glow)
                                    }
                                    Rectangle {
                                        anchors.fill: parent; radius: root.s(4); clip: true
                                        gradient: Gradient {
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: root.blue }
                                            GradientStop { position: 1.0; color: root.mauve }
                                        }
                                        Rectangle {
                                            width: root.s(40); height: parent.height * 2; y: -parent.height / 2
                                            rotation: 20; color: "#ffffff"; opacity: 0.28
                                            NumberAnimation on x { running: tkMa.containsMouse; from: -root.s(60); to: tkBtn.width + root.s(20); duration: 800; loops: Animation.Infinite }
                                        }
                                        Row {
                                            anchors.centerIn: parent; spacing: root.s(8)
                                            PlaneGlyph { width: root.s(20); height: root.s(17); c1: root.crust; c2: Qt.alpha(root.crust, 0.6); anchors.verticalCenter: parent.verticalCenter; x: tkMa.containsMouse ? root.s(4) : 0 }
                                            Text { text: "TAKE OFF"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(12); font.letterSpacing: 2.5; color: root.crust; anchors.verticalCenter: parent.verticalCenter }
                                        }
                                    }
                                    MouseArea { id: tkMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.launch() }
                                }
                            }
                        }

                        // key hints
                        Row {
                            anchors.left: parent.left; anchors.leftMargin: root.s(4)
                            anchors.top: ticket.bottom; anchors.topMargin: root.s(18)
                            spacing: root.s(22)
                            opacity: readyPane.readyT * (1 - readyPane.tear)
                            Repeater {
                                model: [{ k: "\u2191\u2193", d: "CABIN" }, { k: "ENTER", d: "TAKE OFF" }, { k: "ESC", d: "CLOSE" }]
                                delegate: Row {
                                    required property var modelData
                                    spacing: root.s(7)
                                    Rectangle {
                                        height: root.s(20); width: kt.implicitWidth + root.s(14); radius: root.s(3)
                                        color: "transparent"; border.color: root.surface2; border.width: 1
                                        Text { id: kt; anchors.centerIn: parent; text: modelData.k; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(9); color: root.text }
                                    }
                                    Text { text: modelData.d; anchors.verticalCenter: parent.verticalCenter; font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 2; color: root.subtext0 }
                                }
                            }
                        }
                    }
                }
            }

            // ---------- departure board ----------
            Item {
                id: board
                anchors.top: header.bottom; anchors.topMargin: root.s(8)
                anchors.left: leftCol.right; anchors.leftMargin: root.s(24)
                anchors.right: parent.right; anchors.rightMargin: root.s(26)
                anchors.bottom: runway.top; anchors.bottomMargin: root.s(12)
                opacity: root.introBoard
                transform: Translate { x: (1.0 - root.introBoard) * root.s(50) }

                Rectangle {
                    anchors.fill: parent
                    radius: root.s(3)
                    color: Qt.rgba(0, 0, 0, 0.36)
                    border.color: root.surface1; border.width: 1
                }
                Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 3; color: root.peach; opacity: 0.8 }

                Item {
                    id: bHead
                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    height: root.s(108)

                    Column {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.topMargin: root.s(6)
                        spacing: root.s(8)
                        FlapText { text: "DEPARTURES"; len: 10; cw: root.s(14); chh: root.s(26); fontPx: root.s(16); fg: root.peach; bg: root.crust }
                        Text {
                            text: root.activeCount + " IN FLIGHT   \u00b7   " + root.queuedCount + " BOARDING   \u00b7   " + root.doneCount + " LANDED"
                            font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 1; color: root.subtext0
                        }
                    }

                    Canvas {
                        id: dial
                        anchors.right: parent.right; anchors.top: parent.top
                        width: root.s(150); height: root.s(80)
                        property real needle: Math.min(1, root.totalSpeed / (root.dialMaxMB * 1048576))
                        Behavior on needle { SpringAnimation { spring: 2.6; damping: 0.22 } }
                        onNeedleChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onPaint: {
                            let ctx = getContext("2d");
                            ctx.reset();
                            let w = width, h = height, cx = w / 2, cy = h - root.s(6);
                            let r = Math.min(w / 2 - root.s(8), h - root.s(14));
                            let nd = Math.max(0, Math.min(1, needle));
                            ctx.lineCap = "round";
                            ctx.lineWidth = root.s(7);
                            ctx.strokeStyle = String(root.surface1);
                            ctx.beginPath(); ctx.arc(cx, cy, r, Math.PI, Math.PI * 2); ctx.stroke();
                            let a1 = Math.PI + Math.PI * nd;
                            if (nd > 0.005) {
                                ctx.strokeStyle = String(root.blue);
                                ctx.beginPath(); ctx.arc(cx, cy, r, Math.PI, a1); ctx.stroke();
                            }
                            ctx.lineWidth = 1;
                            ctx.strokeStyle = String(root.subtext1);
                            for (let i = 0; i <= 10; i++) {
                                let a = Math.PI + Math.PI * i / 10;
                                let r1 = r - root.s(10), r2 = r - root.s(i % 5 === 0 ? 18 : 14);
                                ctx.beginPath();
                                ctx.moveTo(cx + Math.cos(a) * r1, cy + Math.sin(a) * r1);
                                ctx.lineTo(cx + Math.cos(a) * r2, cy + Math.sin(a) * r2);
                                ctx.stroke();
                            }
                            ctx.lineWidth = root.s(2.5);
                            ctx.strokeStyle = String(root.peach);
                            ctx.beginPath(); ctx.moveTo(cx, cy);
                            ctx.lineTo(cx + Math.cos(a1) * (r - root.s(8)), cy + Math.sin(a1) * (r - root.s(8)));
                            ctx.stroke();
                            ctx.fillStyle = String(root.peach);
                            ctx.beginPath(); ctx.arc(cx, cy, root.s(4), 0, Math.PI * 2); ctx.fill();
                        }
                        Text { x: root.s(2); y: parent.height - root.s(8); text: "0"; font.family: root.fMono; font.pixelSize: root.s(8); color: root.subtext1 }
                        Text { anchors.right: parent.right; anchors.rightMargin: root.s(2); y: parent.height - root.s(8); text: root.dialMaxMB; font.family: root.fMono; font.pixelSize: root.s(8); color: root.subtext1 }
                    }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: root.s(12); anchors.bottom: parent.bottom
                        text: root.totalSpeed > 0 ? "AIRSPEED  " + root.fmtBytes(root.totalSpeed).toUpperCase() + "/S" : "AIRSPEED  0"
                        font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 1; color: root.totalSpeed > 0 ? root.blue : root.subtext1
                    }
                }

                Rectangle { id: bSep; anchors.top: bHead.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16); height: 1; color: root.surface1 }

                ListView {
                    id: jobList
                    anchors.top: bSep.bottom; anchors.topMargin: root.s(2)
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: root.s(16); anchors.rightMargin: root.s(16)
                    anchors.bottom: bFoot.top; anchors.bottomMargin: root.s(4)
                    clip: true
                    model: jobModel
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320 }
                            NumberAnimation { property: "x"; from: root.s(80); to: 0; duration: 420; easing.type: Easing.OutCubic }
                        }
                    }
                    remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 200 } }
                    displaced: Transition { NumberAnimation { properties: "y"; duration: 260; easing.type: Easing.OutCubic } }

                    delegate: Item {
                        id: row
                        required property int index
                        required property string jid
                        required property string title
                        required property string host
                        required property string stat
                        required property string raw
                        required property real pct
                        required property real speed
                        required property real eta
                        required property real size
                        required property string err
                        required property string thumb
                        required property string presetLabel
                        readonly property bool active: raw === "downloading" || raw === "starting"
                        readonly property bool canStop: active || raw === "queued"
                        readonly property color sc: root.statColor(stat)
                        width: ListView.view ? ListView.view.width : 0
                        height: root.s(86)

                        HoverHandler { id: rowHover }
                        Rectangle { anchors.fill: parent; color: root.blue; opacity: rowHover.hovered ? 0.06 : 0 ; Behavior on opacity { NumberAnimation { duration: 140 } } }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.surface1; opacity: 0.7 }

                        Rectangle {
                            id: thumbBox
                            x: root.s(2); y: root.s(14); width: root.s(64); height: root.s(40)
                            color: root.crust; border.color: row.sc; border.width: 1
                            Image {
                                anchors.fill: parent; anchors.margins: 1
                                source: row.thumb !== "" ? "file://" + row.thumb : ""
                                fillMode: Image.PreserveAspectCrop; asynchronous: true; smooth: true
                                opacity: row.raw === "done" ? 1 : 0.8
                            }
                        }

                        Column {
                            id: flapCol
                            anchors.right: parent.right; anchors.rightMargin: root.s(4)
                            y: root.s(10)
                            spacing: root.s(6)
                            FlapText { text: row.stat; len: 9; cw: root.s(12); chh: root.s(20); fontPx: root.s(12); fg: row.sc; bg: root.crust }
                            Row {
                                spacing: root.s(8)
                                FlapText { text: Math.round(row.pct) + "%"; len: 4; rightAlign: true; cw: root.s(12); chh: root.s(20); fontPx: root.s(12); fg: root.text; bg: root.crust }
                                FlapText {
                                    text: row.raw === "done" ? root.fmtCompact(row.size) : (row.active ? root.fmtEta(row.eta) : "--:--")
                                    len: 5; rightAlign: true; cw: root.s(12); chh: root.s(20); fontPx: root.s(12); fg: root.subtext0; bg: root.crust
                                }
                            }
                        }

                        Column {
                            anchors.left: thumbBox.right; anchors.leftMargin: root.s(12)
                            anchors.right: flapCol.left; anchors.rightMargin: root.s(10)
                            y: root.s(14)
                            spacing: root.s(6)
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: row.title.toUpperCase()
                                font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(11); color: root.text
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                visible: !rowHover.hovered
                                text: row.raw === "error" ? row.err
                                    : (row.host.toUpperCase() + "  \u00b7  " + row.presetLabel + (row.active && row.speed > 0 ? "  \u00b7  " + root.fmtBytes(row.speed) + "/s" : ""))
                                font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 0.5
                                color: row.raw === "error" ? root.red : root.subtext0
                            }
                            Row {
                                visible: rowHover.hovered
                                spacing: root.s(14)
                                Text {
                                    visible: row.canStop
                                    text: "ABORT"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(9); font.letterSpacing: 1.5
                                    color: abMa.containsMouse ? root.red : root.subtext0
                                    MouseArea { id: abMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.run(["cancel", row.jid]) }
                                }
                                Text {
                                    visible: row.raw === "error" || row.raw === "cancelled"
                                    text: "RETRY"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(9); font.letterSpacing: 1.5
                                    color: reMa.containsMouse ? root.peach : root.subtext0
                                    MouseArea { id: reMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.run(["retry", row.jid]) }
                                }
                                Text {
                                    visible: row.raw === "done"
                                    text: "OPEN"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(9); font.letterSpacing: 1.5
                                    color: opMa.containsMouse ? root.green : root.subtext0
                                    MouseArea { id: opMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.run(["open", row.jid]) }
                                }
                                Text {
                                    text: "CLEAR"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(9); font.letterSpacing: 1.5
                                    color: clMa.containsMouse ? root.text : root.subtext1
                                    MouseArea { id: clMa; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: root.run(["remove", row.jid]) }
                                }
                            }
                        }

                        // contrail progress
                        Item {
                            x: root.s(2); y: parent.height - root.s(18); width: parent.width - root.s(4); height: root.s(8)
                            visible: row.raw !== "error" && row.raw !== "cancelled" && row.raw !== "queued"
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; color: root.surface1 }
                            Rectangle {
                                id: fillBar
                                anchors.verticalCenter: parent.verticalCenter
                                height: 2; width: parent.width * Math.max(0, Math.min(100, row.pct)) / 100
                                color: row.sc
                                Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
                            }
                            PlaneGlyph {
                                visible: row.active
                                width: root.s(12); height: root.s(10)
                                c1: row.sc; c2: Qt.alpha(row.sc, 0.55)
                                x: Math.max(0, fillBar.width - width * 0.4); y: (parent.height - height) / 2 + Math.sin(root.tm * 4 + row.index) * root.s(1)
                            }
                        }
                    }
                }

                // empty state
                Column {
                    anchors.centerIn: jobList
                    spacing: root.s(10)
                    visible: jobModel.count === 0
                    opacity: 0.9
                    FlapText { anchors.horizontalCenter: parent.horizontalCenter; text: "NO FLIGHTS"; len: 10; cw: root.s(14); chh: root.s(24); fontPx: root.s(14); fg: root.subtext0; bg: root.crust }
                    FlapText { anchors.horizontalCenter: parent.horizontalCenter; text: "SCHEDULED"; len: 9; cw: root.s(14); chh: root.s(24); fontPx: root.s(14); fg: root.subtext0; bg: root.crust }
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "THE BOARD IS QUIET"; font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 3; color: root.subtext1 }
                }

                Item {
                    id: bFoot
                    anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                    anchors.margins: root.s(16)
                    height: root.s(32)
                    Row {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        spacing: root.s(8)
                        Btn { hub: root; label: "CLEAR LANDED"; accent: root.green; onClicked: root.run(["clear"]) }
                        Btn { hub: root; label: "FOLDER"; accent: root.blue; onClicked: Quickshell.execDetached(["xdg-open", root.destDir]) }
                        Btn { hub: root; label: "DESTINATION"; accent: root.peach; onClicked: root.openPicker() }
                    }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        font.family: root.fMono; font.pixelSize: root.s(8); font.letterSpacing: 2; color: root.subtext1
                    }
                }
            }

            // ---------- runway ----------
            Item {
                id: runway
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: root.s(26); anchors.rightMargin: root.s(26)
                anchors.bottom: parent.bottom; anchors.bottomMargin: root.s(14)
                height: root.s(34)
                opacity: root.introContent

                Text { id: rwyLabel; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "RWY 09L"; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 2; color: root.subtext0 }
                Item {
                    id: lights
                    anchors.left: rwyLabel.right; anchors.leftMargin: root.s(16)
                    anchors.right: rwyInfo.left; anchors.rightMargin: root.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.s(14)
                    Repeater {
                        model: 56
                        delegate: Rectangle {
                            required property int index
                            width: root.s(6); height: root.s(3); radius: 1
                            x: index * (lights.width / 56)
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.activeCount > 0 ? root.peach : root.surface2
                            opacity: root.activeCount > 0 ? 0.18 + 0.82 * Math.max(0, Math.sin(root.tm * 7 - index * 0.5)) : 0.35
                        }
                    }
                    PlaneGlyph {
                        width: root.s(22); height: root.s(18)
                        c1: root.text; c2: root.peach
                        anchors.verticalCenter: parent.verticalCenter
                        property real prog: root.activeCount > 0 ? root.avgPct / 100 : 0
                        Behavior on prog { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                        x: prog * (lights.width - width)
                        rotation: root.activeCount > 0 ? Math.sin(root.tm * 5) * 3 : 0
                    }
                }
                Text {
                    id: rwyInfo
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: root.activeCount > 0 ? "OVERALL " + Math.round(root.avgPct) + "%  \u00b7  " + root.shortDir(root.destDir).toUpperCase() : "STANDBY  \u00b7  " + root.shortDir(root.destDir).toUpperCase()
                    font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 1.5; color: root.activeCount > 0 ? root.peach : root.subtext1
                }
            }

                        // ---------- destination picker overlay ----------
            Rectangle {
                id: pickerDim
                anchors.fill: parent
                z: 55
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: root.pickerOpen ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 200 } }
                MouseArea { anchors.fill: parent; onClicked: { root.pickerOpen = false; urlInput.forceActiveFocus(); } }

                Rectangle {
                    id: pickerPanel
                    anchors.centerIn: parent
                    width: root.s(560); height: root.s(500)
                    radius: root.s(4)
                    color: Qt.alpha(root.base, 0.98)
                    border.color: root.peach; border.width: 1
                    scale: root.pickerOpen ? 1 : 0.92
                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                    MouseArea { anchors.fill: parent }

                    Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 3; color: root.peach }

                    Column {
                        id: pkTop
                        x: root.s(20); y: root.s(18)
                        width: parent.width - root.s(40)
                        spacing: root.s(10)

                        Item {
                            width: parent.width; height: root.s(26)
                            FlapText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.pickerOpen ? "DESTINATION" : ""
                                len: 11; cw: root.s(14); chh: root.s(24); fontPx: root.s(14); fg: root.peach; bg: root.crust
                            }
                            Text { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "ESC TO CANCEL"; font.family: root.fMono; font.pixelSize: root.s(9); font.letterSpacing: 2; color: root.subtext1 }
                        }
                        Text {
                            width: parent.width; elide: Text.ElideLeft
                            text: root.pickerPath
                            font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(12); color: root.text
                        }
                        Flow {
                            width: parent.width; spacing: root.s(8)
                            Repeater {
                                model: root.dirs
                                delegate: Rectangle {
                                    id: gate
                                    required property var modelData
                                    readonly property bool on: root.pickerPath === modelData
                                    height: root.s(24); width: gateTxt.implicitWidth + root.s(20); radius: root.s(3)
                                    color: on ? Qt.alpha(root.peach, 0.18) : (gateMa.containsMouse ? Qt.alpha(root.peach, 0.08) : "transparent")
                                    border.color: (on || gateMa.containsMouse) ? root.peach : root.surface2; border.width: 1
                                    Text { id: gateTxt; anchors.centerIn: parent; text: String(gate.modelData).split("/").pop().toUpperCase(); font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(9); font.letterSpacing: 1.5; color: gate.on ? root.peach : root.subtext0 }
                                    MouseArea { id: gateMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.listDir(gate.modelData) }
                                }
                            }
                        }
                        Row {
                            spacing: root.s(8)
                            Btn { hub: root; label: "\u2191 UP"; accent: root.blue; onClicked: root.goUp() }
                            Btn { hub: root; label: root.pickerHidden ? "HIDDEN  ON" : "HIDDEN  OFF"; accent: root.mauve; onClicked: root.pickerHidden = !root.pickerHidden }
                            Btn { hub: root; label: root.pickerNew ? "CANCEL NEW" : "+ NEW FOLDER"; accent: root.green; onClicked: root.pickerNew = !root.pickerNew }
                        }
                        Rectangle {
                            visible: root.pickerNew
                            width: parent.width; height: root.s(36)
                            color: "transparent"; border.color: root.blue; border.width: 1; radius: root.s(3)
                            TextInput {
                                id: pkNewInput
                                anchors.fill: parent; anchors.leftMargin: root.s(12); anchors.rightMargin: root.s(12)
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: root.fMono; font.pixelSize: root.s(13); color: root.text
                                selectByMouse: true; clip: true
                                selectionColor: root.blue; selectedTextColor: root.crust
                                onAccepted: root.makeFolder(text)
                                Text { anchors.verticalCenter: parent.verticalCenter; visible: pkNewInput.text === ""; text: "new folder name \u2014 Enter to create"; font: pkNewInput.font; color: root.subtext1; opacity: 0.6 }
                            }
                        }
                    }

                    Rectangle {
                        id: pkListBox
                        anchors.top: pkTop.bottom; anchors.topMargin: root.s(10)
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.leftMargin: root.s(20); anchors.rightMargin: root.s(20)
                        anchors.bottom: pkFoot.top; anchors.bottomMargin: root.s(12)
                        color: Qt.rgba(0, 0, 0, 0.25); border.color: root.surface1; border.width: 1; radius: root.s(3)
                        ListView {
                            anchors.fill: parent; anchors.margins: 1
                            clip: true
                            model: pickerModel
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: Item {
                                id: pd
                                required property string name
                                required property bool hid
                                readonly property bool vis: !hid || root.pickerHidden
                                width: ListView.view ? ListView.view.width : 0
                                height: vis ? root.s(34) : 0
                                visible: vis
                                opacity: hid ? 0.6 : 1
                                Rectangle { anchors.fill: parent; color: root.peach; opacity: pdMa.containsMouse ? 0.10 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
                                Item {
                                    x: root.s(14); anchors.verticalCenter: parent.verticalCenter
                                    width: root.s(18); height: root.s(14)
                                    Rectangle { x: 0; y: 0; width: root.s(8); height: root.s(4); radius: 1; color: root.peach }
                                    Rectangle { x: 0; y: root.s(3); width: parent.width; height: root.s(11); radius: root.s(2); color: root.peach; opacity: 0.85 }
                                }
                                Text {
                                    x: root.s(44); anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - root.s(80); elide: Text.ElideRight
                                    text: pd.name
                                    font.family: root.fMono; font.pixelSize: root.s(12); color: root.text
                                }
                                Text { anchors.right: parent.right; anchors.rightMargin: root.s(14); anchors.verticalCenter: parent.verticalCenter; text: "\u203a"; font.family: root.fMono; font.pixelSize: root.s(16); color: root.peach; opacity: pdMa.containsMouse ? 1 : 0.4 }
                                MouseArea { id: pdMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.enterDir(pd.name) }
                            }
                        }
                        Text { anchors.centerIn: parent; visible: root.pickerShown === 0; text: "NO SUBFOLDERS HERE"; font.family: root.fMono; font.pixelSize: root.s(10); font.letterSpacing: 3; color: root.subtext1 }
                    }

                    Item {
                        id: pkFoot
                        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
                        anchors.margins: root.s(20)
                        height: root.s(42)
                        Btn { hub: root; label: "CANCEL"; accent: root.subtext0; anchors.verticalCenter: parent.verticalCenter; onClicked: { root.pickerOpen = false; urlInput.forceActiveFocus(); } }
                        Rectangle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            width: root.s(300); height: root.s(42); radius: root.s(4); clip: true
                            scale: pkSelMa.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: 90 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: root.peach }
                                GradientStop { position: 1.0; color: root.green }
                            }
                            Rectangle {
                                width: root.s(40); height: parent.height * 2; y: -parent.height / 2
                                rotation: 20; color: "#ffffff"; opacity: 0.28
                                NumberAnimation on x { running: pkSelMa.containsMouse; from: -root.s(60); to: root.s(320); duration: 800; loops: Animation.Infinite }
                            }
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - root.s(24); horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                                text: "SELECT  \u00b7  " + (root.pickerPath.split("/").pop() || "/").toUpperCase()
                                font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(11); font.letterSpacing: 2; color: root.crust
                            }
                            MouseArea { id: pkSelMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectDir() }
                        }
                    }
                }
            }

            // ---------- toast ----------
            Rectangle {
                id: toastBox
                anchors.horizontalCenter: leftCol.horizontalCenter
                y: root.toastText !== "" ? frame.height - root.s(98) : frame.height + root.s(10)
                Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                width: toastLabel.implicitWidth + root.s(36); height: root.s(32)
                radius: root.s(3); color: Qt.alpha(root.crust, 0.95)
                border.color: root.peach; border.width: 1
                z: 60
                Text { id: toastLabel; anchors.centerIn: parent; text: root.toastText; font.family: root.fMono; font.weight: Font.Bold; font.pixelSize: root.s(10); font.letterSpacing: 2; color: root.peach }
            }

            // ---------- landing ping ----------
            Rectangle {
                id: ping
                property real k: 0
                x: flightLayer.x1 - width / 2; y: flightLayer.y1 - height / 2
                width: root.s(160); height: width; radius: width / 2
                color: "transparent"; border.color: root.peach; border.width: 2
                scale: 0.1 + k * 1.4; opacity: (1 - k) * 0.8
                visible: k > 0 && k < 1
                z: 49
                NumberAnimation on k { id: pingAnim; running: false; from: 0; to: 1; duration: 700; easing.type: Easing.OutCubic }
            }

            // ---------- flight overlay ----------
            Canvas {
                id: flightLayer
                anchors.fill: parent
                z: 50
                visible: false
                property real x0: 0
                property real y0: 0
                property real x1: 0
                property real y1: 0
                property real planeT: 0
                property var trail: []
                onPlaneTChanged: {
                    let t = planeT, cx = (x0 + x1) / 2, cy = Math.min(y0, y1) - root.s(170);
                    let v = 1 - t;
                    let px = v * v * x0 + 2 * v * t * cx + t * t * x1;
                    let py = v * v * y0 + 2 * v * t * cy + t * t * y1;
                    let dx = 2 * v * (cx - x0) + 2 * t * (x1 - cx);
                    let dy = 2 * v * (cy - y0) + 2 * t * (y1 - cy);
                    trail.push({ x: px, y: py, a: Math.atan2(dy, dx) });
                    if (trail.length > 48) trail.shift();
                    requestPaint();
                }
                onPaint: {
                    let ctx = getContext("2d");
                    ctx.reset();
                    let n = trail.length;
                    if (n < 2) return;
                    ctx.lineCap = "round";
                    ctx.strokeStyle = String(root.blue);
                    for (let i = 1; i < n; i++) {
                        let f = i / n;
                        ctx.globalAlpha = f * 0.7;
                        ctx.lineWidth = root.s(1) + f * root.s(5);
                        ctx.beginPath(); ctx.moveTo(trail[i - 1].x, trail[i - 1].y); ctx.lineTo(trail[i].x, trail[i].y); ctx.stroke();
                    }
                    let h = trail[n - 1];
                    ctx.globalAlpha = 1;
                    ctx.save();
                    ctx.translate(h.x, h.y);
                    ctx.rotate(h.a);
                    let z = root.s(15);
                    ctx.fillStyle = String(root.text);
                    ctx.beginPath(); ctx.moveTo(z, 0); ctx.lineTo(-z * 0.9, -z * 0.58); ctx.lineTo(-z * 0.3, 0); ctx.closePath(); ctx.fill();
                    ctx.fillStyle = String(root.peach);
                    ctx.beginPath(); ctx.moveTo(z, 0); ctx.lineTo(-z * 0.3, 0); ctx.lineTo(-z * 0.55, z * 0.42); ctx.closePath(); ctx.fill();
                    ctx.restore();
                }
            }
        }
    }
}
