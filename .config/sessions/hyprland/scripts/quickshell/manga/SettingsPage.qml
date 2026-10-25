import QtQuick
import Quickshell
import Quickshell.Io
import "."

Item {
    id: sp
    property var hub: null
    function s(v) { return hub.s(v) }
    function fs(v) { return hub.fs(v) }
    property string confirm: ""
    property string page: ""
    onPageChanged: { flick.contentY = 0; if (page === "sources") { extLimit = 60; refilter(); if (nlist.length === 0) loadExt(false) } }
    function back() { if (page === "") return false; page = ""; return true }
    Timer { id: confT; interval: 3000; onTriggered: sp.confirm = "" }
    onVisibleChanged: if (visible) { hub.refreshSizes(); hub.refreshDl() }
    function sumRead() { var n = 0; for (var i = 0; i < hub.lib.length; i++) n += hub.lib[i].read_count || 0; return n }
    function ask(id, fn) { if (confirm === id) { confirm = ""; fn() } else { confirm = id; confT.restart() } }

    // ---------------- extensions manager (Nyora sources)
    property var nlist: []
    property var extShown: []
    property int extTotal: 0
    property int extLimit: 60
    property bool extLoading: false
    property string extErr: ""
    property string extQuery: ""
    property string extLang: "mine"
    property string testing: ""
    property var health: ({})
    function enabledCount() { var n = 0; for (var i = 0; i < nlist.length; i++) if (nlist[i].on) n++; return n }
    function extStatus(id) {
        if (testing === id) return "  /  TESTING..."
        var h = health[id]
        if (!h) return ""
        return h.ok ? "  /  WORKING" : "  /  BROKEN: " + h.detail
    }
    function refilter() {
        var q = extQuery.toLowerCase()
        var mine = hub.cs("lang", "en").toLowerCase().split("-")[0]
        var nsfwOk = hub.cb("rating_erotica", false)
        var on = [], off = []
        for (var i = 0; i < nlist.length; i++) {
            var e = nlist[i]
            if (!e.on) {
                if (e.nsfw && !nsfwOk) continue
                if (extLang === "mine" && e.lang !== "all" && e.lang.toLowerCase().split("-")[0] !== mine) continue
            }
            if (q !== "" && e.name.toLowerCase().indexOf(q) < 0) continue
            if (e.on) on.push(e); else off.push(e)
        }
        var all = on.concat(off)
        extTotal = all.length
        extShown = all.slice(0, extLimit)
    }
    function loadExt(refresh) {
        if (extLoading) return
        extLoading = true; extErr = ""
        listProc.command = ["python3", hub.script, "nyora-list"].concat(refresh ? ["refresh"] : [])
        listProc.running = true
    }
    function gotList(t) {
        extLoading = false
        var d = hub.parse(t, null)
        if (!d || d.error || !Array.isArray(d.sources)) { extErr = (d && d.error) ? d.error : "no response"; return }
        nlist = d.sources; health = d.health || {}
        refilter()
    }
    function toggleExt(id) {
        togProc.command = ["python3", hub.script, "nyora-toggle", id]
        togProc.running = true
    }
    function gotToggle(t) {
        var d = hub.parse(t, null)
        if (!d || d.error) { extErr = (d && d.error) ? d.error : "toggle failed"; return }
        for (var i = 0; i < nlist.length; i++) if (nlist[i].id === d.id) nlist[i].on = d.on
        nlist = nlist.slice()
        refilter()
        hub.refreshSources()
    }
    function runTest(id) {
        if (testing !== "") return
        testing = id
        testProc.command = ["python3", hub.script, "nyora-test", id]
        testProc.running = true
    }
    function gotTest(t) {
        var d = hub.parse(t, null)
        var h = Object.assign({}, health)
        h[testing] = { ok: !!(d && d.ok), detail: d ? (d.detail || d.error || "") : "no response" }
        health = h
        testing = ""
    }
    Process { id: listProc; stdout: StdioCollector { onStreamFinished: sp.gotList(text) } }
    Process { id: togProc; stdout: StdioCollector { onStreamFinished: sp.gotToggle(text) } }
    Process { id: testProc; stdout: StdioCollector { onStreamFinished: sp.gotTest(text) } }
    Connections {
        target: flick
        function onContentYChanged() {
            if (sp.page === "sources" && sp.extShown.length < sp.extTotal
                && flick.contentY + flick.height > flick.contentHeight - sp.s(260)) {
                sp.extLimit += 60
                sp.refilter()
            }
        }
    }

    // ---------------- downloads monitor
    property var dlItems: []
    property var dlSummary: ({})
    readonly property var dlActive: dlItems.filter(function (e) { return e.status === "running" || e.status === "queued" })
    readonly property var dlFailed: dlItems.filter(function (e) { return e.status === "error" })
    function dlName(e) {
        var n = e.manga ? e.manga : "unknown title"
        if (e.num !== undefined && e.num !== null && e.num !== "") n += "  /  CH " + e.num
        return n
    }
    function loadDl() {
        if (dlInfoProc.running) return
        dlInfoProc.command = ["python3", hub.script, "dl-info"]
        dlInfoProc.running = true
    }
    function gotDl(t) {
        var d = hub.parse(t, null)
        if (!d || !Array.isArray(d.items)) return
        dlItems = d.items
        dlSummary = d.summary || ({})
    }
    function dlRetry(ids) { Quickshell.execDetached(["python3", hub.script, "dl-retry"].concat(ids)); dlRefreshT.restart() }
    function dlRemove(cid) { Quickshell.execDetached(["python3", hub.script, "dl-rm", cid]); dlRefreshT.restart(); hub.refreshDl() }
    function dlClearFailed() { Quickshell.execDetached(["python3", hub.script, "dl-clear-failed"]); dlRefreshT.restart(); hub.refreshDl() }
    Process { id: dlInfoProc; stdout: StdioCollector { onStreamFinished: sp.gotDl(text) } }
    Timer { id: dlRefreshT; interval: 700; onTriggered: sp.loadDl() }
    Timer { interval: 1200; repeat: true; running: sp.visible && sp.page === "downloads"; triggeredOnStart: true; onTriggered: sp.loadDl() }

    component Sec: Item {
        id: sc
        property var hub: null
        property string title: ""
        width: parent ? parent.width : 0
        height: hub.s(44)
        Text { y: sc.hub.s(18); text: sc.title; color: sc.hub.pink
               font.family: sc.hub.mono; font.pixelSize: sc.hub.fs(10); font.bold: true; font.letterSpacing: sc.hub.s(3) }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.alpha(sc.hub.pink, 0.3) }
    }

    component SRow: Item {
        id: sr
        property var hub: null
        property string label: ""
        property string hint: ""
        default property alias content: slot.data
        width: parent ? parent.width : 0
        height: hint !== "" ? hub.s(54) : hub.s(42)
        Text {
            id: lb
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: sr.hint !== "" ? -sr.hub.s(7) : 0
            width: parent.width * 0.42
            elide: Text.ElideRight
            text: sr.label; color: sr.hub.text
            font.family: sr.hub.mono; font.pixelSize: sr.hub.fs(11); font.bold: true
        }
        Text {
            visible: sr.hint !== ""
            y: lb.y + lb.height + sr.hub.s(2)
            width: parent.width * 0.42
            elide: Text.ElideRight
            text: sr.hint; color: sr.hub.subtext0
            font.family: sr.hub.mono; font.pixelSize: sr.hub.fs(8)
        }
        Item {
            id: slot
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: childrenRect.width; height: childrenRect.height
        }
    }

    component Tgl: Rectangle {
        id: tg
        property var hub: null
        property bool on: false
        signal flipped()
        width: hub.s(44); height: hub.s(24); radius: height / 2
        color: tg.on ? hub.pink : hub.surface1
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            width: tg.height - tg.hub.s(6); height: width; radius: width / 2
            y: tg.hub.s(3)
            x: tg.on ? tg.width - width - tg.hub.s(3) : tg.hub.s(3)
            color: tg.on ? tg.hub.crust : tg.hub.subtext0
            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; onClicked: tg.flipped() }
    }

    component Seg: Row {
        id: sg
        property var hub: null
        property var opts: []
        property string cur: ""
        signal picked(string v)
        spacing: hub.s(4)
        Repeater {
            model: sg.opts
            delegate: Rectangle {
                id: sc2
                required property var modelData
                readonly property bool on: sg.cur === modelData.v
                width: st.width + sg.hub.s(16); height: Math.max(sg.hub.s(26), st.height + sg.hub.s(10)); radius: sg.hub.s(7)
                color: on ? sg.hub.pink : (sma.containsMouse ? Qt.alpha(sg.hub.pink, 0.2) : "transparent")
                border.width: 1
                border.color: on ? sg.hub.pink : Qt.alpha(sg.hub.pink, 0.4)
                Behavior on color { ColorAnimation { duration: 120 } }
                Text { id: st; anchors.centerIn: parent; text: sc2.modelData.l
                       color: sc2.on ? sg.hub.crust : sg.hub.pink
                       font.family: sg.hub.mono; font.pixelSize: sg.hub.fs(9); font.bold: true }
                MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; onClicked: sg.picked(sc2.modelData.v) }
            }
        }
    }

    component Sld: Item {
        id: sl
        property var hub: null
        property real from: 0
        property real to: 100
        property real value: 0
        property real step: 1
        property int decimals: 0
        property string suffix: ""
        signal moved(real v)
        signal released()
        width: hub.s(230); height: hub.s(26)
        readonly property real frac: Math.max(0, Math.min(1, (value - from) / (to - from)))
        Rectangle {
            id: track
            width: parent.width - vl.width - sl.hub.s(14); height: sl.hub.s(6); radius: 3
            anchors.verticalCenter: parent.verticalCenter
            color: sl.hub.surface1
            Rectangle { width: parent.width * sl.frac; height: parent.height; radius: 3; color: sl.hub.pink }
            Rectangle {
                x: parent.width * sl.frac - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: sl.hub.s(14); height: width; radius: width / 2
                color: sl.hub.pink; border.width: 2; border.color: sl.hub.crust
            }
            MouseArea {
                id: sma2
                anchors.fill: parent
                anchors.margins: -sl.hub.s(8)
                function calc(m) {
                    var px = mapToItem(track, m.x, m.y).x
                    var f = Math.max(0, Math.min(1, px / track.width))
                    var v = sl.from + f * (sl.to - sl.from)
                    v = Math.round(v / sl.step) * sl.step
                    sl.moved(Math.max(sl.from, Math.min(sl.to, v)))
                }
                onPressed: function (m) { calc(m) }
                onPositionChanged: function (m) { if (pressed) calc(m) }
                onReleased: sl.released()
            }
        }
        Text {
            id: vl
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: sl.hub.s(46); horizontalAlignment: Text.AlignRight
            text: sl.value.toFixed(sl.decimals) + sl.suffix
            color: sl.hub.text
            font.family: sl.hub.mono; font.pixelSize: sl.hub.fs(10); font.bold: true
        }
    }

    component Swatches: Row {
        id: sw
        property var hub: null
        spacing: hub.s(7)
        Repeater {
            model: ["pink", "mauve", "blue", "sapphire", "green", "peach", "yellow", "red"]
            delegate: Rectangle {
                id: dot
                required property string modelData
                readonly property bool on: sw.hub.cs("accent", "pink") === modelData
                width: sw.hub.s(22); height: width; radius: width / 2
                color: sw.hub.accentColor(modelData)
                border.width: on ? 2 : 0
                border.color: sw.hub.text
                scale: dma.containsMouse ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                MouseArea { id: dma; anchors.fill: parent; hoverEnabled: true; onClicked: sw.hub.setCfg("accent", dot.modelData) }
            }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.rightMargin: sp.s(22)
        contentWidth: width
        contentHeight: col.height + sp.s(30)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            width: flick.width
            spacing: sp.s(2)

            Row {
                visible: sp.page === ""
                spacing: sp.s(8)
                Repeater {
                    model: [{ l: "LIBRARY", v: sp.hub.lib.length },
                            { l: "CHAPTERS READ", v: sp.sumRead() },
                            { l: "OFFLINE", v: Object.keys(sp.hub.dlSet).length }]
                    delegate: Rectangle {
                        required property var modelData
                        width: (col.width - sp.s(16)) / 3; height: sp.s(90); radius: sp.s(10)
                        color: Qt.alpha(sp.hub.pink, 0.08)
                        border.width: 1; border.color: Qt.alpha(sp.hub.pink, 0.45)
                        Column {
                            anchors.centerIn: parent
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.v; color: sp.hub.pink
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(20); font.bold: true }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.l; color: sp.hub.subtext0
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(8); font.letterSpacing: sp.s(1) }
                        }
                    }
                }
            }

            Column {
                width: col.width
                spacing: sp.s(8)
                visible: sp.page === ""
                Item { width: 1; height: sp.s(6) }
                Repeater {
                    model: [{ k: "reading", l: "READING", d: "modes, direction, strip width, scrolling, auto-next" },
                            { k: "library", l: "LIBRARY", d: "sort, grid columns, badges, chapter order" },
                            { k: "sources", l: "SOURCES", d: "defaults, language, content filters, local folder" },
                            { k: "appearance", l: "APPEARANCE", d: "colour, text size, panel layout, effects" },
                            { k: "downloads", l: "DOWNLOADS", d: "queue, progress, errors" },
                            { k: "data", l: "DATA", d: "downloads, cache, reset" }]
                    delegate: Rectangle {
                        id: cat
                        required property var modelData
                        width: col.width; height: sp.s(66); radius: sp.s(10)
                        color: cma.containsMouse ? Qt.alpha(sp.hub.pink, 0.16) : Qt.alpha(sp.hub.pink, 0.06)
                        border.width: 1
                        border.color: Qt.alpha(sp.hub.pink, cma.containsMouse ? 0.7 : 0.35)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Column {
                            anchors { left: parent.left; leftMargin: sp.s(18); verticalCenter: parent.verticalCenter }
                            spacing: sp.s(4)
                            Text { text: cat.modelData.l; color: sp.hub.text
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(12); font.bold: true; font.letterSpacing: sp.s(2) }
                            Text { text: cat.modelData.d; color: sp.hub.subtext0
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(8) }
                        }
                        Text { anchors { right: parent.right; rightMargin: sp.s(18); verticalCenter: parent.verticalCenter }
                               text: ">"; color: sp.hub.pink
                               font.family: sp.hub.mono; font.pixelSize: sp.fs(16); font.bold: true }
                        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: sp.page = cat.modelData.k }
                    }
                }
            }

            Column {
                width: col.width
                spacing: sp.s(2)
                visible: sp.page === "reading"
                MBtn { hub: sp.hub; label: "< BACK"; accent: sp.hub.yellow; onClicked: sp.page = "" }
                Sec { hub: sp.hub; title: "READING" }
                SRow { hub: sp.hub; label: "Mode: manga"
                    Seg { hub: sp.hub; opts: [{ v: "scroll", l: "SCROLL" }, { v: "paged", l: "PAGED" }]
                          cur: sp.hub.modeFor("MANGA"); onPicked: function (v) { sp.hub.setCfg("mode_MANGA", v) } } }
                SRow { hub: sp.hub; label: "Mode: manhwa"
                    Seg { hub: sp.hub; opts: [{ v: "scroll", l: "SCROLL" }, { v: "paged", l: "PAGED" }]
                          cur: sp.hub.modeFor("MANHWA"); onPicked: function (v) { sp.hub.setCfg("mode_MANHWA", v) } } }
                SRow { hub: sp.hub; label: "Mode: manhua"
                    Seg { hub: sp.hub; opts: [{ v: "scroll", l: "SCROLL" }, { v: "paged", l: "PAGED" }]
                          cur: sp.hub.modeFor("MANHUA"); onPicked: function (v) { sp.hub.setCfg("mode_MANHUA", v) } } }
                SRow { hub: sp.hub; label: "Paged direction: manga"; hint: "RTL = tap right side goes back"
                    Seg { hub: sp.hub; opts: [{ v: "rtl", l: "RIGHT TO LEFT" }, { v: "ltr", l: "LEFT TO RIGHT" }]
                          cur: sp.hub.rtlFor("MANGA") ? "rtl" : "ltr"
                          onPicked: function (v) { sp.hub.setCfg("rtl_MANGA", v === "rtl") } } }
                SRow { hub: sp.hub; label: "Paged direction: others"
                    Seg { hub: sp.hub; opts: [{ v: "rtl", l: "RIGHT TO LEFT" }, { v: "ltr", l: "LEFT TO RIGHT" }]
                          cur: sp.hub.rtlFor("MANHWA") ? "rtl" : "ltr"
                          onPicked: function (v) { sp.hub.setCfg("rtl_MANHWA", v === "rtl"); sp.hub.setCfg("rtl_MANHUA", v === "rtl") } } }
                SRow { hub: sp.hub; label: "Strip width"; hint: "scroll mode page width"
                    Sld { hub: sp.hub; from: 50; to: 100; step: 5; suffix: "%"; value: sp.hub.cn("strip_width", 100)
                          onMoved: function (v) { sp.hub.setCfgLocal("strip_width", v) }; onReleased: sp.hub.commitCfg("strip_width") } }
                SRow { hub: sp.hub; label: "Scroll step"; hint: "arrow keys, pixels"
                    Sld { hub: sp.hub; from: 60; to: 400; step: 20; suffix: "px"; value: sp.hub.cn("scroll_step", 160)
                          onMoved: function (v) { sp.hub.setCfgLocal("scroll_step", v) }; onReleased: sp.hub.commitCfg("scroll_step") } }
                SRow { hub: sp.hub; label: "Data saver"; hint: "smaller images, less bandwidth"
                    Tgl { hub: sp.hub; on: sp.hub.cb("saver", false); onFlipped: sp.hub.setCfg("saver", !on) } }
                SRow { hub: sp.hub; label: "Auto-open next chapter"
                    Tgl { hub: sp.hub; on: sp.hub.cb("auto_next", true); onFlipped: sp.hub.setCfg("auto_next", !on) } }
                SRow { hub: sp.hub; label: "Mark read at chapter end"
                    Tgl { hub: sp.hub; on: sp.hub.cb("auto_read", true); onFlipped: sp.hub.setCfg("auto_read", !on) } }
                SRow { hub: sp.hub; label: "Reader background"
                    Seg { hub: sp.hub; opts: [{ v: "theme", l: "THEME" }, { v: "black", l: "BLACK" }, { v: "base", l: "LIGHTER" }]
                          cur: sp.hub.cs("reader_bg", "theme"); onPicked: function (v) { sp.hub.setCfg("reader_bg", v) } } }

            }

            Column {
                width: col.width
                spacing: sp.s(2)
                visible: sp.page === "library"
                MBtn { hub: sp.hub; label: "< BACK"; accent: sp.hub.yellow; onClicked: sp.page = "" }
                Sec { hub: sp.hub; title: "LIBRARY" }
                SRow { hub: sp.hub; label: "Add to library when reading"
                    Tgl { hub: sp.hub; on: sp.hub.cb("auto_add", true); onFlipped: sp.hub.setCfg("auto_add", !on) } }
                SRow { hub: sp.hub; label: "Sort"
                    Seg { hub: sp.hub; opts: [{ v: "recent", l: "RECENT" }, { v: "title", l: "TITLE" }, { v: "added", l: "ADDED" }]
                          cur: sp.hub.cs("lib_sort", "recent"); onPicked: function (v) { sp.hub.setCfg("lib_sort", v) } } }
                SRow { hub: sp.hub; label: "Grid columns"
                    Seg { hub: sp.hub; opts: [{ v: "2", l: "2" }, { v: "3", l: "3" }, { v: "4", l: "4" }]
                          cur: String(sp.hub.cn("cols", 3)); onPicked: function (v) { sp.hub.setCfg("cols", Number(v)) } } }
                SRow { hub: sp.hub; label: "Chapter order"
                    Seg { hub: sp.hub; opts: [{ v: "newest", l: "NEWEST FIRST" }, { v: "oldest", l: "OLDEST FIRST" }]
                          cur: sp.hub.cb("ch_rev", true) ? "newest" : "oldest"
                          onPicked: function (v) { sp.hub.setCfg("ch_rev", v === "newest"); sp.hub.chRev = (v === "newest") } } }
                SRow { hub: sp.hub; label: "Show kind badge"
                    Tgl { hub: sp.hub; on: sp.hub.cb("show_badge", true); onFlipped: sp.hub.setCfg("show_badge", !on) } }
                SRow { hub: sp.hub; label: "Show chapter badge"
                    Tgl { hub: sp.hub; on: sp.hub.cb("show_ch_badge", true); onFlipped: sp.hub.setCfg("show_ch_badge", !on) } }
                SRow { hub: sp.hub; label: "Show titles"
                    Tgl { hub: sp.hub; on: sp.hub.cb("show_titles", true); onFlipped: sp.hub.setCfg("show_titles", !on) } }

            }

            Column {
                width: col.width
                spacing: sp.s(2)
                visible: sp.page === "sources"
                MBtn { hub: sp.hub; label: "< BACK"; accent: sp.hub.yellow; onClicked: sp.page = "" }
                Sec { hub: sp.hub; title: "SOURCES" }
                SRow { hub: sp.hub; label: "Default source"
                    Seg { hub: sp.hub
                          opts: { var o = []; for (var i = 0; i < sp.hub.sources.length; i++) o.push({ v: sp.hub.sources[i].id, l: sp.hub.sources[i].name.toUpperCase() }); return o }
                          cur: sp.hub.cs("def_src", "md"); onPicked: function (v) { sp.hub.setCfg("def_src", v) } } }
                SRow { hub: sp.hub; label: "Default kind"
                    Seg { hub: sp.hub; opts: [{ v: "all", l: "ALL" }, { v: "manga", l: "MANGA" }, { v: "manhwa", l: "MANHWA" }, { v: "manhua", l: "MANHUA" }]
                          cur: sp.hub.cs("def_kind", "all"); onPicked: function (v) { sp.hub.setCfg("def_kind", v) } } }
                SRow { hub: sp.hub; label: "Default sort"
                    Seg { hub: sp.hub; opts: [{ v: "popular", l: "POPULAR" }, { v: "latest", l: "LATEST" }, { v: "rating", l: "RATING" }]
                          cur: sp.hub.cs("def_sort", "popular"); onPicked: function (v) { sp.hub.setCfg("def_sort", v) } } }
                SRow { hub: sp.hub; label: "Start on"
                    Seg { hub: sp.hub; opts: [{ v: "library", l: "LIBRARY" }, { v: "discover", l: "DISCOVER" }]
                          cur: sp.hub.cs("def_tab", "library"); onPicked: function (v) { sp.hub.setCfg("def_tab", v) } } }
                SRow { hub: sp.hub; label: "Chapter language"
                    Seg { hub: sp.hub
                          opts: [{ v: "en", l: "EN" }, { v: "es", l: "ES" }, { v: "pt-br", l: "PT-BR" }, { v: "fr", l: "FR" }, { v: "id", l: "ID" }, { v: "ru", l: "RU" }]
                          cur: sp.hub.cs("lang", "en"); onPicked: function (v) { sp.hub.setCfg("lang", v) } } }
                SRow { hub: sp.hub; visible: false; label: "Include suggestive"
                    Tgl { hub: sp.hub; on: sp.hub.cb("rating_suggestive", true); onFlipped: sp.hub.setCfg("rating_suggestive", !on) } }
                SRow { hub: sp.hub; label: "Include erotica"
                    Tgl { hub: sp.hub; on: sp.hub.cb("rating_erotica", false); onFlipped: sp.hub.setCfg("rating_erotica", !on) } }
                SRow { hub: sp.hub; label: "Local folder"; hint: "series folders, .cbz, .zip"
                    Row {
                        spacing: sp.s(6)
                        Rectangle {
                            width: sp.s(200); height: Math.max(sp.s(30), lr.contentHeight + sp.s(16)); radius: sp.s(8)
                            color: Qt.alpha(sp.hub.surface0, 0.6)
                            border.width: 1; border.color: lr.activeFocus ? sp.hub.pink : Qt.alpha(sp.hub.pink, 0.4)
                            TextInput {
                                id: lr
                                anchors.fill: parent; anchors.margins: sp.s(8)
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                color: sp.hub.text
                                selectionColor: Qt.alpha(sp.hub.pink, 0.4)
                                font.family: sp.hub.mono; font.pixelSize: sp.fs(10)
                                text: sp.hub.cs("local_root", "~/Manga")
                                onAccepted: sp.hub.setCfg("local_root", text.trim())
                                Keys.onEscapePressed: sp.hub.forceActiveFocus()
                            }
                        }
                        MBtn { hub: sp.hub; label: "APPLY"; accent: sp.hub.green; onClicked: sp.hub.setCfg("local_root", lr.text.trim()) }
                    }
                }
                Sec { hub: sp.hub; title: "EXTENSIONS" }
                SRow { hub: sp.hub; label: "Source list"
                    hint: sp.extErr !== "" ? sp.extErr : (sp.extLoading ? "loading..." : sp.nlist.length + " available, " + sp.enabledCount() + " enabled")
                    MBtn { hub: sp.hub; label: "REFRESH"; accent: sp.hub.blue; onClicked: sp.loadExt(true) } }
                SRow { hub: sp.hub; label: "Language"; hint: "your MangaDex language plus multi-language sources"
                    Seg { hub: sp.hub; opts: [{ v: "mine", l: "MINE" }, { v: "any", l: "ANY" }]
                          cur: sp.extLang; onPicked: function (v) { sp.extLang = v; sp.extLimit = 60; sp.refilter() } } }
                SRow { hub: sp.hub; label: "Search"
                    Rectangle {
                        width: sp.s(200); height: Math.max(sp.s(30), exq.contentHeight + sp.s(16)); radius: sp.s(8)
                        color: Qt.alpha(sp.hub.surface0, 0.6)
                        border.width: 1; border.color: exq.activeFocus ? sp.hub.pink : Qt.alpha(sp.hub.pink, 0.4)
                        TextInput {
                            id: exq
                            anchors.fill: parent; anchors.margins: sp.s(8)
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            color: sp.hub.text
                            selectionColor: Qt.alpha(sp.hub.pink, 0.4)
                            font.family: sp.hub.mono; font.pixelSize: sp.fs(10)
                            onTextChanged: { sp.extQuery = text; sp.extLimit = 60; sp.refilter() }
                            Keys.onEscapePressed: sp.hub.forceActiveFocus()
                            Text { visible: exq.text === ""; text: "name..."; color: sp.hub.overlay0
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(10) }
                        }
                    } }
                Repeater {
                    model: sp.extShown
                    delegate: SRow {
                        required property var modelData
                        hub: sp.hub
                        label: modelData.name
                        hint: modelData.lang.toUpperCase() + (modelData.nsfw ? "  /  NSFW" : "") + sp.extStatus(modelData.id)
                        Row {
                            spacing: sp.s(8)
                            MBtn { hub: sp.hub; label: sp.testing === modelData.id ? "..." : "TEST"; accent: sp.hub.blue
                                   enabled: sp.testing === ""; onClicked: sp.runTest(modelData.id) }
                            Tgl { hub: sp.hub; on: modelData.on; onFlipped: sp.toggleExt(modelData.id) }
                        }
                    }
                }
                Text { visible: sp.extTotal > sp.extShown.length
                       text: "showing " + sp.extShown.length + " of " + sp.extTotal + ", scroll for more"
                       color: sp.hub.overlay0; font.family: sp.hub.mono; font.pixelSize: sp.fs(8) }

            }

            Column {
                width: col.width
                spacing: sp.s(2)
                visible: sp.page === "appearance"
                MBtn { hub: sp.hub; label: "< BACK"; accent: sp.hub.yellow; onClicked: sp.page = "" }
                Sec { hub: sp.hub; title: "APPEARANCE" }
                SRow { hub: sp.hub; label: "Accent colour"
                    Swatches { hub: sp.hub } }
                SRow { hub: sp.hub; label: "Text size"; hint: "applies instantly"
                    Seg { hub: sp.hub
                          opts: [{ v: "1", l: "1X" }, { v: "1.25", l: "1.25X" }, { v: "1.5", l: "1.5X" }, { v: "1.75", l: "1.75X" }, { v: "2", l: "2X" }, { v: "2.5", l: "2.5X" }, { v: "3", l: "3X" }, { v: "3.5", l: "3.5X" }]
                          cur: String(sp.hub.cn("font_scale", 2)); onPicked: function (v) { sp.hub.setCfg("font_scale", Number(v)) } } }
                SRow { hub: sp.hub; label: "Panel width"; hint: "needs APPLY below"
                    Sld { hub: sp.hub; from: 600; to: 1700; step: 50; suffix: "px"; value: sp.hub.cn("panel_w", 1200)
                          onMoved: function (v) { sp.hub.setCfgLocal("panel_w", v) }; onReleased: sp.hub.commitCfg("panel_w") } }
                SRow { hub: sp.hub; label: "Panel height"; hint: "needs APPLY below"
                    Seg { hub: sp.hub; opts: [{ v: "100", l: "FULL" }, { v: "90", l: "90%" }, { v: "80", l: "80%" }, { v: "70", l: "70%" }]
                          cur: String(sp.hub.cn("panel_h", 100)); onPicked: function (v) { sp.hub.setCfg("panel_h", Number(v)) } } }
                SRow { hub: sp.hub; label: "Panel side"; hint: "needs APPLY below"
                    Seg { hub: sp.hub; opts: [{ v: "left", l: "LEFT" }, { v: "right", l: "RIGHT" }]
                          cur: sp.hub.cs("side", "left"); onPicked: function (v) { sp.hub.setCfg("side", v) } } }
                SRow { hub: sp.hub; label: "Apply panel layout"; hint: "restarts the panel, about 5 seconds"
                    MBtn { hub: sp.hub; label: "APPLY & RESTART"; accent: sp.hub.green; solid: true; onClicked: sp.hub.applyLayout() } }
                SRow { hub: sp.hub; label: "Panel opacity"
                    Sld { hub: sp.hub; from: 0.6; to: 1.0; step: 0.02; decimals: 2; value: sp.hub.cn("panel_opacity", 0.95)
                          onMoved: function (v) { sp.hub.setCfgLocal("panel_opacity", v) }; onReleased: sp.hub.commitCfg("panel_opacity") } }
                SRow { hub: sp.hub; label: "UI scale"
                    Seg { hub: sp.hub; opts: [{ v: "0.9", l: "90%" }, { v: "1", l: "100%" }, { v: "1.1", l: "110%" }, { v: "1.2", l: "120%" }]
                          cur: String(sp.hub.cn("ui_scale", 1)); onPicked: function (v) { sp.hub.setCfg("ui_scale", Number(v)) } } }
                SRow { hub: sp.hub; label: "Card corner radius"
                    Sld { hub: sp.hub; from: 0; to: 20; step: 1; value: sp.hub.cn("card_radius", 10)
                          onMoved: function (v) { sp.hub.setCfgLocal("card_radius", v) }; onReleased: sp.hub.commitCfg("card_radius") } }
                SRow { hub: sp.hub; label: "Animation speed"
                    Seg { hub: sp.hub; opts: [{ v: "off", l: "OFF" }, { v: "fast", l: "FAST" }, { v: "normal", l: "NORMAL" }, { v: "slow", l: "SLOW" }]
                          cur: sp.hub.cs("anim", "normal"); onPicked: function (v) { sp.hub.setCfg("anim", v) } } }
                SRow { hub: sp.hub; label: "Scan beam"
                    Tgl { hub: sp.hub; on: sp.hub.cb("beam", true); onFlipped: sp.hub.setCfg("beam", !on) } }
                SRow { hub: sp.hub; label: "Corner brackets"
                    Tgl { hub: sp.hub; on: sp.hub.cb("corners", true); onFlipped: sp.hub.setCfg("corners", !on) } }
                SRow { hub: sp.hub; label: "Grid overlay"
                    Tgl { hub: sp.hub; on: sp.hub.cb("grid", false); onFlipped: sp.hub.setCfg("grid", !on) } }

            }

            Column {
                width: col.width
                spacing: sp.s(2)
                visible: sp.page === "data"
                MBtn { hub: sp.hub; label: "< BACK"; accent: sp.hub.yellow; onClicked: sp.page = "" }
                Sec { hub: sp.hub; title: "DATA" }
                SRow { hub: sp.hub; label: "Offline downloads"; hint: sp.hub.sizes.dl + " on disk"
                    MBtn { hub: sp.hub; accent: sp.hub.red; solid: sp.confirm === "dl"
                           label: sp.confirm === "dl" ? "CONFIRM CLEAR" : "CLEAR"
                           onClicked: sp.ask("dl", function () { sp.hub.wipe("downloads") }) } }
                SRow { hub: sp.hub; label: "Cache"; hint: sp.hub.sizes.cache + " (archive pages, chapter lists)"
                    MBtn { hub: sp.hub; accent: sp.hub.red; solid: sp.confirm === "cache"
                           label: sp.confirm === "cache" ? "CONFIRM CLEAR" : "CLEAR"
                           onClicked: sp.ask("cache", function () { sp.hub.wipe("cache") }) } }
                SRow { hub: sp.hub; label: "Data folder"; hint: "library.json, downloads"
                    MBtn { hub: sp.hub; accent: sp.hub.blue; label: "OPEN"
                           onClicked: Quickshell.execDetached(["xdg-open", sp.hub.home + "/.local/share/qs-manga"]) } }
                SRow { hub: sp.hub; label: "Reset all settings"; hint: "library and progress are kept"
                    MBtn { hub: sp.hub; accent: sp.hub.red; solid: sp.confirm === "reset"
                           label: sp.confirm === "reset" ? "CONFIRM RESET" : "RESET"
                           onClicked: sp.ask("reset", function () { sp.hub.resetCfg() }) } }
            }

            Column {
                width: col.width
                spacing: sp.s(6)
                visible: sp.page === "downloads"
                MBtn { hub: sp.hub; label: "< BACK"; accent: sp.hub.yellow; onClicked: sp.page = "" }
                Sec { hub: sp.hub; title: "DOWNLOADS" }
                SRow { hub: sp.hub; label: "Queue"; hint: sp.dlActive.length > 0 ? "downloading in the background" : "idle"
                    Text { text: "ACTIVE " + sp.dlActive.length + "    FAILED " + sp.dlFailed.length + "    DONE " + (sp.dlSummary.done || 0)
                           color: sp.hub.text; font.family: sp.hub.mono; font.pixelSize: sp.fs(10); font.bold: true } }
                SRow { hub: sp.hub; visible: sp.dlFailed.length > 0; label: "Failed downloads"; hint: "retry keeps pages already saved"
                    Row {
                        spacing: sp.s(8)
                        MBtn { hub: sp.hub; label: "RETRY ALL"; accent: sp.hub.green
                               onClicked: sp.dlRetry(sp.dlFailed.map(function (e) { return e.cid })) }
                        MBtn { hub: sp.hub; label: "CLEAR"; accent: sp.hub.red; onClicked: sp.dlClearFailed() }
                    } }
                Text { visible: sp.dlActive.length === 0 && sp.dlFailed.length === 0
                       width: col.width; wrapMode: Text.Wrap
                       text: "NOTHING DOWNLOADING. USE DOWNLOAD ON A TITLE PAGE."
                       color: sp.hub.overlay0; font.family: sp.hub.mono; font.pixelSize: sp.fs(9); font.letterSpacing: sp.s(1) }
                Sec { hub: sp.hub; visible: sp.dlActive.length > 0; title: "IN PROGRESS" }
                Repeater {
                    model: sp.dlActive
                    delegate: Rectangle {
                        id: arow
                        required property var modelData
                        readonly property real frac: modelData.total > 0 ? Math.min(1, modelData.done / modelData.total) : 0
                        width: col.width
                        height: acol.height + sp.s(22)
                        radius: sp.s(8)
                        color: Qt.alpha(sp.hub.surface0, 0.35)
                        Column {
                            id: acol
                            x: sp.s(14); y: sp.s(11)
                            width: parent.width - sp.s(28)
                            spacing: sp.s(6)
                            Text { width: parent.width; elide: Text.ElideRight; text: sp.dlName(arow.modelData); color: sp.hub.text
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(10); font.bold: true }
                            Rectangle {
                                width: parent.width; height: sp.s(6); radius: sp.s(3); color: sp.hub.surface1
                                Rectangle { width: parent.width * arow.frac; height: parent.height; radius: parent.radius; color: sp.hub.sapphire }
                            }
                            Text { text: arow.modelData.status === "running" ? "DOWNLOADING  " + arow.modelData.done + " / " + arow.modelData.total + " PAGES" : "WAITING IN QUEUE"
                                   color: sp.hub.subtext0; font.family: sp.hub.mono; font.pixelSize: sp.fs(8) }
                        }
                    }
                }
                Sec { hub: sp.hub; visible: sp.dlFailed.length > 0; title: "FAILED" }
                Repeater {
                    model: sp.dlFailed
                    delegate: Rectangle {
                        id: frow
                        required property var modelData
                        width: col.width
                        height: fcol.height + sp.s(22)
                        radius: sp.s(8)
                        color: Qt.alpha(sp.hub.red, 0.08)
                        border.width: 1; border.color: Qt.alpha(sp.hub.red, 0.4)
                        Column {
                            id: fcol
                            x: sp.s(14); y: sp.s(11)
                            width: parent.width - sp.s(28)
                            spacing: sp.s(6)
                            Text { width: parent.width; elide: Text.ElideRight; text: sp.dlName(frow.modelData); color: sp.hub.text
                                   font.family: sp.hub.mono; font.pixelSize: sp.fs(10); font.bold: true }
                            Text { width: parent.width; wrapMode: Text.Wrap; text: frow.modelData.error || "Unknown error"
                                   color: sp.hub.red; font.family: sp.hub.mono; font.pixelSize: sp.fs(9) }
                            Text { visible: frow.modelData.total > 0; text: frow.modelData.done + " OF " + frow.modelData.total + " PAGES SAVED"
                                   color: sp.hub.subtext0; font.family: sp.hub.mono; font.pixelSize: sp.fs(8) }
                            Row {
                                spacing: sp.s(8)
                                MBtn { hub: sp.hub; label: "RETRY"; accent: sp.hub.green; onClicked: sp.dlRetry([frow.modelData.cid]) }
                                MBtn { hub: sp.hub; label: "REMOVE"; accent: sp.hub.red; onClicked: sp.dlRemove(frow.modelData.cid) }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: sp.s(10) }
            Text { visible: sp.page === ""; text: "MANGA//DECK  /  " + sp.hub.sources.length + " SOURCES  /  KEYS: ESC CLOSE, M MODE, N P CHAPTERS"
                   color: sp.hub.overlay0; font.family: sp.hub.mono; font.pixelSize: sp.fs(8); font.letterSpacing: sp.s(1) }
        }
    }

    MScroll { hub: sp.hub; target: flick; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } }
}
