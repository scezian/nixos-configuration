import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
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

    function s(val) {
        return scaler.s(val);
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
    readonly property color red: _theme.red
    readonly property color green: _theme.green

    readonly property string helper: Quickshell.env("HOME") + "/.config/hypr/scripts/default_apps.py"

    property var cats: []
    property int sel: 0
    property bool loaded: false
    property bool busy: false
    property bool statusError: false
    property string statusText: "Pick a category, then click an app to make it the default."
    readonly property var cat: (cats.length > sel) ? cats[sel] : null

    function refresh() {
        reader.running = true;
    }

    function loadData(txt) {
        try {
            var d = JSON.parse(txt);
            cats = d;
            loaded = true;
            if (sel >= cats.length) sel = 0;
        } catch (e) {
            statusError = true;
            statusText = "Couldn't read the app list: " + e;
        }
    }

    function setDefault(app) {
        if (busy || !cat) return;
        busy = true;
        statusError = false;
        statusText = "Setting " + app.name + "...";
        applier.pendingName = app.name;
        applier.pendingCat = cat.label;
        applier.command = ["python3", helper, "set", cat.id, app.id];
        applier.running = true;
    }

    function iconSource(name) {
        if (!name) return "";
        if (name.charAt(0) === "/") return "file://" + name;
        var p = "";
        try { p = Quickshell.iconPath(name, true); } catch (e) { p = ""; }
        return p || "";
    }

    Component.onCompleted: refresh()

    Process {
        id: reader
        command: ["python3", window.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: window.loadData(this.text)
        }
    }

    Process {
        id: applier
        property string pendingName: ""
        property string pendingCat: ""
        stderr: StdioCollector { id: applyErr }
        onExited: (code) => {
            window.busy = false;
            if (code === 0) {
                window.statusError = false;
                window.statusText = applier.pendingCat + " is now " + applier.pendingName;
                window.refresh();
            } else {
                window.statusError = true;
                var e = applyErr.text.trim();
                window.statusText = e !== "" ? e : ("Failed (exit " + code + ").");
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: window.s(24)
        color: window.base
        border.width: 1
        border.color: Qt.alpha(window.surface1, 0.8)
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: window.s(28)
        spacing: window.s(24)

        // ---------------- left: categories ----------------
        ColumnLayout {
            Layout.preferredWidth: window.s(260)
            Layout.fillHeight: true
            spacing: window.s(4)

            Text {
                text: "Default apps"
                color: window.text
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(22)
                font.bold: true
            }
            Text {
                text: "What opens what"
                color: window.subtext0
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(12)
                Layout.bottomMargin: window.s(6)
            }

            Repeater {
                model: window.cats

                delegate: Rectangle {
                    id: catRow
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(46)
                    radius: window.s(14)
                    color: catMa.containsMouse ? window.surface1 : (window.sel === catRow.index ? window.surface0 : "transparent")
                    border.width: window.sel === catRow.index ? window.s(2) : 0
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

            Item { Layout.fillHeight: true }
        }

        // ---------------- right: apps for the selected category ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: window.s(10)

            RowLayout {
                Layout.fillWidth: true
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
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: window.s(16)
                color: window.mantle
                border.width: 1
                border.color: Qt.alpha(window.surface1, 0.6)

                ListView {
                    id: appList
                    anchors.fill: parent
                    anchors.margins: window.s(8)
                    clip: true
                    spacing: window.s(4)
                    boundsBehavior: Flickable.StopAtBounds
                    model: window.cat ? window.cat.apps : []
                    ScrollBar.vertical: ScrollBar { }

                    delegate: Rectangle {
                        id: appRow
                        required property var modelData
                        readonly property bool isCurrent: window.cat !== null && appRow.modelData.id === window.cat.current

                        width: appList.width
                        height: window.s(56)
                        radius: window.s(12)
                        color: rowMa.containsMouse ? window.surface1 : (appRow.isCurrent ? Qt.alpha(window.mauve, 0.14) : "transparent")
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
                                    color: window.surface0
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
                                color: Qt.alpha(window.mauve, 0.2)
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

            Text {
                Layout.fillWidth: true
                text: window.statusText
                wrapMode: Text.WordWrap
                color: window.statusError ? window.red : window.subtext0
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(11)
            }
        }
    }
}
