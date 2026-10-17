import QtQuick
import "."
import QtQuick.Layouts

Item {
    id: page
    property var hub: null
    function s(v) { return hub.s(v); }

    readonly property color cText: hub.text
    readonly property color cSub0: hub.subtext0
    readonly property color cSub1: hub.subtext1
    readonly property color cSurf0: hub.surface0
    readonly property color cSurf1: hub.surface1
    readonly property color cMauve: hub.mauve
    readonly property color cRed: hub.red

    property string dictText: ""
    property var tokens: []
    property bool analyzing: false
    property string selected: ""
    property int selIndex: -1
    property var wordData: null
    property bool wordLoading: false
    property bool resultsMode: false
    property var results: []
    property bool searching: false
    property bool fromResults: false
    property bool noHan: false
    property string errorMsg: ""
    property var eng: null
    property string engQuery: ""

    readonly property var hanTokens: page.tokens.filter(function (t) { return t.han === true; })
    readonly property bool busyAny: analyzing || wordLoading || searching
    readonly property var allDefs: {
        let out = [];
        if (page.wordData && page.wordData.entries) {
            for (let i = 0; i < page.wordData.entries.length; i++) {
                let ds = page.wordData.entries[i].defs;
                for (let j = 0; j < ds.length; j++)
                    if (out.indexOf(ds[j]) < 0) out.push(ds[j]);
            }
        }
        return out.slice(0, 14);
    }
    readonly property string errText: errorMsg === "no-db"
        ? "Dictionary data is not built yet. Run: ~/.local/share/qs-venv/bin/python ~/.config/hypr/scripts/quickshell/translate/lookup.py build"
        : (errorMsg === "parse" ? "Lookup backend failed. Check that ~/.local/share/qs-venv exists." : errorMsg)

    property real pulse: 1.0
    SequentialAnimation on pulse {
        running: page.busyAny; loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    function hasHan(t) { return /[\u3400-\u9fff\uf900-\ufaff]/.test(t || ""); }
    function focusSearch() { searchInput.forceActiveFocus(); searchInput.selectAll(); }
    function copyMeanings() { if (resultsMode) copyEnglish(); else page.hub.copyText(page.allDefs.join("; "), "Meanings copied"); }

    function analyzeText(t) {
        t = (t || "").trim();
        dictText = t;
        resultsMode = false; fromResults = false; errorMsg = "";
        if (t === "" || !hasHan(t)) {
            tokens = []; noHan = (t !== ""); wordData = null; selected = ""; selIndex = -1;
            return;
        }
        noHan = false;
        analyzing = true;
        analyzer.request(t);
    }
    function selectWord(w) {
        selected = w; wordLoading = true; errorMsg = "";
        worder.request(w);
    }
    function selectToken(i) {
        if (i < 0 || i >= hanTokens.length) return;
        selIndex = i;
        selectWord(hanTokens[i].w);
    }
    function runSearch(q) {
        q = (q || "").trim();
        if (q === "") return;
        if (hasHan(q)) { analyzeText(q); return; }
        resultsMode = true; fromResults = false; searching = true; errorMsg = "";
        eng = null; engQuery = q;
        definer.request(q.toLowerCase());
    }
    function pickSuggestion(w) { searchInput.text = w; runSearch(w); }
    function copyEnglish() {
        if (!eng || !eng.meanings || eng.meanings.length === 0) return;
        let lines = [];
        for (let i = 0; i < eng.meanings.length; i++) {
            let m = eng.meanings[i];
            for (let j = 0; j < Math.min(2, m.defs.length); j++) lines.push(m.pos + ": " + m.defs[j].d);
        }
        hub.copyText(eng.word + "\n" + lines.join("\n"), "Definition copied");
    }

    LookupProc {
        id: analyzer
        mode: "analyze"
        onResult: (d, arg) => {
            page.analyzing = false;
            if (d.error) { page.errorMsg = d.error; page.tokens = []; return; }
            let han = d.tokens.filter(function (t) { return t.han === true; });
            let pick = -1;
            for (let i = 0; i < han.length && pick < 0; i++)
                if (han[i].found) pick = i;
            if (pick < 0 && han.length > 0) pick = 0;
            page.tokens = d.tokens;
            if (pick >= 0) page.selectToken(pick);
        }
    }
    LookupProc {
        id: worder
        mode: "word"
        onResult: (d, arg) => {
            page.wordLoading = false;
            if (d.error) { page.errorMsg = d.error; return; }
            page.wordData = d;
        }
    }
    LookupProc {
        id: definer
        mode: "define"
        onResult: (d, arg) => {
            page.searching = false;
            if (d.error) { page.errorMsg = d.error; page.eng = null; return; }
            page.eng = d;
        }
    }

    Component.onCompleted: { if (hasHan(hub.original)) analyzeText(hub.original); }
    Connections {
        target: page.hub
        function onOriginalChanged() { page.analyzeText(page.hub.original); }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: page.s(14)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: page.s(46)
            ColumnLayout {
                spacing: page.s(4)
                Text { text: "Dictionary"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(30); color: page.cText }
                Text { text: "English definitions  \u00b7  Free Dictionary API"; font.family: "JetBrains Mono"; font.pixelSize: page.s(11); color: page.cSub0 }
            }
            Item { Layout.fillWidth: true }
            PillBtn {
                visible: page.fromResults && page.results.length > 0 && !page.resultsMode
                hub: page.hub; label: "\u2039  Results"
                onClicked: { page.resultsMode = true; }
            }
        }

        // ---- sweep ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: page.s(2)
            radius: 1; color: page.cSurf0; clip: true
            Rectangle {
                id: sweep
                width: parent.width * 0.3; height: parent.height; radius: 1
                color: page.cMauve
                visible: page.busyAny
                SequentialAnimation on x {
                    running: page.busyAny; loops: Animation.Infinite
                    NumberAnimation { from: -sweep.width; to: sweep.parent.width; duration: 1000; easing.type: Easing.InOutQuad }
                }
            }
        }

        // ---- search bar ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: page.s(54)
            radius: page.s(14)
            color: Qt.alpha(page.cSurf0, 0.5)
            border.color: searchInput.activeFocus ? page.cMauve : page.cSurf1
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 200 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: page.s(18); anchors.rightMargin: page.s(12)
                spacing: page.s(12)

                Text {
                    text: "\uDB80\uDF49"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: page.s(20)
                    color: searchInput.activeFocus ? page.cMauve : page.cSub0
                }
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        font.family: "JetBrains Mono"; font.pixelSize: page.s(16)
                        color: page.cText; selectionColor: page.cMauve
                        selectByMouse: true; clip: true
                        Keys.onReturnPressed: page.runSearch(searchInput.text)
                        Keys.onEnterPressed: page.runSearch(searchInput.text)
                        Keys.onEscapePressed: (e) => { page.hub.requestClose(); e.accepted = true; }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text === ""
                        text: "Look up a word in English\u2026"
                        font.family: "JetBrains Mono"; font.pixelSize: page.s(15)
                        color: page.cSub0; opacity: 0.7
                    }
                }
                Rectangle {
                    visible: searchInput.text !== ""
                    Layout.preferredWidth: page.s(26); Layout.preferredHeight: page.s(26)
                    radius: width / 2
                    color: clrMa.containsMouse ? page.cSurf1 : "transparent"
                    Text { anchors.centerIn: parent; text: "\u00d7"; font.pixelSize: page.s(18); color: page.cSub0 }
                    MouseArea { id: clrMa; anchors.fill: parent; hoverEnabled: true; onClicked: { searchInput.text = ""; searchInput.forceActiveFocus(); } }
                }
                Rectangle {
                    visible: page.hasHan(page.hub.original) && page.dictText !== page.hub.original.trim()
                    Layout.preferredHeight: page.s(30)
                    Layout.preferredWidth: useText.implicitWidth + page.s(24)
                    radius: page.s(8)
                    color: useMa.containsMouse ? Qt.alpha(page.cMauve, 0.2) : Qt.alpha(page.cMauve, 0.1)
                    border.color: page.cMauve; border.width: 1
                    Text { id: useText; anchors.centerIn: parent; text: "Use scanned text"; font.family: "JetBrains Mono"; font.pixelSize: page.s(11); font.weight: Font.Bold; color: page.cMauve }
                    MouseArea { id: useMa; anchors.fill: parent; hoverEnabled: true; onClicked: page.analyzeText(page.hub.original) }
                }
                Text { text: "Enter"; font.family: "JetBrains Mono"; font.pixelSize: page.s(10); color: page.cSub0 }
            }
        }

        // ---- error banner ----
        Rectangle {
            visible: page.errorMsg !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: errEdit.paintedHeight + page.s(24)
            radius: page.s(10)
            color: Qt.alpha(page.cRed, 0.1); border.color: Qt.alpha(page.cRed, 0.5); border.width: 1
            TextEdit {
                id: errEdit
                anchors.fill: parent; anchors.margins: page.s(12)
                text: page.errText
                readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                font.family: "JetBrains Mono"; font.pixelSize: page.s(12); color: page.cRed
            }
        }

        // ---- full English translation of the scanned text ----
        Rectangle {
            visible: page.hanTokens.length > 0 && !page.resultsMode && page.hub.status === "done" && page.hub.translated !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: page.s(58)
            radius: page.s(12)
            color: Qt.alpha(page.cMauve, 0.08)
            border.color: Qt.alpha(page.cMauve, 0.35); border.width: 1
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: page.s(16); anchors.rightMargin: page.s(16)
                spacing: page.s(14)
                Text { text: "ENGLISH"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cMauve }
                Text {
                    Layout.fillWidth: true
                    text: page.hub.translated
                    wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                    font.family: "JetBrains Mono"; font.pixelSize: page.s(15)
                    color: page.cText
                }
            }
        }

        // ---- one English chip per word of the scan ----
        Rectangle {
            visible: page.hanTokens.length > 0 && !page.resultsMode
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(tokFlow.height + page.s(20), page.s(150))
            radius: page.s(14)
            color: Qt.alpha(page.cSurf0, 0.35)
            border.color: page.cSurf1; border.width: 1
            clip: true
            Flickable {
                id: tokFlick
                anchors.fill: parent; anchors.margins: page.s(10)
                contentHeight: tokFlow.height
                clip: true; boundsBehavior: Flickable.StopAtBounds
                Flow {
                    id: tokFlow
                    width: tokFlick.width
                    spacing: page.s(8)
                    Repeater {
                        model: page.hanTokens
                        delegate: Rectangle {
                            id: tk
                            required property int index
                            required property var modelData
                            readonly property bool sel: tk.index === page.selIndex
                            readonly property bool known: (tk.modelData.def || "") !== ""
                            width: page.s(168); height: page.s(54)
                            radius: page.s(10)
                            color: tk.sel ? Qt.alpha(page.cMauve, 0.22) : (tkMa.containsMouse ? Qt.alpha(page.cSurf1, 0.7) : Qt.alpha(page.cSurf0, 0.5))
                            border.color: tk.sel ? page.cMauve : page.cSurf1
                            border.width: 1
                            scale: tkMa.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: 90 } }
                            Text {
                                anchors.fill: parent; anchors.margins: page.s(10)
                                verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                text: tk.known ? tk.modelData.def : "no entry"
                                wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: page.s(13)
                                color: tk.sel ? page.cMauve : (tk.known ? page.cText : page.cSub0)
                            }
                            MouseArea { id: tkMa; anchors.fill: parent; hoverEnabled: true; onClicked: page.selectToken(tk.index) }
                        }
                    }
                }
            }
        }

        // ---- English definition (Free Dictionary API) ----
        Rectangle {
            visible: page.resultsMode
            Layout.fillWidth: true; Layout.fillHeight: true
            radius: page.s(16)
            color: Qt.alpha(page.cMauve, 0.06)
            border.color: Qt.alpha(page.cMauve, 0.3); border.width: 1
            clip: true

            Text {
                anchors.centerIn: parent
                visible: page.searching && page.eng === null
                text: "Looking up \u201c" + page.engQuery + "\u201d\u2026"
                font.family: "JetBrains Mono"; font.pixelSize: page.s(18); color: page.cSub0
                opacity: page.pulse
            }

            // not found + did-you-mean
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - page.s(80)
                visible: page.eng !== null && page.eng.notfound === true
                spacing: page.s(14)
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No definition found for \u201c" + page.engQuery + "\u201d"
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(20); color: page.cText
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: page.eng !== null && page.eng.suggestions !== undefined && page.eng.suggestions.length > 0
                    text: "DID YOU MEAN"
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cSub0
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: page.s(10)
                    Repeater {
                        model: (page.eng && page.eng.suggestions) ? page.eng.suggestions : []
                        delegate: Rectangle {
                            id: sg
                            required property var modelData
                            Layout.preferredHeight: page.s(38)
                            Layout.preferredWidth: sgText.implicitWidth + page.s(30)
                            radius: page.s(10)
                            color: sgMa.containsMouse ? Qt.alpha(page.cMauve, 0.2) : Qt.alpha(page.cMauve, 0.08)
                            border.color: page.cMauve; border.width: 1
                            Text { id: sgText; anchors.centerIn: parent; text: sg.modelData; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(15); color: page.cMauve }
                            MouseArea { id: sgMa; anchors.fill: parent; hoverEnabled: true; onClicked: page.pickSuggestion(sg.modelData) }
                        }
                    }
                }
            }

            // definition
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: page.s(30)
                spacing: page.s(12)
                visible: page.eng !== null && page.eng.meanings !== undefined

                RowLayout {
                    Layout.fillWidth: true
                    spacing: page.s(16)
                    Text {
                        text: page.eng ? page.eng.word : ""
                        font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(40); color: page.cText
                    }
                    Text {
                        Layout.alignment: Qt.AlignBottom
                        visible: !!(page.eng && page.eng.phonetic)
                        text: page.eng && page.eng.phonetic ? page.eng.phonetic : ""
                        font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: page.s(18); color: page.cMauve
                    }
                    Item { Layout.fillWidth: true }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: page.cSurf1 }

                Flickable {
                    id: engFlick
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: engCol.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: engCol
                        width: engFlick.width
                        spacing: page.s(18)
                        Repeater {
                            model: (page.eng && page.eng.meanings) ? page.eng.meanings : []
                            delegate: ColumnLayout {
                                id: mg
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: page.s(8)
                                Rectangle {
                                    Layout.preferredHeight: page.s(24)
                                    Layout.preferredWidth: posText.implicitWidth + page.s(20)
                                    radius: page.s(6)
                                    color: Qt.alpha(page.cMauve, 0.18)
                                    Text { id: posText; anchors.centerIn: parent; text: mg.modelData.pos.toUpperCase(); font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cMauve }
                                }
                                Repeater {
                                    model: mg.modelData.defs
                                    delegate: ColumnLayout {
                                        id: dg
                                        required property int index
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: page.s(3)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: page.s(10)
                                            Text { Layout.alignment: Qt.AlignTop; Layout.preferredWidth: page.s(28); text: String(dg.index + 1) + "."; font.family: "JetBrains Mono"; font.pixelSize: page.s(14); color: page.cSub0 }
                                            Text { Layout.fillWidth: true; text: dg.modelData.d; wrapMode: Text.Wrap; font.family: "JetBrains Mono"; font.pixelSize: page.s(16); color: page.cText }
                                        }
                                        Text {
                                            visible: dg.modelData.ex !== ""
                                            Layout.fillWidth: true
                                            Layout.leftMargin: page.s(38)
                                            text: "\u201c" + dg.modelData.ex + "\u201d"
                                            wrapMode: Text.Wrap
                                            font.family: "JetBrains Mono"; font.italic: true; font.pixelSize: page.s(13); color: page.cSub1
                                        }
                                    }
                                }
                                Text {
                                    visible: mg.modelData.synonyms.length > 0
                                    Layout.fillWidth: true
                                    text: "Synonyms: " + mg.modelData.synonyms.join(", ")
                                    wrapMode: Text.Wrap
                                    font.family: "JetBrains Mono"; font.pixelSize: page.s(13); color: Qt.alpha(page.cMauve, 0.9)
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    PillBtn { hub: page.hub; label: "Copy definition"; onClicked: page.copyEnglish() }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ---- meanings of the selected word ----
        Rectangle {
            visible: !page.resultsMode
            Layout.fillWidth: true; Layout.fillHeight: true
            radius: page.s(16)
            color: Qt.alpha(page.cMauve, 0.06)
            border.color: Qt.alpha(page.cMauve, 0.3); border.width: 1
            clip: true

            ColumnLayout {
                anchors.centerIn: parent
                visible: page.selected === ""
                spacing: page.s(10)
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "\uDB80\uDF49"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: page.s(90)
                    color: page.cMauve; opacity: 0.18
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: page.noHan ? "No Chinese found in that text." : "Scan something, or look up a word in English."
                    font.family: "JetBrains Mono"; font.pixelSize: page.s(15); color: page.cSub0
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: page.s(30)
                spacing: page.s(14)
                visible: page.selected !== ""

                Text {
                    visible: page.wordLoading && page.allDefs.length === 0
                    text: "Looking up\u2026"
                    font.family: "JetBrains Mono"; font.pixelSize: page.s(18); color: page.cSub0
                    opacity: page.pulse
                }
                Text {
                    Layout.fillWidth: true
                    visible: page.allDefs.length > 0
                    text: page.allDefs.length > 0 ? page.allDefs[0] : ""
                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                    font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(30)
                    color: page.cText
                    opacity: page.wordLoading ? page.pulse : 1.0
                }
                Text {
                    Layout.fillWidth: true
                    visible: !page.wordLoading && page.wordData !== null && page.allDefs.length === 0
                    text: "No plain-English entry for this word. Names and rare words often don't have one."
                    wrapMode: Text.Wrap
                    font.family: "JetBrains Mono"; font.pixelSize: page.s(15); color: page.cSub0
                }

                Rectangle { visible: page.allDefs.length > 1; Layout.fillWidth: true; Layout.preferredHeight: 1; color: page.cSurf1 }

                Flickable {
                    id: defFlick
                    visible: page.allDefs.length > 1
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: defCol.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    ColumnLayout {
                        id: defCol
                        width: defFlick.width
                        spacing: page.s(12)
                        Text {
                            text: "OTHER MEANINGS"
                            font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cSub0
                        }
                        Repeater {
                            model: page.allDefs.slice(1)
                            delegate: RowLayout {
                                id: df
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: page.s(12)
                                Rectangle {
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredWidth: page.s(24); Layout.preferredHeight: page.s(24)
                                    radius: width / 2
                                    color: Qt.alpha(page.cMauve, 0.18)
                                    Text { anchors.centerIn: parent; text: String(df.index + 2); font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(11); color: page.cMauve }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: df.modelData
                                    wrapMode: Text.Wrap
                                    font.family: "JetBrains Mono"; font.pixelSize: page.s(16)
                                    color: page.cText
                                }
                            }
                        }
                    }
                }
                Item { visible: page.allDefs.length <= 1; Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    PillBtn { hub: page.hub; label: "Copy meanings"; onClicked: page.copyMeanings() }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
