import QtQuick
import Quickshell
import "."

Rectangle {
    id: rd
    focus: true
    property var hub: null
    color: bgMode === "black" ? "#000000" : (bgMode === "base" ? hub.base : hub.crust)

    property var pages: []
    property int startIndex: 0
    property string mode: "scroll"
    property bool rtl: false
    property string title: ""
    property bool loading: false
    property bool hasPrev: false
    property bool hasNext: false
    property bool saver: false
    property int index: 0
    property bool endSent: false
    property bool settled: false
    property real scrollStep: 160
    property real stripWidth: 1.0
    property bool autoNext: true
    property string bgMode: "theme"

    signal closeRequested()
    signal pageChanged(int idx)
    signal finished()
    signal prevChapter()
    signal nextChapter()
    signal modeToggled()
    signal saverToggled()

    onPagesChanged: { index = startIndex; endSent = false; settled = false; posT.restart(); settleT.restart() }
    onModeChanged: posT.restart()
    Timer { id: posT; interval: 300; onTriggered: rd.goTo(rd.index) }
    Timer { id: pos2T; interval: 1400; onTriggered: if (rd.mode === "scroll") lv.positionViewAtIndex(rd.index, ListView.Beginning) }
    Timer { id: settleT; interval: 1800; onTriggered: rd.settled = true }

    function goTo(i) {
        if (pages.length === 0) return
        i = Math.max(0, Math.min(pages.length - 1, i))
        index = i
        if (mode === "scroll") { lv.positionViewAtIndex(i, ListView.Beginning); pos2T.restart() }
    }
    function step(d) {
        var i = index + d
        if (i < 0) { if (hasPrev) prevChapter(); return }
        if (i >= pages.length) {
            if (!endSent) { endSent = true; finished() }
            if (hasNext && autoNext) nextChapter()
            return
        }
        index = i
        pageChanged(i)
        if (i === pages.length - 1 && !endSent) { endSent = true; finished() }
    }
    function scrollBy(dy) {
        var maxY = Math.max(0, lv.contentHeight - lv.height)
        scrollAnim.stop()
        scrollAnim.to = Math.max(0, Math.min(maxY, lv.contentY + dy))
        scrollAnim.start()
    }
    NumberAnimation { id: scrollAnim; target: lv; property: "contentY"; duration: 170; easing.type: Easing.OutCubic }

    Keys.onPressed: function (e) {
        var k = e.key
        if (k === Qt.Key_Escape) closeRequested()
        else if (k === Qt.Key_N) nextChapter()
        else if (k === Qt.Key_P) prevChapter()
        else if (k === Qt.Key_M) modeToggled()
        else if (mode === "scroll") {
            if (k === Qt.Key_Down || k === Qt.Key_J) scrollBy(rd.scrollStep)
            else if (k === Qt.Key_Up || k === Qt.Key_K) scrollBy(-rd.scrollStep)
            else if (k === Qt.Key_Space || k === Qt.Key_PageDown) scrollBy(lv.height * 0.9)
            else if (k === Qt.Key_PageUp) scrollBy(-lv.height * 0.9)
        } else {
            if (k === Qt.Key_Right) step(rtl ? -1 : 1)
            else if (k === Qt.Key_Left) step(rtl ? 1 : -1)
            else if (k === Qt.Key_Space || k === Qt.Key_PageDown || k === Qt.Key_Down) step(1)
            else if (k === Qt.Key_PageUp || k === Qt.Key_Up) step(-1)
        }
    }

    Rectangle {
        id: topBar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: rd.hub.s(46)
        color: Qt.alpha(rd.hub.base, 0.97)
        MBtn {
            hub: rd.hub; label: "< BACK"; accent: rd.hub.blue
            anchors { left: parent.left; leftMargin: rd.hub.s(10); verticalCenter: parent.verticalCenter }
            onClicked: rd.closeRequested()
        }
        Text {
            anchors.centerIn: parent
            width: parent.width - rd.hub.s(210)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: rd.title; color: rd.hub.text
            font.family: rd.hub.mono; font.pixelSize: rd.hub.fs(11); font.bold: true
        }
        Text {
            anchors { right: parent.right; rightMargin: rd.hub.s(14); verticalCenter: parent.verticalCenter }
            text: (rd.pages.length ? rd.index + 1 : 0) + " / " + rd.pages.length
            color: rd.hub.pink
            font.family: rd.hub.mono; font.pixelSize: rd.hub.fs(11); font.bold: true
        }
    }

    Rectangle {
        id: botBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: rd.hub.s(46)
        color: Qt.alpha(rd.hub.base, 0.97)
        Row {
            anchors.centerIn: parent
            spacing: rd.hub.s(10)
            MBtn { hub: rd.hub; label: "< PREV"; accent: rd.hub.mauve; enabled: rd.hasPrev; onClicked: rd.prevChapter() }
            MBtn { hub: rd.hub; label: rd.mode === "scroll" ? "MODE: SCROLL" : "MODE: PAGED"; accent: rd.hub.pink; onClicked: rd.modeToggled() }
            MBtn { hub: rd.hub; label: rd.saver ? "SAVER: ON" : "SAVER: OFF"; accent: rd.hub.yellow; solid: rd.saver; onClicked: rd.saverToggled() }
            MBtn { hub: rd.hub; label: "NEXT >"; accent: rd.hub.mauve; enabled: rd.hasNext; onClicked: rd.nextChapter() }
        }
    }

    property var enh: ({})
    function enhW() {
        var w = rd.mode === "scroll" ? lv.width * rd.stripWidth : paged.width
        return Math.max(400, Math.round(w / 50) * 50)
    }

    Item {
        id: area
        anchors { left: parent.left; right: parent.right; top: topBar.bottom; bottom: botBar.top }
        clip: true

        ListView {
            id: lv
            anchors.fill: parent
            visible: rd.mode === "scroll"
            model: rd.pages
            cacheBuffer: height * 4
            boundsBehavior: Flickable.StopAtBounds
            maximumFlickVelocity: 6000
            delegate: Image {
                id: pimg
                required property string modelData
                required property int index
                width: lv.width * rd.stripWidth
                x: (lv.width - width) / 2
                source: modelData
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(lv.width * 1.6)
                height: status === Image.Ready ? width * implicitHeight / Math.max(1, implicitWidth) : width * 1.4
                Text {
                    anchors.centerIn: parent
                    visible: pimg.status !== Image.Ready
                    text: pimg.status === Image.Error ? "FAILED - TAP TO RETRY" : "LOADING " + (pimg.index + 1)
                    color: pimg.status === Image.Error ? rd.hub.red : rd.hub.overlay0
                    font.family: rd.hub.mono; font.pixelSize: rd.hub.fs(11); font.letterSpacing: rd.hub.s(2)
                }
                Image {
                    anchors.fill: parent
                    source: rd.enh[String(pimg.index)] || ""
                    asynchronous: true
                    cache: false
                    smooth: true
                    fillMode: Image.Stretch
                    sourceSize.width: Math.round(pimg.width)
                    visible: status === Image.Ready
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: pimg.status === Image.Error
                    onClicked: { var u = pimg.source; pimg.source = ""; pimg.source = u }
                }
            }
        }
        MScroll { hub: rd.hub; target: lv; shown: rd.mode === "scroll"; anchors { right: parent.right; top: parent.top; bottom: parent.bottom } }
        Timer {
            interval: 300; repeat: true
            running: rd.visible && rd.mode === "scroll" && rd.pages.length > 0
            onTriggered: {
                var i = lv.indexAt(lv.width / 2, lv.contentY + lv.height * 0.3)
                if (i >= 0 && i !== rd.index) { rd.index = i; rd.pageChanged(i) }
                if (rd.settled && !rd.endSent && lv.contentHeight > lv.height && lv.contentY + lv.height >= lv.contentHeight - 40) {
                    rd.endSent = true
                    rd.finished()
                }
            }
        }

        Item {
            id: paged
            anchors.fill: parent
            visible: rd.mode === "paged"
            Image {
                id: pg
                anchors.fill: parent
                source: rd.pages.length > 0 ? rd.pages[Math.min(rd.index, rd.pages.length - 1)] : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                sourceSize.width: Math.round(paged.width * 2)
            }
            Image {
                anchors.fill: parent
                source: rd.enh[String(rd.index)] || ""
                asynchronous: true
                cache: false
                smooth: true
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.round(paged.width * 2)
                visible: status === Image.Ready
            }
            Image { width: 1; height: 1; visible: false; asynchronous: true; cache: true
                    sourceSize.width: Math.round(paged.width * 2)
                    source: rd.pages.length > rd.index + 1 ? rd.pages[rd.index + 1] : "" }
            Image { width: 1; height: 1; visible: false; asynchronous: true; cache: true
                    sourceSize.width: Math.round(paged.width * 2)
                    source: rd.index > 0 && rd.pages.length > 0 ? rd.pages[rd.index - 1] : "" }
            Text {
                anchors.centerIn: parent
                visible: pg.status !== Image.Ready && rd.pages.length > 0
                text: pg.status === Image.Error ? "FAILED TO LOAD" : "LOADING"
                color: rd.hub.overlay0
                font.family: rd.hub.mono; font.pixelSize: rd.hub.fs(11); font.letterSpacing: rd.hub.s(2)
            }
            MouseArea {
                anchors.fill: parent
                onClicked: function (m) {
                    var left = m.x < width / 2
                    rd.step(rd.rtl ? (left ? 1 : -1) : (left ? -1 : 1))
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: rd.loading
            text: "FETCHING PAGES..."
            color: rd.hub.pink
            font.family: rd.hub.mono; font.pixelSize: rd.hub.fs(13); font.bold: true; font.letterSpacing: rd.hub.s(3)
            SequentialAnimation on opacity {
                running: rd.loading; loops: Animation.Infinite
                NumberAnimation { to: 0.3; duration: 600 }
                NumberAnimation { to: 1.0; duration: 600 }
            }
        }
    }
}
