import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "."

Item {
    id: pg
    property var hub: null
    property bool active: false
    property string mode: "search"
    property var results: []
    property var allInstalled: []
    property bool searching: false
    property bool pending: false
    property var searchCmd: []
    property var pkgCmd: []
    property string confirmName: ""
    property string pkgName: ""
    property string pkgText: ""
    property bool showPkg: false
    function s(v) { return hub.s(v) }

    function runSearch() {
        var q = box.text.trim()
        if (mode === "installed") { refilter(); return }
        if (q.length < 2) { results = []; return }
        if (searchProc.running) { pending = true; return }
        searchCmd = ["python3", hub.script, "search", q]
        searching = true
        searchProc.running = true
    }
    function refilter() {
        var q = box.text.trim().toLowerCase()
        var out = []
        for (var i = 0; i < allInstalled.length; i++)
            if (q === "" || allInstalled[i].name.toLowerCase().indexOf(q) >= 0) out.push(allInstalled[i])
        results = out
    }
    function loadInstalled() { if (!instProc.running) instProc.running = true }
    function setMode(m) {
        mode = m; results = []
        if (m === "installed") loadInstalled(); else runSearch()
    }
    onActiveChanged: { if (active) box.forceActiveFocus(); else hub.forceActiveFocus() }
    Connections {
        target: pg.hub
        function onJobTickChanged() { if (pg.mode === "installed") pg.loadInstalled(); else pg.runSearch() }
    }
    Timer { id: debounce; interval: 400; onTriggered: pg.runSearch() }
    Timer { id: confirmT; interval: 3000; onTriggered: pg.confirmName = "" }

    Process {
        id: searchProc
        command: pg.searchCmd
        stdout: StdioCollector {
            onStreamFinished: {
                pg.searching = false
                try { pg.results = JSON.parse(text) } catch (e) {}
                if (pg.pending) { pg.pending = false; pg.runSearch() }
            }
        }
    }
    Process {
        id: instProc
        command: ["python3", pg.hub.script, "installed"]
        stdout: StdioCollector {
            onStreamFinished: { try { pg.allInstalled = JSON.parse(text) } catch (e) {} pg.refilter() }
        }
    }
    Process {
        id: pkgProc
        command: pg.pkgCmd
        stdout: StdioCollector {
            onStreamFinished: { try { pg.pkgText = JSON.parse(text).text } catch (e) { pg.pkgText = "failed to load" } }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: pg.s(12)

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: pg.s(50)
            radius: pg.s(12)
            color: Qt.alpha(pg.hub.surface0, 0.6)
            border.width: 1
            border.color: box.activeFocus ? pg.hub.pink : Qt.alpha(pg.hub.mauve, 0.4)
            Behavior on border.color { ColorAnimation { duration: 150 } }
            Text { id: prompt; x: pg.s(16); anchors.verticalCenter: parent.verticalCenter; text: ">"; color: pg.hub.pink
                   font.family: pg.hub.mono; font.pixelSize: pg.s(16); font.bold: true }
            TextInput {
                id: box
                anchors { left: prompt.right; leftMargin: pg.s(12); right: parent.right; rightMargin: pg.s(16); verticalCenter: parent.verticalCenter }
                color: pg.hub.text
                selectionColor: Qt.alpha(pg.hub.pink, 0.4)
                font.family: pg.hub.mono; font.pixelSize: pg.s(14)
                clip: true
                onTextChanged: debounce.restart()
                onAccepted: pg.runSearch()
                Text {
                    visible: box.text === ""
                    text: pg.mode === "search" ? "search packages (repo + AUR)..." : "filter installed packages..."
                    color: pg.hub.overlay0
                    font.family: pg.hub.mono; font.pixelSize: pg.s(14)
                }
            }
        }

        Row {
            spacing: pg.s(10)
            HubBtn { hub: pg.hub; label: "SEARCH"; accent: pg.hub.pink; solid: pg.mode === "search"; onClicked: pg.setMode("search") }
            HubBtn { hub: pg.hub; label: "INSTALLED"; accent: pg.hub.blue; solid: pg.mode === "installed"; onClicked: pg.setMode("installed") }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: pg.s(8)
                text: pg.searching ? "SEARCHING..." : pg.results.length + " RESULTS"
                color: pg.hub.subtext0
                font.family: pg.hub.mono; font.pixelSize: pg.s(10); font.letterSpacing: pg.s(2)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: pg.s(14)
            color: Qt.alpha(pg.hub.surface0, 0.4)
            border.width: 1
            border.color: Qt.alpha(pg.hub.mauve, 0.25)
            clip: true
            ListView {
                anchors.fill: parent
                anchors.margins: pg.s(8)
                clip: true
                spacing: pg.s(6)
                model: pg.results
                boundsBehavior: Flickable.StopAtBounds
                delegate: Rectangle {
                    id: rw
                    required property var modelData
                    readonly property string repo: modelData.repo ? modelData.repo : (modelData.foreign ? "aur" : "local")
                    readonly property bool isAur: repo === "aur"
                    readonly property bool inst: pg.mode === "installed" || modelData.installed === true
                    readonly property color rc: isAur ? pg.hub.peach : repo === "core" ? pg.hub.red : repo === "extra" ? pg.hub.blue : pg.hub.green
                    width: ListView.view.width
                    height: pg.s(74)
                    radius: pg.s(10)
                    color: Qt.alpha(pg.hub.surface1, 0.3)
                    Row {
                        x: pg.s(16); y: pg.s(12); spacing: pg.s(10)
                        Text { text: rw.modelData.name; color: pg.hub.text
                               font.family: pg.hub.mono; font.pixelSize: pg.s(13); font.bold: true }
                        Rectangle {
                            height: pg.s(16); width: rtag.width + pg.s(12); radius: pg.s(4)
                            color: "transparent"; border.width: 1; border.color: rw.rc
                            Text { id: rtag; anchors.centerIn: parent; text: rw.repo.toUpperCase(); color: rw.rc
                                   font.family: pg.hub.mono; font.pixelSize: pg.s(8); font.bold: true }
                        }
                        Text { text: rw.modelData.ver; color: pg.hub.subtext0
                               font.family: pg.hub.mono; font.pixelSize: pg.s(10) }
                        Text { visible: rw.isAur && pg.mode === "search"; text: rw.modelData.votes + " VOTES"
                               color: pg.hub.yellow; font.family: pg.hub.mono; font.pixelSize: pg.s(9) }
                        Text { visible: rw.modelData.ood === true; text: "OUT OF DATE"; color: pg.hub.red
                               font.family: pg.hub.mono; font.pixelSize: pg.s(9); font.bold: true }
                        Text { visible: rw.inst && pg.mode === "search"; text: "INSTALLED"; color: pg.hub.green
                               font.family: pg.hub.mono; font.pixelSize: pg.s(9); font.bold: true }
                    }
                    Text {
                        x: pg.s(16); y: pg.s(40)
                        width: rw.width - pg.s(36) - btnRow.width
                        text: rw.modelData.desc ? rw.modelData.desc : ""
                        color: pg.hub.subtext1; elide: Text.ElideRight
                        font.family: pg.hub.mono; font.pixelSize: pg.s(10)
                    }
                    Row {
                        id: btnRow
                        anchors { right: parent.right; rightMargin: pg.s(14); verticalCenter: parent.verticalCenter }
                        spacing: pg.s(8)
                        HubBtn {
                            hub: pg.hub; label: "PKGBUILD"; accent: pg.hub.yellow
                            visible: rw.isAur && pg.mode === "search"
                            onClicked: {
                                if (pkgProc.running) return
                                pg.pkgName = rw.modelData.name; pg.pkgText = "LOADING..."; pg.showPkg = true
                                pg.pkgCmd = ["python3", pg.hub.script, "pkgbuild", rw.modelData.name]
                                pkgProc.running = true
                            }
                        }
                        HubBtn {
                            hub: pg.hub; label: "BUILD (TERMINAL)"; accent: pg.hub.peach
                            visible: rw.isAur && !rw.inst
                            onClicked: Quickshell.execDetached(["kitty", "-e", "bash", "-c",
                                "yay -S -- \"$1\"; echo; read -rp 'Press enter to close' _", "_", rw.modelData.name])
                        }
                        HubBtn {
                            hub: pg.hub; label: "INSTALL"; accent: pg.hub.green
                            visible: !rw.isAur && !rw.inst
                            enabled: pg.hub.fixStatus !== "running"
                            onClicked: pg.hub.startJob("install", [rw.modelData.name])
                        }
                        HubBtn {
                            hub: pg.hub
                            label: pg.confirmName === rw.modelData.name ? "CONFIRM REMOVE" : "REMOVE"
                            accent: pg.hub.red
                            solid: pg.confirmName === rw.modelData.name
                            visible: rw.inst
                            enabled: pg.hub.fixStatus !== "running"
                            onClicked: {
                                if (pg.confirmName === rw.modelData.name) { pg.confirmName = ""; pg.hub.startJob("remove", [rw.modelData.name]) }
                                else { pg.confirmName = rw.modelData.name; confirmT.restart() }
                            }
                        }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: pg.results.length === 0 && !pg.searching
                text: pg.mode === "search" ? (box.text.trim().length < 2 ? "TYPE TO SEARCH REPOS + AUR" : "NO MATCHES") : "NO PACKAGES"
                color: pg.hub.overlay0
                font.family: pg.hub.mono; font.pixelSize: pg.s(12); font.letterSpacing: pg.s(3)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: pg.showPkg
        z: 10
        radius: pg.s(14)
        color: Qt.alpha(pg.hub.crust, 0.97)
        border.width: 1
        border.color: pg.hub.yellow
        Text { x: pg.s(18); y: pg.s(14); text: "PKGBUILD // " + pg.pkgName.toUpperCase(); color: pg.hub.yellow
               font.family: pg.hub.mono; font.pixelSize: pg.s(11); font.bold: true; font.letterSpacing: pg.s(2) }
        Text { x: pg.s(18); y: pg.s(34); text: "READ IT BEFORE YOU BUILD. AUR PACKAGES ARE UNVETTED."; color: pg.hub.subtext0
               font.family: pg.hub.mono; font.pixelSize: pg.s(9) }
        HubBtn {
            hub: pg.hub; label: "CLOSE"; accent: pg.hub.red
            anchors { right: parent.right; rightMargin: pg.s(14); top: parent.top; topMargin: pg.s(12) }
            onClicked: pg.showPkg = false
        }
        Flickable {
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                      leftMargin: pg.s(18); rightMargin: pg.s(18); topMargin: pg.s(62); bottomMargin: pg.s(14) }
            contentHeight: pkgT.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: pkgT
                width: parent.width
                text: pg.pkgText; color: pg.hub.text
                wrapMode: Text.WrapAnywhere
                font.family: pg.hub.mono; font.pixelSize: pg.s(10)
            }
        }
    }
}
