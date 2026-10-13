import QtQuick
import QtQuick.Window
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.folderlistmodel
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
    readonly property color text: _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color mauve: _theme.mauve
    readonly property color red: _theme.red
    readonly property color green: _theme.green
    readonly property color crust: _theme.crust

    readonly property string home: Quickshell.env("HOME")
    readonly property string helper: home + "/.config/hypr/scripts/avatar_apply.py"
    readonly property real previewSize: s(250)

    property string srcPath: ""
    property real zoom: 1.0
    property real ox: 0.0
    property real oy: 0.0
    property bool busy: false
    property bool statusError: false
    property string statusText: "Pick a wallpaper, or browse for any image."

    // ------------------------------------------------------------------
    // Crop state (math must match avatar_apply.py)
    // ------------------------------------------------------------------
    function clampPan() {
        if (previewImg.status !== Image.Ready) return;
        var w = previewImg.implicitWidth;
        var h = previewImg.implicitHeight;
        var m = Math.min(w, h);
        if (m <= 0) return;
        var lx = Math.max(0, (zoom * w / m - 1) / 2);
        var ly = Math.max(0, (zoom * h / m - 1) / 2);
        ox = Math.max(-lx, Math.min(lx, ox));
        oy = Math.max(-ly, Math.min(ly, oy));
    }

    function setSource(p) {
        srcPath = p;
        zoom = 1.0;
        ox = 0.0;
        oy = 0.0;
        statusError = false;
        statusText = "Drag to reposition, scroll or use the slider to zoom.";
    }

    function setZoom(z) {
        zoom = Math.max(1.0, Math.min(3.0, z));
        clampPan();
    }

    function apply() {
        if (srcPath === "" || busy) return;
        busy = true;
        statusError = false;
        statusText = "Waiting for authentication...";
        applier.mode = "save";
        applier.command = ["python3", helper, srcPath, zoom.toFixed(4), ox.toFixed(5), oy.toFixed(5)];
        applier.running = true;
    }

    function removeAvatar() {
        if (busy) return;
        busy = true;
        statusError = false;
        statusText = "Waiting for authentication...";
        applier.mode = "remove";
        applier.command = ["python3", helper, "--remove"];
        applier.running = true;
    }

    // ------------------------------------------------------------------
    // Processes
    // ------------------------------------------------------------------
    Process {
        id: picker
        command: ["zenity", "--file-selection",
                  "--title=Choose avatar image",
                  "--filename=" + window.home + "/Pictures/",
                  "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp *.PNG *.JPG *.JPEG"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = this.text.trim();
                if (p !== "") window.setSource(p);
            }
        }
    }

    Process {
        id: applier
        property string mode: "save"
        stderr: StdioCollector { id: applyErr }
        onExited: (code) => {
            window.busy = false;
            if (code === 0) {
                window.statusError = false;
                window.statusText = applier.mode === "remove"
                    ? "Avatar removed."
                    : "Saved! It will show at your next login screen.";
            } else {
                window.statusError = true;
                var e = applyErr.text.trim();
                window.statusText = e !== "" ? e : ("Failed (exit " + code + "). Is a polkit agent running?");
            }
        }
    }

    FolderListModel {
        id: wallModel
        folder: "file://" + window.home + "/Pictures/Wallpapers"
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        caseSensitive: false
        showDirs: false
        sortField: FolderListModel.Name
    }

    // ------------------------------------------------------------------
    // Reusable button (no outer ids inside, so it's scope-safe)
    // ------------------------------------------------------------------
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
        Layout.preferredHeight: px * 3.2
        radius: height / 2.6
        color: !active ? Qt.alpha(fill, 0.35) : (ma.containsMouse ? fillHover : fill)
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
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.active) btn.clicked()
        }
    }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
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
        spacing: window.s(28)

        // ---------------- left: preview + controls ----------------
        ColumnLayout {
            Layout.preferredWidth: window.s(290)
            Layout.fillHeight: true
            spacing: window.s(12)

            Text {
                text: "Login avatar"
                color: window.text
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(22)
                font.bold: true
            }
            Text {
                text: "Shown on the SDDM login screen"
                color: window.subtext0
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(12)
                Layout.bottomMargin: window.s(6)
            }

            Item {
                id: previewWrap
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: window.previewSize
                Layout.preferredHeight: window.previewSize

                // Square crop surface (hidden; rendered through the circular mask below)
                Item {
                    id: cropBox
                    anchors.fill: parent
                    visible: false
                    clip: true
                    layer.enabled: true

                    Rectangle {
                        anchors.fill: parent
                        color: window.surface0
                    }

                    Image {
                        id: previewImg
                        source: window.srcPath !== "" ? "file://" + window.srcPath : ""
                        asynchronous: true
                        autoTransform: true
                        smooth: true
                        mipmap: true
                        fillMode: Image.Stretch
                        readonly property real sc: implicitWidth > 0
                            ? window.zoom * window.previewSize / Math.min(implicitWidth, implicitHeight)
                            : 1
                        width: implicitWidth * sc
                        height: implicitHeight * sc
                        x: window.previewSize / 2 + window.ox * window.previewSize - width / 2
                        y: window.previewSize / 2 + window.oy * window.previewSize - height / 2
                        onStatusChanged: if (status === Image.Ready) window.clampPan()
                    }
                }

                Item {
                    id: circleMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "black"
                    }
                }

                MultiEffect {
                    anchors.fill: parent
                    source: cropBox
                    maskEnabled: true
                    maskSource: circleMask
                    visible: window.srcPath !== ""
                }

                // Empty-state disc
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: window.surface0
                    visible: window.srcPath === ""
                    Text {
                        anchors.centerIn: parent
                        text: "No image"
                        color: window.subtext0
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(13)
                    }
                }

                // Ring
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: window.s(3)
                    border.color: window.mauve
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: window.srcPath !== ""
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real lx: 0
                    property real ly: 0
                    onPressed: (m) => { lx = m.x; ly = m.y; }
                    onPositionChanged: (m) => {
                        if (!pressed) return;
                        window.ox += (m.x - lx) / window.previewSize;
                        window.oy += (m.y - ly) / window.previewSize;
                        lx = m.x;
                        ly = m.y;
                        window.clampPan();
                    }
                    onWheel: (w) => window.setZoom(window.zoom + w.angleDelta.y / 1200)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: window.s(6)
                spacing: window.s(10)
                Text {
                    text: "Zoom"
                    color: window.subtext0
                    font.family: "JetBrains Mono"
                    font.pixelSize: window.s(12)
                }
                Slider {
                    id: zoomSlider
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.s(28)
                    implicitHeight: window.s(28)
                    from: 1
                    to: 3
                    stepSize: 0.01
                    value: window.zoom
                    enabled: window.srcPath !== ""
                    onMoved: window.setZoom(value)

                    background: Rectangle {
                        x: zoomSlider.leftPadding
                        y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                        width: zoomSlider.availableWidth
                        height: window.s(6)
                        radius: height / 2
                        color: window.surface0
                        Rectangle {
                            width: zoomSlider.visualPosition * parent.width
                            height: parent.height
                            radius: parent.radius
                            color: window.mauve
                        }
                    }
                    handle: Rectangle {
                        x: zoomSlider.leftPadding + zoomSlider.visualPosition * (zoomSlider.availableWidth - width)
                        y: zoomSlider.topPadding + zoomSlider.availableHeight / 2 - height / 2
                        width: window.s(18)
                        height: window.s(18)
                        radius: width / 2
                        color: window.mauve
                        border.width: window.s(2)
                        border.color: window.base
                    }
                }
            }

            Item { Layout.fillHeight: true }

            ActionButton {
                label: "Browse files..."
                px: window.s(13)
                fill: window.surface0
                fillHover: window.surface1
                fg: window.text
                onClicked: picker.running = true
            }
            ActionButton {
                label: window.busy ? "Working..." : "Set as login avatar"
                px: window.s(13)
                fill: window.mauve
                fillHover: Qt.lighter(window.mauve, 1.12)
                fg: window.crust
                active: window.srcPath !== "" && !window.busy
                onClicked: window.apply()
            }
            ActionButton {
                label: "Remove avatar"
                px: window.s(13)
                fill: window.surface0
                fillHover: Qt.alpha(window.red, 0.85)
                fg: window.text
                active: !window.busy
                onClicked: window.removeAvatar()
            }
        }

        // ---------------- right: constellation ----------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: window.s(10)

            Text {
                text: "Constellation  -  click or scroll to rotate"
                color: window.subtext0
                font.family: "JetBrains Mono"
                font.pixelSize: window.s(12)
                font.bold: true
            }

            Rectangle {
                id: sky
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: window.s(16)
                color: window.mantle
                border.width: 1
                border.color: Qt.alpha(window.mauve, 0.35)

                function pick(i) {
                    if (wallModel.count === 0) return;
                    var n = (i + wallModel.count) % wallModel.count;
                    ring.currentIndex = n;
                    window.setSource(wallModel.get(n, "filePath"));
                }

                // ambient backdrop from the picked image
                Image {
                    id: skySrc
                    anchors.fill: parent
                    source: window.srcPath !== "" ? "file://" + window.srcPath : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 160
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: skyMask
                    anchors.fill: parent
                    radius: sky.radius
                    color: "black"
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    anchors.fill: parent
                    source: skySrc
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 64
                    saturation: 0.3
                    maskEnabled: true
                    maskSource: skyMask
                    opacity: window.srcPath !== "" ? 0.8 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 400 } }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: sky.radius
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(window.crust, 0.35) }
                        GradientStop { position: 1.0; color: Qt.alpha(window.crust, 0.6) }
                    }
                }

                // orbit guide
                Rectangle {
                    anchors.centerIn: parent
                    width: ring.rx * 2
                    height: ring.ry * 2
                    radius: height / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(window.mauve, 0.25)
                }

                // centre label
                Column {
                    anchors.centerIn: parent
                    spacing: window.s(4)
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: wallModel.count > 0 ? String(wallModel.get(ring.currentIndex, "fileName")) : ""
                        width: ring.rx * 1.2
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        color: window.text
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(13)
                        font.bold: true
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: wallModel.count > 0 ? ((ring.currentIndex + 1) + " / " + wallModel.count) : ""
                        color: window.subtext0
                        font.family: "JetBrains Mono"
                        font.pixelSize: window.s(11)
                    }
                }

                PathView {
                    id: ring
                    anchors.fill: parent
                    readonly property real rx: width * 0.36
                    readonly property real ry: height * 0.26
                    model: wallModel
                    pathItemCount: Math.min(9, Math.max(1, wallModel.count))
                    preferredHighlightBegin: 0.0
                    preferredHighlightEnd: 0.0
                    highlightRangeMode: PathView.StrictlyEnforceRange
                    highlightMoveDuration: 450
                    snapMode: PathView.SnapToItem
                    interactive: false

                    path: Path {
                        startX: ring.width / 2
                        startY: ring.height / 2 + ring.ry
                        PathAttribute { name: "itemScale"; value: 1.15 }
                        PathAttribute { name: "itemZ"; value: 10 }
                        PathAttribute { name: "itemOp"; value: 1.0 }
                        PathArc {
                            x: ring.width / 2; y: ring.height / 2 - ring.ry
                            radiusX: ring.rx; radiusY: ring.ry
                            direction: PathArc.Clockwise
                        }
                        PathAttribute { name: "itemScale"; value: 0.5 }
                        PathAttribute { name: "itemZ"; value: 0 }
                        PathAttribute { name: "itemOp"; value: 0.45 }
                        PathArc {
                            x: ring.width / 2; y: ring.height / 2 + ring.ry
                            radiusX: ring.rx; radiusY: ring.ry
                            direction: PathArc.Clockwise
                        }
                        PathAttribute { name: "itemScale"; value: 1.15 }
                        PathAttribute { name: "itemZ"; value: 10 }
                        PathAttribute { name: "itemOp"; value: 1.0 }
                    }

                    delegate: Item {
                        id: pl
                        width: window.s(124)
                        height: width
                        scale: PathView.itemScale
                        z: PathView.itemZ
                        opacity: PathView.itemOp
                        readonly property string path: model.filePath
                        readonly property bool picked: window.srcPath === pl.path

                        Item {
                            id: plSrc
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Image {
                                anchors.fill: parent
                                source: "file://" + pl.path
                                sourceSize.width: 260
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                        }
                        Item {
                            id: plMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle { anchors.fill: parent; radius: width / 2; color: "black" }
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: plSrc
                            maskEnabled: true
                            maskSource: plMask
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: pl.picked ? window.s(3) : (plMa.containsMouse ? window.s(2) : 1)
                            border.color: pl.picked ? window.mauve : (plMa.containsMouse ? window.text : Qt.alpha(window.subtext0, 0.5))
                        }
                        MouseArea {
                            id: plMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: sky.pick(index)
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    onWheel: (w) => sky.pick(ring.currentIndex + (w.angleDelta.y < 0 ? 1 : -1))
                }

                Text {
                    anchors.centerIn: parent
                    visible: wallModel.status === FolderListModel.Ready && wallModel.count === 0
                    text: "No images in ~/Pictures/Wallpapers"
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
