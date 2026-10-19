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
    readonly property color cGreen: hub.green
    readonly property color cRed: hub.red

    readonly property bool busy: hub.status === "scanning" || hub.status === "loading"
    readonly property string statusLabel: hub.status === "scanning" ? "Scanning" : hub.status === "loading" ? "Translating" : hub.status === "done" ? "Done" : hub.status === "error" ? "Error" : "Ready"
    readonly property color statusColor: busy ? cMauve : hub.status === "done" ? cGreen : hub.status === "error" ? cRed : cSub0

    property real pulse: 1.0
    SequentialAnimation on pulse {
        running: page.busy; loops: Animation.Infinite
        NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    }

    property bool moreLangs: false
    readonly property var chipModel: (moreLangs ? hub.langChips : hub.langChips.slice(0, 8)).concat([{ label: moreLangs ? "Less" : "More\u2026", langs: "__more" }])

    // ---- typewriter reveal ----
    property bool wasBusy: false
    property bool typing: false
    property int revealWords: 0
    readonly property var transWords: hub.translated === "" ? [] : hub.translated.split(" ")
    readonly property string shownText: typing ? transWords.slice(0, revealWords).join(" ") + " \u258d" : hub.translated
    Timer {
        id: typeTimer
        interval: 55; repeat: true; running: page.typing
        onTriggered: {
            page.revealWords += 1;
            Qt.callLater(function () { dstFlick.contentY = Math.max(0, dstFlick.contentHeight - dstFlick.height); });
            if (page.revealWords >= page.transWords.length) page.typing = false;
        }
    }
    Timer {
        id: startFx
        interval: 40
        onTriggered: {
            page.revealWords = 0;
            dstFlick.contentY = 0;
            page.typing = page.transWords.length > 0;
            stampAnim.restart();
            rippleAnim.restart();
        }
    }

    // ---- word-by-word (interlinear) ----
    property int viewMode: 0            // 0 = text, 1 = word by word
    property var tokens: []
    property bool tokBusy: false
    readonly property bool zhText: hub.langs.indexOf("chi_") >= 0
    function hasHan(t) { return /[\u3400-\u9fff\uf900-\ufaff]/.test(t || ""); }
    function refreshTokens() {
        if (viewMode !== 1 || !zhText || !hasHan(hub.original)) { tokens = []; return; }
        tokBusy = true;
        tokProc.request(hub.original);
    }
    LookupProc {
        id: tokProc
        mode: "analyze"
        onResult: (d, arg) => { page.tokBusy = false; page.tokens = d.error ? [] : d.tokens; }
    }
    onViewModeChanged: refreshTokens()

    Component.onCompleted: srcEdit.text = hub.original
    Connections {
        target: page.hub
        function onOriginalChanged() {
            srcEdit.text = page.hub.original;
            srcFade.restart();
            page.refreshTokens();
        }
        function onStatusChanged() {
            const st = page.hub.status;
            if (st === "idle") srcEdit.forceActiveFocus();
            if (st === "loading" || st === "scanning") { page.wasBusy = true; page.typing = false; hanko.opacity = 0; }
            if (st === "done" && page.wasBusy) { page.wasBusy = false; startFx.restart(); }
        }
    }

    SequentialAnimation {
        id: stampAnim
        PropertyAction { target: hanko; property: "opacity"; value: 0 }
        PropertyAction { target: hanko; property: "scale"; value: 2.4 }
        ParallelAnimation {
            NumberAnimation { target: hanko; property: "opacity"; to: 0.88; duration: 110 }
            NumberAnimation { target: hanko; property: "scale"; to: 1.0; duration: 280; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
        }
        ParallelAnimation {
            NumberAnimation { target: stampRing; property: "scale"; from: 1.0; to: 1.9; duration: 380; easing.type: Easing.OutCubic }
            NumberAnimation { target: stampRing; property: "opacity"; from: 0.5; to: 0.0; duration: 380 }
        }
    }
    SequentialAnimation {
        id: rippleAnim
        ParallelAnimation {
            NumberAnimation { target: ripple; property: "scale"; from: 1.0; to: 5.5; duration: 900; easing.type: Easing.OutCubic }
            NumberAnimation { target: ripple; property: "opacity"; from: 0.6; to: 0.0; duration: 900 }
        }
    }
    NumberAnimation { id: srcFade; target: srcArea; property: "opacity"; from: 0.0; to: 1.0; duration: 500; easing.type: Easing.OutCubic }

    ColumnLayout {
        anchors.fill: parent
        spacing: page.s(16)

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            Layout.rightMargin: page.s(46)
            ColumnLayout {
                spacing: page.s(4)
                Text { text: "Translate"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(30); color: page.cText }
                Text {
                    text: "Screen text to English  \u00b7  " + hub.langLabel(hub.langs) + (hub.conf > 0 ? "  \u00b7  " + hub.conf + "% confident" : "")
                    font.family: "JetBrains Mono"; font.pixelSize: page.s(11); color: page.cSub0
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredHeight: page.s(30)
                Layout.preferredWidth: pillRow.implicitWidth + page.s(26)
                radius: height / 2
                color: Qt.alpha(page.statusColor, 0.14)
                border.color: Qt.alpha(page.statusColor, 0.5); border.width: 1
                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: page.s(8)
                    Rectangle { width: page.s(8); height: page.s(8); radius: page.s(4); color: page.statusColor; opacity: page.busy ? page.pulse : 1.0 }
                    Text { text: page.statusLabel; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(11); color: page.statusColor }
                }
            }
        }

        // ---- progress sweep ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: page.s(2)
            radius: 1
            color: page.cSurf0
            clip: true
            Rectangle {
                id: sweep
                width: parent.width * 0.3; height: parent.height; radius: 1
                color: page.cMauve
                visible: page.busy
                SequentialAnimation on x {
                    running: page.busy; loops: Animation.Infinite
                    NumberAnimation { from: -sweep.width; to: sweep.parent.width; duration: 1000; easing.type: Easing.InOutQuad }
                }
            }
        }

        // ---- cards ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: page.s(14)

            // SOURCE
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredWidth: 100
                radius: page.s(16)
                color: Qt.alpha(page.cSurf0, 0.45)
                border.color: srcEdit.activeFocus ? page.cMauve : page.cSurf1
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 200 } }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: page.s(20)
                    spacing: page.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: page.s(8)
                        Text { text: "SOURCE"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cSub0 }
                        Item { Layout.fillWidth: true }
                        Repeater {
                            model: ["Text", "Word by word"]
                            delegate: Rectangle {
                                id: vm
                                required property int index
                                required property string modelData
                                readonly property bool act: page.viewMode === vm.index
                                Layout.preferredHeight: page.s(24)
                                Layout.preferredWidth: vmText.implicitWidth + page.s(18)
                                radius: page.s(6)
                                color: vm.act ? Qt.alpha(page.cMauve, 0.2) : (vmMa.containsMouse ? Qt.alpha(page.cMauve, 0.08) : "transparent")
                                border.color: vm.act ? page.cMauve : page.cSurf1; border.width: 1
                                Text { id: vmText; anchors.centerIn: parent; text: vm.modelData; font.family: "JetBrains Mono"; font.pixelSize: page.s(10); font.weight: vm.act ? Font.Bold : Font.Normal; color: vm.act ? page.cMauve : page.cSub0 }
                                MouseArea { id: vmMa; anchors.fill: parent; hoverEnabled: true; onClicked: page.viewMode = vm.index }
                            }
                        }
                        Text { text: srcEdit.text.length + " chars"; font.family: "JetBrains Mono"; font.pixelSize: page.s(10); color: page.cSub0 }
                    }

                    // captured image with scanline
                    Rectangle {
                        id: capBox
                        visible: hub.hasImg
                        property real hh: hub.status === "scanning" ? page.s(170) : page.s(96)
                        Behavior on hh { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                        Layout.fillWidth: true
                        Layout.preferredHeight: hh
                        radius: page.s(10)
                        color: Qt.alpha(hub.crust, 0.6)
                        border.color: hub.status === "scanning" ? page.cMauve : page.cSurf1
                        border.width: 1
                        clip: true
                        Image {
                            anchors.fill: parent; anchors.margins: page.s(4)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true; cache: false; smooth: true
                            source: hub.hasImg ? "file://" + hub.home + "/.cache/qs_translate_last.png?" + hub.imgStamp : ""
                        }
                        Rectangle {
                            id: scanline
                            visible: hub.status === "scanning"
                            width: parent.width; height: page.s(40)
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.alpha(page.cMauve, 0.45) }
                                GradientStop { position: 1.0; color: "transparent" }
                            }
                            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: page.s(2); color: page.cMauve }
                            SequentialAnimation on y {
                                running: hub.status === "scanning"; loops: Animation.Infinite
                                NumberAnimation { from: -scanline.height; to: capBox.height; duration: 1200; easing.type: Easing.InOutSine }
                            }
                        }
                    }

                    Item {
                        id: srcArea
                        Layout.fillWidth: true; Layout.fillHeight: true

                        ScrollHint { flick: srcFlick; hub: page.hub }
                        Flickable {
                            id: srcFlick
                            visible: page.viewMode === 0
                            anchors.fill: parent
                            contentHeight: srcEdit.paintedHeight
                            clip: true; boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: srcEdit
                                width: srcFlick.width - page.s(16)
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                readOnly: page.busy
                                font.family: "JetBrains Mono"; font.pixelSize: page.s(20)
                                color: page.cText; selectionColor: page.cMauve
                                Keys.onReturnPressed: (e) => {
                                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; }
                                    else { hub.retranslate(srcEdit.text); e.accepted = true; }
                                }
                                Keys.onEnterPressed: (e) => {
                                    if (e.modifiers & Qt.ShiftModifier) { e.accepted = false; }
                                    else { hub.retranslate(srcEdit.text); e.accepted = true; }
                                }
                                Keys.onEscapePressed: (e) => { hub.requestClose(); e.accepted = true; }
                            }
                        }
                        Text {
                            visible: page.viewMode === 0 && srcEdit.text === ""
                            anchors.left: parent.left; anchors.top: parent.top
                            text: hub.status === "scanning" ? "Reading text\u2026" : "Scan the screen, or type here\u2026"
                            font.family: "JetBrains Mono"; font.pixelSize: page.s(18)
                            color: page.cSub0; opacity: hub.status === "scanning" ? page.pulse : 0.6
                        }

                        // interlinear view
                        Flickable {
                            id: ilFlick
                            visible: page.viewMode === 1 && page.zhText && page.tokens.length > 0
                            anchors.fill: parent
                            contentHeight: ilFlow.height
                            clip: true; boundsBehavior: Flickable.StopAtBounds
                            Flow {
                                id: ilFlow
                                width: ilFlick.width
                                spacing: page.s(8)
                                Repeater {
                                    model: page.tokens
                                    delegate: Rectangle {
                                        id: tk
                                        required property var modelData
                                        readonly property bool han: tk.modelData.han === true
                                        width: tkCol.implicitWidth + page.s(18)
                                        height: tkCol.implicitHeight + page.s(14)
                                        radius: page.s(8)
                                        color: tk.han ? (tkMa.containsMouse ? Qt.alpha(page.cMauve, 0.14) : Qt.alpha(page.cSurf0, 0.5)) : "transparent"
                                        border.color: tk.han ? (tkMa.containsMouse ? page.cMauve : page.cSurf1) : "transparent"
                                        border.width: 1
                                        ColumnLayout {
                                            id: tkCol
                                            anchors.centerIn: parent
                                            spacing: page.s(3)
                                            Text { visible: tk.han; Layout.alignment: Qt.AlignHCenter; text: tk.modelData.pinyin || ""; font.family: "JetBrains Mono"; font.pixelSize: page.s(10); color: page.cMauve }
                                            Text { Layout.alignment: Qt.AlignHCenter; text: tk.modelData.w; font.pixelSize: page.s(tk.han ? 22 : 18); color: tk.han ? page.cText : page.cSub0 }
                                            Text {
                                                visible: tk.han
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.maximumWidth: page.s(110)
                                                text: tk.modelData.def || ""
                                                elide: Text.ElideRight
                                                font.family: "JetBrains Mono"; font.pixelSize: page.s(10); color: page.cSub1
                                            }
                                        }
                                        MouseArea { id: tkMa; anchors.fill: parent; hoverEnabled: true; enabled: tk.han; onClicked: page.hub.openWord(tk.modelData.w) }
                                    }
                                }
                            }
                        }
                        Text {
                            visible: page.viewMode === 1 && !(page.zhText && page.tokens.length > 0)
                            anchors.left: parent.left; anchors.top: parent.top
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: !page.zhText ? "Word by word works for Chinese text. Pick Chinese or Auto-detect and scan again."
                                  : (page.tokBusy ? "Splitting words\u2026" : "Nothing to split yet.")
                            font.family: "JetBrains Mono"; font.pixelSize: page.s(14); color: page.cSub0
                        }
                    }

                    Text {
                        visible: hub.phonetic !== "" && page.viewMode === 0
                        Layout.fillWidth: true
                        text: hub.phonetic
                        wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                        font.family: "JetBrains Mono"; font.pixelSize: page.s(13); font.italic: true
                        color: Qt.alpha(page.cMauve, 0.9)
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: page.s(8)
                        Text {
                            height: page.s(26); verticalAlignment: Text.AlignVCenter
                            text: "RE-SCAN AS"; font.family: "JetBrains Mono"; font.pixelSize: page.s(9); font.letterSpacing: 1.5; color: page.cSub0
                        }
                        Repeater {
                            model: page.chipModel
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool active: hub.langs === chip.modelData.langs
                                width: chipText.implicitWidth + page.s(22); height: page.s(26)
                                radius: page.s(7)
                                color: active ? Qt.alpha(page.cMauve, 0.2) : (chipMa.containsMouse ? Qt.alpha(page.cMauve, 0.1) : "transparent")
                                border.color: (active || chipMa.containsMouse) ? page.cMauve : page.cSurf1
                                border.width: 1
                                Text {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData.label
                                    font.family: "JetBrains Mono"; font.pixelSize: page.s(11)
                                    font.weight: chip.active ? Font.Bold : Font.Normal
                                    color: chip.active ? page.cMauve : page.cSub0
                                }
                                MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; onClicked: { if (chip.modelData.langs === "__more") page.moreLangs = !page.moreLangs; else hub.rescan(chip.modelData.langs); } }
                            }
                        }
                    }
                }
            }

            // ARROW (with completion ripple)
            Rectangle {
                id: arrowBtn
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: page.s(46); Layout.preferredHeight: page.s(46)
                radius: width / 2
                scale: page.busy ? 0.9 + 0.1 * page.pulse : 1.0
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: hub.mauve }
                    GradientStop { position: 1.0; color: hub.pink }
                }
                Rectangle {
                    id: ripple
                    z: -1
                    anchors.centerIn: parent
                    width: parent.width; height: parent.height; radius: width / 2
                    color: "transparent"
                    border.color: hub.mauve; border.width: 2
                    opacity: 0
                }
                Text {
                    anchors.centerIn: parent
                    text: "\uDB80\uDC54"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: page.s(20)
                    color: hub.crust
                }
            }

            // ENGLISH
            Rectangle {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.preferredWidth: 100
                radius: page.s(16)
                color: Qt.alpha(page.cMauve, 0.07)
                border.color: Qt.alpha(page.cMauve, 0.4); border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: page.s(20)
                    spacing: page.s(12)

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "ENGLISH"; font.family: "JetBrains Mono"; font.weight: Font.Bold; font.pixelSize: page.s(10); font.letterSpacing: 1.5; color: page.cMauve }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            Layout.preferredWidth: page.s(32); Layout.preferredHeight: page.s(32)
                            radius: page.s(9)
                            opacity: hub.status === "done" ? 1.0 : 0.35
                            color: cpMa.containsMouse ? Qt.alpha(page.cMauve, 0.18) : "transparent"
                            border.color: cpMa.containsMouse ? page.cMauve : page.cSurf1; border.width: 1
                            Text { anchors.centerIn: parent; text: "\uDB80\uDD8F"; font.family: "Iosevka Nerd Font"; font.pixelSize: page.s(15); color: page.cMauve }
                            MouseArea {
                                id: cpMa; anchors.fill: parent; hoverEnabled: true
                                onClicked: { if (hub.status === "done") hub.copyText(hub.translated, "Translation copied"); }
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true; Layout.fillHeight: true

                        Column {
                            visible: hub.status === "loading"
                            width: parent.width; spacing: page.s(12)
                            Repeater {
                                model: [0.92, 0.78, 0.5]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: parent.width * modelData; height: page.s(16); radius: page.s(8)
                                    color: page.cSurf1; opacity: page.pulse
                                }
                            }
                        }
                        Text {
                            visible: hub.status === "idle" || hub.status === "scanning"
                            anchors.left: parent.left; anchors.top: parent.top
                            text: hub.status === "scanning" ? "Waiting for the text\u2026" : "The translation appears here."
                            font.family: "JetBrains Mono"; font.pixelSize: page.s(18); color: page.cSub0
                            opacity: hub.status === "scanning" ? page.pulse * 0.8 : 0.6
                        }
                        ScrollHint { flick: dstFlick; hub: page.hub }
                        Flickable {
                            id: dstFlick
                            visible: hub.status === "done" || hub.status === "error"
                            anchors.fill: parent
                            contentHeight: dstText.paintedHeight + page.s(72)
                            clip: true; boundsBehavior: Flickable.StopAtBounds
                            TextEdit {
                                id: dstText
                                width: dstFlick.width - page.s(16)
                                text: hub.status === "error" ? hub.translated : page.shownText
                                readOnly: true; selectByMouse: true
                                wrapMode: TextEdit.Wrap
                                font.family: "JetBrains Mono"; font.weight: Font.Medium; font.pixelSize: page.s(24)
                                color: hub.status === "error" ? page.cRed : page.cText
                                selectionColor: page.cMauve
                            }
                        }
                    }
                }

                // hanko seal
                Item {
                    id: hanko
                    anchors.right: parent.right; anchors.bottom: parent.bottom
                    anchors.margins: page.s(18)
                    width: page.s(64); height: page.s(64)
                    opacity: 0; rotation: -8
                    Rectangle {
                        id: stampRing
                        anchors.centerIn: parent
                        width: parent.width; height: parent.height; radius: page.s(10)
                        color: "transparent"; border.color: hub.red; border.width: 2
                        opacity: 0
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: page.s(8)
                        color: Qt.alpha(hub.red, 0.10)
                        border.color: hub.red; border.width: 3
                        Rectangle { anchors.fill: parent; anchors.margins: page.s(5); radius: page.s(4); color: "transparent"; border.color: Qt.alpha(hub.red, 0.7); border.width: 1 }
                        Text { anchors.centerIn: parent; text: "\u8a33"; font.pixelSize: page.s(34); font.weight: Font.Bold; color: hub.red }
                    }
                }
            }
        }

        // ---- footer ----
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Enter translate  \u00b7  Shift+Enter new line  \u00b7  C copy  \u00b7  S scan  \u00b7  2 dictionary"
                font.family: "JetBrains Mono"; font.pixelSize: page.s(11); color: page.cSub0
            }
            Item { Layout.fillWidth: true }
            PillBtn { hub: page.hub; label: "Open in Dictionary"; onClicked: page.hub.page = 1 }
        }
    }
}
