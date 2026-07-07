import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: window

    // -------------------------------------------------------------------------
    // Responsive Scaling
    // -------------------------------------------------------------------------
    Scaler {
        id: scaler
        currentWidth: Screen.width
    }
    function s(val) { return scaler.s(val); }

    // -------------------------------------------------------------------------
    // COLORS (Dynamic Matugen Palette)
    // -------------------------------------------------------------------------
    MatugenColors { id: _theme }
    readonly property color base: _theme.base
    readonly property color mantle: _theme.mantle
    readonly property color crust: _theme.crust
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color red: _theme.red
    readonly property color green: _theme.green
    readonly property color yellow: _theme.yellow
    readonly property color blue: _theme.blue

    // -------------------------------------------------------------------------
    // STATE
    // -------------------------------------------------------------------------
    property var notes: []          // [{id, title, body, updated}]
    property int selectedIndex: -1
    property bool dataReady: false

    readonly property string notesDir: (Quickshell.env("HOME") || "/tmp") + "/.cache/quickshell/notepad"
    readonly property string notesFile: notesDir + "/notes.json"

    function nowStamp() {
        return new Date().toLocaleString(Qt.locale(), "MMM d, HH:mm");
    }

    function newNoteId() {
        return Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    // -------------------------------------------------------------------------
    // PERSISTENCE
    // -------------------------------------------------------------------------
    Process {
        id: loadProc
        running: false
        command: ["bash", "-c", "mkdir -p '" + window.notesDir + "' && cat '" + window.notesFile + "' 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let raw = this.text.trim();
                let parsed = [];
                try {
                    parsed = raw === "" ? [] : JSON.parse(raw);
                    if (!Array.isArray(parsed)) parsed = [];
                } catch (e) {
                    parsed = [];
                }
                window.notes = parsed;
                window.dataReady = true;
                if (window.notes.length > 0 && window.selectedIndex === -1) {
                    window.selectedIndex = 0;
                }
            }
        }
    }

    Timer {
        id: saveDebounce
        interval: 400
        onTriggered: window.persistNotes()
    }

    function requestSave() {
        saveDebounce.restart();
    }

    function persistNotes() {
        let json = JSON.stringify(window.notes);
        let b64 = Qt.btoa(json);
        Quickshell.execDetached(["bash", "-c",
            "mkdir -p '" + window.notesDir + "' && echo '" + b64 + "' | base64 -d > '" + window.notesFile + "'"
        ]);
    }

    Component.onCompleted: loadProc.running = true

    // -------------------------------------------------------------------------
    // NOTE OPERATIONS
    // -------------------------------------------------------------------------
    function addNote() {
        let temp = window.notes.slice();
        temp.unshift({ id: newNoteId(), title: "Untitled", body: "", updated: nowStamp() });
        window.notes = temp;
        window.selectedIndex = 0;
        requestSave();
    }

    function deleteNote(idx) {
        if (idx < 0 || idx >= window.notes.length) return;
        let temp = window.notes.slice();
        temp.splice(idx, 1);
        window.notes = temp;
        if (window.selectedIndex >= window.notes.length) {
            window.selectedIndex = window.notes.length - 1;
        }
        requestSave();
    }

    function updateNote(idx, field, value) {
        if (idx < 0 || idx >= window.notes.length) return;
        let temp = window.notes.slice();
        temp[idx] = Object.assign({}, temp[idx]);
        temp[idx][field] = value;
        temp[idx].updated = nowStamp();
        window.notes = temp;
        requestSave();
    }

    // -------------------------------------------------------------------------
    // UI LAYOUT
    // -------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        radius: window.s(20)
        color: window.base
        border.color: window.surface0
        border.width: 1
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 1

            // ==========================================
            // LEFT: NOTE LIST
            // ==========================================
            Rectangle {
                Layout.preferredWidth: window.s(240)
                Layout.fillHeight: true
                color: window.mantle

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(14)
                    spacing: window.s(10)

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Notes"
                            font.family: "JetBrains Mono"
                            font.weight: Font.Black
                            font.pixelSize: window.s(16)
                            color: window.text
                            Layout.fillWidth: true
                        }
                        Rectangle {
                            width: window.s(28); height: window.s(28); radius: window.s(9)
                            color: addMa.containsMouse ? window.surface1 : "transparent"
                            border.color: window.surface2
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: "+"
                                font.family: "JetBrains Mono"
                                font.weight: Font.Black
                                font.pixelSize: window.s(16)
                                color: window.green
                            }
                            MouseArea {
                                id: addMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: window.addNote()
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: window.dataReady && window.notes.length === 0
                        text: "No notes yet.\nTap + to add one."
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(12)
                        color: window.overlay0
                    }

                    ListView {
                        id: noteList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: window.s(6)
                        model: window.notes

                        delegate: Rectangle {
                            width: noteList.width
                            height: window.s(58)
                            radius: window.s(10)
                            color: index === window.selectedIndex
                                ? window.surface1
                                : (rowMa.containsMouse ? window.surface0 : "transparent")
                            border.color: index === window.selectedIndex ? window.mauve : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: window.s(10)
                                spacing: window.s(2)

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.title !== "" ? modelData.title : "Untitled"
                                        font.family: "JetBrains Mono"
                                        font.weight: Font.Bold
                                        font.pixelSize: window.s(13)
                                        color: window.text
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "󰅖"
                                        font.family: "Iosevka Nerd Font"
                                        font.pixelSize: window.s(12)
                                        color: delMa.containsMouse ? window.red : window.overlay0
                                        MouseArea {
                                            id: delMa
                                            anchors.fill: parent
                                            anchors.margins: window.s(-6)
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.deleteNote(index)
                                        }
                                    }
                                }
                                Text {
                                    text: modelData.updated || ""
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: window.s(10)
                                    color: window.subtext0
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                z: -1
                                onClicked: window.selectedIndex = index
                            }
                        }
                    }
                }
            }

            // ==========================================
            // RIGHT: EDITOR
            // ==========================================
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: window.s(20)
                    spacing: window.s(12)
                    visible: window.selectedIndex >= 0 && window.selectedIndex < window.notes.length

                    TextField {
                        id: titleField
                        Layout.fillWidth: true
                        font.family: "JetBrains Mono"
                        font.weight: Font.Black
                        font.pixelSize: window.s(18)
                        color: window.text
                        background: Item {}
                        text: window.selectedIndex >= 0 && window.selectedIndex < window.notes.length
                            ? window.notes[window.selectedIndex].title : ""
                        onTextEdited: window.updateNote(window.selectedIndex, "title", text)
                        placeholderText: "Title"
                        placeholderTextColor: window.overlay0
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: window.surface1 }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        TextArea {
                            id: bodyField
                            wrapMode: TextArea.Wrap
                            font.family: "JetBrains Mono"
                            font.pixelSize: window.s(13)
                            color: window.subtext0
                            background: Item {}
                            text: window.selectedIndex >= 0 && window.selectedIndex < window.notes.length
                                ? window.notes[window.selectedIndex].body : ""
                            onTextChanged: {
                                if (window.selectedIndex >= 0 && text !== window.notes[window.selectedIndex].body) {
                                    window.updateNote(window.selectedIndex, "body", text);
                                }
                            }
                            placeholderText: "Start typing..."
                            placeholderTextColor: window.overlay0
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !(window.selectedIndex >= 0 && window.selectedIndex < window.notes.length)
                    text: window.dataReady ? "Select or create a note" : "Loading..."
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(14)
                    color: window.overlay0
                }
            }
        }
    }
}
