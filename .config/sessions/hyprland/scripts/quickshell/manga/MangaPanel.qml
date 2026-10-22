import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "../"
import "."

Item {
    id: root
    focus: true

    Scaler { id: scaler; currentWidth: Screen.width }
    function s(val) { return scaler.s(val) * uiScale; }
    function fs(val) { return s(val) * cn("font_scale", 2.0) }

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
    function accentColor(n) {
        return n === "mauve" ? _theme.mauve : n === "blue" ? _theme.blue : n === "sapphire" ? _theme.sapphire
             : n === "green" ? _theme.green : n === "peach" ? _theme.peach : n === "yellow" ? _theme.yellow
             : n === "red" ? _theme.red : _theme.pink
    }
    readonly property color pink: accentColor(cs("accent", "pink"))
    readonly property color blue: _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color green: _theme.green
    readonly property color peach: _theme.peach
    readonly property color yellow: _theme.yellow
    readonly property color red: _theme.red

    readonly property string mono: "JetBrains Mono"
    readonly property string home: Quickshell.env("HOME")
    readonly property string script: home + "/.config/hypr/scripts/manga.py"
    function cb(k, d) { var v = cfg[k]; return v === undefined ? d : (v === true || v === "true") }
    function cn(k, d) { var v = Number(cfg[k]); return (cfg[k] === undefined || cfg[k] === "" || isNaN(v)) ? d : v }
    function cs(k, d) { var v = cfg[k]; return (v === undefined || v === null || v === "") ? d : String(v) }
    function rtlFor(kind) { return cb("rtl_" + kind, kind === "MANGA") }
    readonly property real uiScale: cn("ui_scale", 1.0)
    readonly property int animMs: ({ off: 0, fast: 220, normal: 440, slow: 800 })[cs("anim", "normal")]
    property var sizes: ({ dl: "-", cache: "-" })

    // ---------------- state
    property bool shown: false
    property string tab: "library"
    property bool firstLib: true
    property string src: "md"
    property string kind: "all"
    property string sort: "popular"
    property var sources: [{ id: "md", name: "MangaDex" }, { id: "local", name: "Local files" }]
    property var cfg: ({ saver: false })
    property var results: []
    property var lib: []
    property bool loading: false
    property string listErr: ""
    property var listCmd: []
    property bool listAgain: false
    property bool libAgain: false

    property var cur: null
    property bool detailOpen: false
    property var chapters: []
    property bool chLoading: false
    property bool chRev: true
    property bool chAgain: false
    property string chReq: ""
    property var chCmd: []
    property var getCmd: []
    property var infoCmd: []
    property var mstate: null
    property var readSet: ({})
    property var dlSet: ({})
    property var dlBusy: ({})
    property bool descExp: false
    property bool confirmRm: false
    property var shownCh: chRev ? chapters.slice().reverse() : chapters

    property bool readerOpen: false
    property int rIdx: -1
    property var rch: null
    property var rpages: []
    property int rStart: 0
    property bool rLoading: false
    property var pagesCmd: []
    property int pgPending: -1
    property string toastText: ""

    // ---------------- helpers
    function parse(txt, fallback) { try { return JSON.parse(txt) } catch (e) { return fallback } }
    function toast(msg) { toastText = msg; toastT.restart() }
    function modeFor(kind) {
        var m = cfg["mode_" + kind]
        if (m) return m
        return (kind === "MANHWA" || kind === "MANHUA") ? "scroll" : "paged"
    }
    function setCfg(k, v) {
        var c = {}
        for (var key in cfg) c[key] = cfg[key]
        c[k] = v
        cfg = c
        Quickshell.execDetached(["python3", script, "cfg", k, String(v)])
        if (k === "lib_sort") lib = sortLib(lib.slice())
        if (k === "lang" || k === "rating_suggestive" || k === "rating_erotica" || k === "local_root") reloadT.restart()
    }
    function toggleMode() {
        var k = cur ? cur.kind : ""
        setCfg("mode_" + k, modeFor(k) === "scroll" ? "paged" : "scroll")
    }
    function toggleSaver() {
        setCfg("saver", cfg.saver !== true)
        if (rch) openChapter(rIdx, readerIndex())
    }
    function readerIndex() { return reader.index }

    function setCfgLocal(k, v) {
        var c = {}
        for (var key in cfg) c[key] = cfg[key]
        c[k] = v
        cfg = c
    }
    function commitCfg(k) { Quickshell.execDetached(["python3", script, "cfg", k, String(cfg[k])]) }
    function sortLib(d) {
        var m = cs("lib_sort", "recent")
        if (m === "title") d.sort(function (a, b) { return a.title.localeCompare(b.title) })
        else if (m === "added") d.sort(function (a, b) { return (b.added || 0) - (a.added || 0) })
        return d
    }
    function applyDefaults() {
        src = cs("def_src", "md")
        kind = cs("def_kind", "all")
        sort = cs("def_sort", "popular")
        chRev = cb("ch_rev", true)
        if (cs("def_tab", "library") === "discover") tab = "discover"
    }
    function resetCfg() {
        Quickshell.execDetached(["python3", script, "cfg-reset"])
        cfg = ({ saver: false })
        lib = sortLib(lib.slice())
        applyDefaults()
        reloadT.restart()
    }
    function refreshSizes() { if (!sizeProc.running) sizeProc.running = true }
    function refreshDl() { if (!dlProc.running) dlProc.running = true }
    function wipe(what) {
        if (what === "downloads") {
            Quickshell.execDetached(["sh", "-c", "rm -rf \"$HOME/.local/share/qs-manga/downloads\"/* 2>/dev/null"])
            dlSet = ({})
        } else {
            Quickshell.execDetached(["sh", "-c", "rm -rf \"$HOME/.cache/qs-manga/arc\"/* \"$HOME/.cache/qs-manga/meta\"/* 2>/dev/null"])
        }
        sizeT.restart()
    }
    function applyLayout() {
        var w = cn("panel_w", 1200), h = cn("panel_h", 100), sd = cs("side", "left")
        var mgr = home + "/.config/hypr/scripts/qs_manager.sh"
        var lay = home + "/.config/hypr/scripts/manga_layout.py"
        toast("RESTARTING PANEL...")
        Quickshell.execDetached(["setsid", "sh", "-c",
            "if python3 '" + lay + "' " + w + " " + h + " " + sd + "; then pkill -f 'quickshell.*Main.qml'; sleep 1; bash '" + mgr + "' close; sleep 3; bash '" + mgr + "' open manga; fi"])
    }
    function loadLib() {
        if (libProc.running) { libAgain = true; return }
        libProc.running = true
    }
    function loadList() {
        if (listProc.running) { listAgain = true; return }
        var q = searchBox.text.trim()
        listErr = ""
        loading = true
        listCmd = q.length >= 2 ? ["python3", script, "search", src, kind, q]
                                : ["python3", script, "browse", src, kind, sort]
        listProc.running = true
    }
    function runChapters() {
        if (!cur) return
        if (chProc.running) { chAgain = true; return }
        chReq = cur.id
        chLoading = true
        chCmd = ["python3", script, "chapters", cur.id]
        chProc.running = true
    }
    function openManga(item) {
        cur = item
        detailOpen = true
        chapters = []
        mstate = null
        readSet = ({})
        descExp = false
        confirmRm = false
        runChapters()
        getCmd = ["python3", script, "get", item.id]
        if (!getProc.running) getProc.running = true
        if (!item.desc && !infoProc.running) {
            infoCmd = ["python3", script, "info", item.id]
            infoProc.running = true
        }
        if (!dlProc.running) dlProc.running = true
    }
    function continueIdx() {
        if (!mstate || !mstate.last) return -1
        for (var i = 0; i < chapters.length; i++)
            if (chapters[i].id === mstate.last.chapter_id) return i
        return -1
    }
    function startReading() {
        var i = continueIdx()
        if (i >= 0) openChapter(i, mstate.last.page || 0)
        else if (chapters.length > 0) openChapter(0, 0)
    }
    function autoAdd() {
        if (cur && mstate && !mstate.inlib && cb("auto_add", true)) {
            Quickshell.execDetached(["python3", script, "lib-add", cur.id, cur.title,
                                     cur.cover ? cur.cover : "", cur.kind ? cur.kind : ""])
            mstate = ({ id: cur.id, inlib: true, read: mstate.read ? mstate.read : [], last: null })
            libRefresh.restart()
        }
    }
    function openChapter(i, page) {
        if (i < 0 || i >= chapters.length) return
        if (pagesProc.running) return
        rIdx = i
        rch = chapters[i]
        rStart = page || 0
        rpages = []
        rLoading = true
        readerOpen = true
        autoAdd()
        pagesCmd = ["python3", script, "pages", rch.id].concat(cfg.saver === true ? ["saver"] : [])
        pagesProc.running = true
    }
    function stepChapter(d) {
        flushProgress()
        var ni = rIdx + d
        if (ni < 0 || ni >= chapters.length) return
        openChapter(ni, 0)
    }
    function closeReader() {
        flushProgress()
        readerOpen = false
        rpages = []
        libRefresh.restart()
        root.forceActiveFocus()
    }
    function savePage(idx) { pgPending = idx; progT.restart() }
    function doProgress() {
        if (!cur || !rch || pgPending < 0) return
        Quickshell.execDetached(["python3", script, "progress", cur.id, rch.id, rch.num, String(pgPending)])
        if (mstate)
            mstate = ({ id: mstate.id, inlib: true, read: mstate.read, last: { chapter_id: rch.id, num: rch.num, page: pgPending } })
    }
    function flushProgress() { if (progT.running) { progT.stop(); doProgress() } }
    function markRead() {
        if (!cur || !rch || readSet[rch.id]) return
        Quickshell.execDetached(["python3", script, "read", cur.id, rch.id])
        var rs = {}
        for (var k in readSet) rs[k] = readSet[k]
        rs[rch.id] = true
        readSet = rs
        libRefresh.restart()
    }
    function toggleLib() {
        if (!cur || !mstate) return
        if (mstate.inlib) {
            if (!confirmRm) { confirmRm = true; confirmT.restart(); return }
            confirmRm = false
            Quickshell.execDetached(["python3", script, "lib-rm", cur.id])
            mstate = ({ id: cur.id, inlib: false, read: [], last: null })
            readSet = ({})
        } else {
            Quickshell.execDetached(["python3", script, "lib-add", cur.id, cur.title,
                                     cur.cover ? cur.cover : "", cur.kind ? cur.kind : ""])
            mstate = ({ id: cur.id, inlib: true, read: mstate.read ? mstate.read : [], last: null })
        }
        libRefresh.restart()
    }
    function download(ch) {
        if (dlSet[ch.id] || dlBusy[ch.id]) return
        Quickshell.execDetached(["python3", script, "download", ch.id].concat(cfg.saver === true ? ["saver"] : []))
        var b = {}
        for (var k in dlBusy) b[k] = dlBusy[k]
        b[ch.id] = true
        dlBusy = b
        dlPoll.start()
    }
    function removeDownload(ch) {
        Quickshell.execDetached(["python3", script, "dl-rm", ch.id])
        var d = {}
        for (var k in dlSet) if (k !== ch.id) d[k] = true
        dlSet = d
    }

    Component.onCompleted: {
        showT.start()
        sourcesProc.running = true
        cfgProc.running = true
        libProc.running = true
    }
    onTabChanged: if (tab === "discover" && results.length === 0) loadList()
    Timer { id: showT; interval: 40; onTriggered: root.shown = true }
    Timer { id: toastT; interval: 3200; onTriggered: root.toastText = "" }
    Timer { id: libRefresh; interval: 600; onTriggered: root.loadLib() }
    Timer { id: progT; interval: 700; onTriggered: root.doProgress() }
    Timer { id: confirmT; interval: 3000; onTriggered: root.confirmRm = false }
    Timer { id: searchT; interval: 450; onTriggered: root.loadList() }
    Timer { id: reloadT; interval: 450; onTriggered: { root.results = []; root.loadList() } }
    Timer { id: sizeT; interval: 700; onTriggered: root.refreshSizes() }
    Process {
        id: sizeProc
        command: ["sh", "-c", "du -sh \"$HOME/.local/share/qs-manga/downloads\" \"$HOME/.cache/qs-manga\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var sz = { dl: "0", cache: "0" }
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var p = lines[i].split("\t")
                    if (p.length < 2) continue
                    if (p[1].indexOf("downloads") >= 0) sz.dl = p[0]
                    else sz.cache = p[0]
                }
                root.sizes = sz
            }
        }
    }
    Timer { id: dlPoll; interval: 1500; repeat: true; onTriggered: if (!dlProc.running) dlProc.running = true }

    onReaderOpenChanged: { if (readerOpen) reader.forceActiveFocus(); else root.forceActiveFocus() }

    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Escape) {
            if (root.detailOpen) root.detailOpen = false
            else Quickshell.execDetached(["bash", root.home + "/.config/hypr/scripts/qs_manager.sh", "close"])
        }
    }

    // ---------------- processes
    Process {
        id: sourcesProc
        command: ["python3", root.script, "sources"]
        stdout: StdioCollector {
            onStreamFinished: { var d = root.parse(text, null); if (Array.isArray(d) && d.length > 0) root.sources = d }
        }
    }
    Process {
        id: cfgProc
        command: ["python3", root.script, "cfg"]
        stdout: StdioCollector {
            onStreamFinished: { var d = root.parse(text, null); if (d && typeof d === "object" && !d.error) { root.cfg = d; root.applyDefaults() } }
        }
    }
    Process {
        id: libProc
        command: ["python3", root.script, "lib"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = root.parse(text, null)
                if (Array.isArray(d)) {
                    root.lib = root.sortLib(d)
                    if (root.firstLib) { root.firstLib = false; if (d.length === 0) root.tab = "discover" }
                }
                if (root.libAgain) { root.libAgain = false; root.loadLib() }
            }
        }
    }
    Process {
        id: listProc
        command: root.listCmd
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                var d = root.parse(text, null)
                if (Array.isArray(d)) { root.results = d; root.listErr = d.length === 0 ? "NOTHING FOUND" : "" }
                else root.listErr = (d && d.error) ? String(d.error).toUpperCase() : "REQUEST FAILED"
                if (root.listAgain) { root.listAgain = false; root.loadList() }
            }
        }
    }
    Process {
        id: chProc
        command: root.chCmd
        stdout: StdioCollector {
            onStreamFinished: {
                var d = root.parse(text, null)
                if (root.cur && root.chReq === root.cur.id) {
                    root.chLoading = false
                    if (d && d.cached && d.data) d = d.data
                    if (Array.isArray(d)) root.chapters = d
                    else { root.chapters = []; root.toast(d && d.error ? String(d.error) : "COULD NOT LOAD CHAPTERS") }
                }
                if (root.chAgain) { root.chAgain = false; root.runChapters() }
            }
        }
    }
    Process {
        id: getProc
        command: root.getCmd
        stdout: StdioCollector {
            onStreamFinished: {
                var d = root.parse(text, null)
                if (d && root.cur && d.id === root.cur.id) {
                    root.mstate = d
                    var rs = {}
                    var rd = d.read ? d.read : []
                    for (var i = 0; i < rd.length; i++) rs[rd[i]] = true
                    root.readSet = rs
                }
            }
        }
    }
    Process {
        id: infoProc
        command: root.infoCmd
        stdout: StdioCollector {
            onStreamFinished: {
                var d = root.parse(text, null)
                if (d && root.cur && d.id === root.cur.id && !d.error) {
                    var c = {}
                    for (var k in root.cur) c[k] = root.cur[k]
                    for (var k2 in d) if (k2 !== "cover" || !c.cover) c[k2] = d[k2]
                    root.cur = c
                }
            }
        }
    }
    Process {
        id: dlProc
        command: ["python3", root.script, "dl-list"]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = root.parse(text, null)
                if (!Array.isArray(d)) return
                var m = {}
                for (var i = 0; i < d.length; i++) m[d[i]] = true
                root.dlSet = m
                var b = {}, left = 0
                for (var k in root.dlBusy) if (!m[k]) { b[k] = true; left++ }
                root.dlBusy = b
                if (left === 0) dlPoll.stop()
            }
        }
    }
    Process {
        id: pagesProc
        command: root.pagesCmd
        stdout: StdioCollector {
            onStreamFinished: {
                var d = root.parse(text, null)
                root.rLoading = false
                if (Array.isArray(d) && d.length > 0) root.rpages = d
                else {
                    root.toast(d && d.error ? String(d.error) : "NO PAGES RETURNED")
                    root.closeReader()
                }
            }
        }
    }

    // ---------------- reusable card
    component MangaCard: Item {
        id: mc
        property var hub: null
        property var item: ({})
        property string badge: ""
        signal clicked()
        Rectangle {
            id: cv
            width: parent.width
            height: width * 1.5
            radius: mc.hub.s(mc.hub.cn("card_radius", 10))
            color: mc.hub.surface0
            clip: true
            border.width: 1
            border.color: cma.containsMouse ? mc.hub.pink : Qt.alpha(mc.hub.mauve, 0.3)
            Behavior on border.color { ColorAnimation { duration: 140 } }
            Image {
                anchors.fill: parent
                source: mc.item.cover ? mc.item.cover : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 256
            }
            Rectangle {
                visible: mc.hub.cb("show_badge", true)
                x: mc.hub.s(6); y: mc.hub.s(6)
                width: kt.width + mc.hub.s(10); height: Math.max(mc.hub.s(16), kt.height + mc.hub.s(4)); radius: mc.hub.s(4)
                color: Qt.alpha(mc.hub.crust, 0.85)
                Text { id: kt; anchors.centerIn: parent; text: mc.item.kind ? mc.item.kind : ""; color: mc.hub.pink
                       font.family: mc.hub.mono; font.pixelSize: mc.hub.fs(8); font.bold: true }
            }
            Rectangle {
                visible: mc.badge !== ""
                anchors { right: parent.right; rightMargin: mc.hub.s(6); top: parent.top; topMargin: mc.hub.s(6) }
                width: bt.width + mc.hub.s(10); height: Math.max(mc.hub.s(16), bt.height + mc.hub.s(4)); radius: mc.hub.s(4)
                color: mc.hub.pink
                Text { id: bt; anchors.centerIn: parent; text: mc.badge; color: mc.hub.crust
                       font.family: mc.hub.mono; font.pixelSize: mc.hub.fs(8); font.bold: true }
            }
        }
        Text {
            visible: mc.hub.cb("show_titles", true)
            anchors { left: parent.left; right: parent.right; top: cv.bottom; topMargin: mc.hub.s(6) }
            text: mc.item.title ? mc.item.title : ""
            color: mc.hub.text
            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
            font.family: mc.hub.mono; font.pixelSize: mc.hub.fs(10); font.bold: true
        }
        MouseArea { id: cma; anchors.fill: cv; hoverEnabled: true; onClicked: mc.clicked() }
    }

    // ---------------- frame
    Rectangle {
        id: frame
        width: parent.width
        height: parent.height
        x: root.shown ? 0 : (root.cs("side", "left") === "left" ? -1 : 1) * (root.width + root.s(40))
        opacity: root.shown ? 1 : 0
        Behavior on x { NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Math.min(300, root.animMs) } }
        radius: root.s(18)
        color: Qt.alpha(root.crust, root.cn("panel_opacity", 0.95))
        border.width: 1
        border.color: Qt.alpha(root.mauve, 0.45)
        clip: true

        Rectangle {
            id: beam
            visible: root.cb("beam", true)
            width: parent.width; height: root.s(120)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.alpha(root.mauve, 0.09) }
                GradientStop { position: 1.0; color: "transparent" }
            }
            NumberAnimation on y { from: -beam.height; to: frame.height; duration: 8000; loops: Animation.Infinite }
        }

        Canvas {
            anchors.fill: parent
            visible: root.cb("grid", false)
            opacity: 0.07
            onVisibleChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var c = getContext("2d")
                c.clearRect(0, 0, width, height)
                c.strokeStyle = root.pink
                c.lineWidth = 1
                var g = root.s(32)
                for (var x = 0; x < width; x += g) { c.beginPath(); c.moveTo(x, 0); c.lineTo(x, height); c.stroke() }
                for (var y = 0; y < height; y += g) { c.beginPath(); c.moveTo(0, y); c.lineTo(width, y); c.stroke() }
            }
        }
        Repeater {
            model: 4
            delegate: Item {
                required property int index
                visible: root.cb("corners", true)
                width: root.s(22); height: root.s(22)
                x: index % 2 === 0 ? root.s(8) : frame.width - width - root.s(8)
                y: index < 2 ? root.s(8) : frame.height - height - root.s(8)
                Rectangle { width: parent.width; height: 2; color: root.pink; opacity: 0.8; y: index < 2 ? 0 : parent.height - 2 }
                Rectangle { width: 2; height: parent.height; color: root.pink; opacity: 0.8; x: index % 2 === 0 ? 0 : parent.width - 2 }
            }
        }

        // header
        Item {
            id: header
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: root.s(18); rightMargin: root.s(18); topMargin: root.s(14) }
            height: root.s(70)
            Text {
                text: "MANGA//DECK"
                color: root.text
                font.family: root.mono; font.pixelSize: root.fs(18); font.bold: true; font.letterSpacing: root.s(2)
            }
            Text {
                y: root.s(46)
                text: root.lib.length + " IN LIBRARY"
                color: root.subtext0
                font.family: root.mono; font.pixelSize: root.fs(9); font.letterSpacing: root.s(2)
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: root.s(8)
                MBtn { hub: root; label: "LIBRARY"; accent: root.pink; solid: root.tab === "library"
                       onClicked: { root.tab = "library"; root.detailOpen = false } }
                MBtn { hub: root; label: "DISCOVER"; accent: root.blue; solid: root.tab === "discover"
                       onClicked: { root.tab = "discover"; root.detailOpen = false } }
                MBtn { hub: root; label: "SETTINGS"; accent: root.yellow; solid: root.tab === "settings"
                       onClicked: { root.tab = "settings"; root.detailOpen = false } }
                MBtn { hub: root; label: "X"; accent: root.red
                       onClicked: Quickshell.execDetached(["bash", root.home + "/.config/hypr/scripts/qs_manager.sh", "close"]) }
            }
            Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: -root.s(6); width: parent.width; height: 1; color: Qt.alpha(root.mauve, 0.3) }
        }

        Item {
            id: body
            anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom
                      leftMargin: root.s(18); rightMargin: root.s(18); topMargin: root.s(16); bottomMargin: root.s(16) }

            // ---------- library
            Item {
                anchors.fill: parent
                visible: root.tab === "library"
                GridView {
                    id: libGrid
                    anchors.fill: parent
                    clip: true
                    model: root.lib
                    cellWidth: Math.floor(width / root.cn("cols", 3))
                    cellHeight: cellWidth * 1.5 + root.s(52)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        required property var modelData
                        width: libGrid.cellWidth
                        height: libGrid.cellHeight
                        MangaCard {
                            anchors.fill: parent
                            anchors.margins: root.s(6)
                            hub: root
                            item: modelData
                            badge: modelData.last && root.cb("show_ch_badge", true) ? "CH " + modelData.last.num : ""
                            onClicked: root.openManga(modelData)
                        }
                    }
                }
                MScroll { hub: root; target: libGrid; anchors { right: libGrid.right; top: libGrid.top; bottom: libGrid.bottom } }
                Column {
                    anchors.centerIn: parent
                    visible: root.lib.length === 0
                    spacing: root.s(12)
                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: "LIBRARY EMPTY"; color: root.overlay0
                           font.family: root.mono; font.pixelSize: root.fs(13); font.bold: true; font.letterSpacing: root.s(3) }
                    MBtn { anchors.horizontalCenter: parent.horizontalCenter; hub: root; label: "BROWSE DISCOVER"; accent: root.blue
                           onClicked: root.tab = "discover" }
                }
            }

            // ---------- discover
            Item {
                anchors.fill: parent
                visible: root.tab === "discover"

                Column {
                    id: ctl
                    width: parent.width
                    spacing: root.s(8)
                    Rectangle {
                        width: parent.width; height: root.s(42); radius: root.s(10)
                        color: Qt.alpha(root.surface0, 0.6)
                        border.width: 1
                        border.color: searchBox.activeFocus ? root.pink : Qt.alpha(root.mauve, 0.4)
                        Text { id: prompt; x: root.s(14); anchors.verticalCenter: parent.verticalCenter; text: ">"; color: root.pink
                               font.family: root.mono; font.pixelSize: root.fs(15); font.bold: true }
                        TextInput {
                            id: searchBox
                            anchors { left: prompt.right; leftMargin: root.s(10); right: parent.right; rightMargin: root.s(14); verticalCenter: parent.verticalCenter }
                            color: root.text
                            selectionColor: Qt.alpha(root.pink, 0.4)
                            font.family: root.mono; font.pixelSize: root.fs(13)
                            clip: true
                            onTextChanged: searchT.restart()
                            onAccepted: root.loadList()
                            Keys.onEscapePressed: { text = ""; root.forceActiveFocus() }
                            Text { visible: searchBox.text === ""; text: "search titles..."; color: root.overlay0
                                   font.family: root.mono; font.pixelSize: root.fs(13) }
                        }
                    }
                    Flow {
                        width: parent.width
                        spacing: root.s(6)
                        Repeater {
                            model: root.sources
                            delegate: MBtn {
                                required property var modelData
                                hub: root; height: root.s(28)
                                label: modelData.name.toUpperCase()
                                accent: root.peach
                                solid: root.src === modelData.id
                                onClicked: { root.src = modelData.id; root.loadList() }
                            }
                        }
                        Repeater {
                            model: root.src === "md" ? ["all", "manga", "manhwa", "manhua"] : []
                            delegate: MBtn {
                                required property string modelData
                                hub: root; height: root.s(28)
                                label: modelData.toUpperCase()
                                accent: root.pink
                                solid: root.kind === modelData
                                onClicked: { root.kind = modelData; root.loadList() }
                            }
                        }
                        Repeater {
                            model: root.src === "md" ? ["popular", "latest", "rating"] : []
                            delegate: MBtn {
                                required property string modelData
                                hub: root; height: root.s(28)
                                label: modelData.toUpperCase()
                                accent: root.blue
                                solid: root.sort === modelData
                                onClicked: { root.sort = modelData; root.loadList() }
                            }
                        }
                    }
                }
                GridView {
                    id: resGrid
                    anchors { left: parent.left; right: parent.right; top: ctl.bottom; bottom: parent.bottom; topMargin: root.s(10) }
                    clip: true
                    model: root.results
                    cellWidth: Math.floor(width / root.cn("cols", 3))
                    cellHeight: cellWidth * 1.5 + root.s(52)
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Item {
                        required property var modelData
                        width: resGrid.cellWidth
                        height: resGrid.cellHeight
                        MangaCard {
                            anchors.fill: parent
                            anchors.margins: root.s(6)
                            hub: root
                            item: modelData
                            onClicked: root.openManga(modelData)
                        }
                    }
                }
                MScroll { hub: root; target: resGrid; anchors { right: resGrid.right; top: resGrid.top; bottom: resGrid.bottom } }
                Text {
                    anchors.centerIn: resGrid
                    visible: root.loading || root.listErr !== ""
                    text: root.loading ? "SCANNING..." : root.listErr
                    color: root.loading ? root.pink : root.overlay0
                    font.family: root.mono; font.pixelSize: root.fs(13); font.bold: true; font.letterSpacing: root.s(3)
                    SequentialAnimation on opacity {
                        running: root.loading; loops: Animation.Infinite
                        NumberAnimation { to: 0.3; duration: 600 }
                        NumberAnimation { to: 1.0; duration: 600 }
                    }
                }
            }

            SettingsPage {
                anchors.fill: parent
                hub: root
                visible: root.tab === "settings"
            }

            // ---------- detail
            Rectangle {
                id: detail
                anchors.fill: parent
                visible: root.detailOpen && root.cur !== null
                color: root.crust
                z: 5
                MBtn { id: backBtn; hub: root; label: "< BACK"; accent: root.blue; onClicked: root.detailOpen = false }
                MBtn {
                    anchors.right: parent.right
                    hub: root
                    label: root.mstate && root.mstate.inlib ? (root.confirmRm ? "CONFIRM REMOVE" : "IN LIBRARY") : "+ LIBRARY"
                    accent: root.mstate && root.mstate.inlib ? (root.confirmRm ? root.red : root.green) : root.pink
                    solid: root.confirmRm
                    onClicked: root.toggleLib()
                }
                Rectangle {
                    id: dCover
                    x: 0; y: root.s(46)
                    width: root.s(112); height: root.s(168)
                    radius: root.s(10); color: root.surface0; clip: true
                    border.width: 1; border.color: Qt.alpha(root.mauve, 0.4)
                    Image { anchors.fill: parent; source: root.cur && root.cur.cover ? root.cur.cover : ""
                            fillMode: Image.PreserveAspectCrop; asynchronous: true; cache: true; sourceSize.width: 256 }
                }
                Column {
                    x: dCover.width + root.s(16); y: root.s(46)
                    width: parent.width - x
                    spacing: root.s(6)
                    Text { width: parent.width; text: root.cur ? root.cur.title : ""; color: root.text
                           wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                           font.family: root.mono; font.pixelSize: root.fs(15); font.bold: true }
                    Text { width: parent.width
                           text: root.cur ? ((root.cur.kind ? root.cur.kind : "") + (root.cur.status ? "  /  " + root.cur.status.toUpperCase() : "") + (root.cur.year ? "  /  " + root.cur.year : "")) : ""
                           color: root.pink; font.family: root.mono; font.pixelSize: root.fs(10); font.bold: true }
                    Text { width: parent.width; visible: !!(root.cur && root.cur.authors && root.cur.authors.length)
                           text: root.cur && root.cur.authors ? root.cur.authors.join(", ") : ""; color: root.subtext1
                           elide: Text.ElideRight; font.family: root.mono; font.pixelSize: root.fs(10) }
                    Text { width: parent.width; visible: !!(root.cur && root.cur.tags && root.cur.tags.length)
                           text: root.cur && root.cur.tags ? root.cur.tags.join("  /  ") : ""; color: root.subtext0
                           wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                           font.family: root.mono; font.pixelSize: root.fs(9) }
                }
                Row {
                    id: dBtns
                    x: dCover.width + root.s(16); y: dCover.y + dCover.height - root.s(34)
                    spacing: root.s(8)
                    MBtn {
                        hub: root; accent: root.green; solid: true
                        enabled: root.chapters.length > 0
                        label: root.continueIdx() >= 0 ? "CONTINUE CH " + root.chapters[root.continueIdx()].num : "START READING"
                        onClicked: root.startReading()
                    }
                    MBtn {
                        hub: root; accent: root.yellow
                        visible: !!(root.cur && root.cur.official)
                        label: "OFFICIAL"
                        onClicked: Quickshell.execDetached(["xdg-open", root.cur.official])
                    }
                }
                Text {
                    id: dDesc
                    anchors { left: parent.left; right: parent.right; top: dCover.bottom; topMargin: root.s(12) }
                    text: root.cur && root.cur.desc ? root.cur.desc : ""
                    color: root.subtext1
                    wrapMode: Text.Wrap
                    maximumLineCount: root.descExp ? 40 : 3
                    elide: Text.ElideRight
                    font.family: root.mono; font.pixelSize: root.fs(10)
                    MouseArea { anchors.fill: parent; onClicked: root.descExp = !root.descExp }
                }
                Item {
                    id: chHead
                    anchors { left: parent.left; right: parent.right; top: dDesc.bottom; topMargin: root.s(12) }
                    height: root.s(30)
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: "CHAPTERS  " + root.chapters.length; color: root.pink
                           font.family: root.mono; font.pixelSize: root.fs(11); font.bold: true; font.letterSpacing: root.s(2) }
                    MBtn { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                           hub: root; height: root.s(26); label: root.chRev ? "NEWEST FIRST" : "OLDEST FIRST"; accent: root.mauve
                           onClicked: root.chRev = !root.chRev }
                }
                ListView {
                    id: chList
                    anchors { left: parent.left; right: parent.right; top: chHead.bottom; bottom: parent.bottom; topMargin: root.s(6) }
                    clip: true
                    spacing: root.s(5)
                    model: root.shownCh
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: cr
                        required property var modelData
                        readonly property int gi: root.chapters.indexOf(modelData)
                        readonly property bool isRead: !!root.readSet[modelData.id]
                        readonly property bool isCur: !!(root.mstate && root.mstate.last && root.mstate.last.chapter_id === modelData.id)
                        readonly property bool isDl: !!root.dlSet[modelData.id]
                        readonly property bool isBusy: !!root.dlBusy[modelData.id]
                        readonly property bool canDl: modelData.id.indexOf("md:") === 0
                        width: ListView.view.width
                        height: root.s(44)
                        radius: root.s(8)
                        color: cma2.containsMouse ? Qt.alpha(root.surface1, 0.5) : (isCur ? Qt.alpha(root.pink, 0.10) : Qt.alpha(root.surface0, 0.35))
                        border.width: isCur ? 1 : 0
                        border.color: root.pink
                        MouseArea { id: cma2; anchors.fill: parent; hoverEnabled: true; onClicked: root.openChapter(cr.gi, 0) }
                        Rectangle {
                            x: root.s(14); anchors.verticalCenter: parent.verticalCenter
                            width: root.s(9); height: width; radius: width / 2
                            color: cr.isRead ? root.green : "transparent"
                            border.width: 1; border.color: cr.isRead ? root.green : root.overlay0
                        }
                        Text {
                            x: root.s(36); anchors.verticalCenter: parent.verticalCenter
                            text: "CH " + (cr.modelData.num !== "" ? cr.modelData.num : "-")
                            color: cr.isRead ? root.overlay0 : root.text
                            font.family: root.mono; font.pixelSize: root.fs(11); font.bold: true
                        }
                        Text {
                            x: root.s(104); anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - root.s(104) - root.s(170)
                            elide: Text.ElideRight
                            text: cr.modelData.title
                            color: root.subtext1
                            font.family: root.mono; font.pixelSize: root.fs(10)
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: root.s(10); verticalCenter: parent.verticalCenter }
                            spacing: root.s(8)
                            Text { anchors.verticalCenter: parent.verticalCenter; text: cr.modelData.pages + " P"; color: root.overlay0
                                   font.family: root.mono; font.pixelSize: root.fs(9) }
                            MBtn {
                                visible: cr.canDl
                                hub: root; height: root.s(26)
                                label: cr.isBusy ? "..." : (cr.isDl ? "x OFFLINE" : "DL")
                                accent: cr.isDl ? root.green : root.sapphire
                                onClicked: cr.isDl ? root.removeDownload(cr.modelData) : root.download(cr.modelData)
                            }
                        }
                    }
                }
                MScroll { hub: root; target: chList; anchors { right: chList.right; top: chList.top; bottom: chList.bottom } }
                Text {
                    anchors.centerIn: chList
                    visible: root.chLoading || (root.chapters.length === 0 && !root.chLoading)
                    text: root.chLoading ? "LOADING CHAPTERS..." : "NO READABLE CHAPTERS HERE"
                    color: root.chLoading ? root.pink : root.overlay0
                    font.family: root.mono; font.pixelSize: root.fs(11); font.bold: true; font.letterSpacing: root.s(2)
                }
            }
        }

        Reader {
            id: reader
            anchors.fill: parent
            z: 20
            hub: root
            visible: root.readerOpen
            pages: root.rpages
            startIndex: root.rStart
            mode: root.modeFor(root.cur ? root.cur.kind : "")
            rtl: root.cur ? root.rtlFor(root.cur.kind) : false
            title: (root.cur ? root.cur.title : "") + "  //  CH " + (root.rch ? root.rch.num : "")
            loading: root.rLoading
            hasPrev: root.rIdx > 0
            hasNext: root.rIdx < root.chapters.length - 1
            saver: root.cfg.saver === true
            scrollStep: root.cn("scroll_step", 160)
            stripWidth: root.cn("strip_width", 100) / 100
            autoNext: root.cb("auto_next", true)
            bgMode: root.cs("reader_bg", "theme")
            onCloseRequested: root.closeReader()
            onPageChanged: function (i) { root.savePage(i) }
            onFinished: { if (root.cb("auto_read", true)) root.markRead() }
            onPrevChapter: root.stepChapter(-1)
            onNextChapter: root.stepChapter(1)
            onModeToggled: root.toggleMode()
            onSaverToggled: root.toggleSaver()
        }

        Rectangle {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: root.s(60) }
            z: 40
            visible: root.toastText !== ""
            width: tt.width + root.s(32); height: root.s(36); radius: root.s(10)
            color: Qt.alpha(root.base, 0.96)
            border.width: 1; border.color: root.peach
            Text { id: tt; anchors.centerIn: parent; text: root.toastText; color: root.peach
                   font.family: root.mono; font.pixelSize: root.fs(10); font.bold: true }
        }
    }
}
