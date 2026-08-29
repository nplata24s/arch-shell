import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState

    implicitWidth: 590
    implicitHeight: 520

    property string tab: "appearance"
    property string capturingId: ""
    property var keybinds: ({ binds: {} })

    readonly property var accentSwatches: [
        "#60cdff", "#4cc2ff", "#0078d4", "#8b8bf5", "#c586f0",
        "#f472b6", "#ff6b6b", "#ffa94d", "#6ccb5f", "#2dd4bf"
    ]

    readonly property var bindOrder: [
        "shell.start", "shell.keybindHelp",
        "module.agentCentre", "module.audio", "module.clipboard",
        "module.network", "module.music", "module.wallpaper", "module.clock",
        "module.battery", "module.gaming", "module.settings",
        "module.notes", "module.calculator", "module.taskView",
        "module.quickSettings",
        "app.terminal", "app.browser", "app.files", "app.lock",
        "app.screenshot", "app.colorPicker",
        "window.close", "window.toggleFloat"
    ]

    readonly property var taskbarSettings: {
        const _ = shellState ? shellState.settingsRev : 0
        return shellState.settings.taskbar || ({})
    }

    // Modules currently not placed anywhere on the bar.
    readonly property var availableModules: {
        const _ = shellState ? shellState.settingsRev : 0
        return shellState.allModules.filter(m => shellState.moduleZone(m.id) === "")
    }

    FileView {
        id: kbFile
        path: shellState.configDir + "/keybinds.json"
        onLoaded: {
            try { root.keybinds = JSON.parse(text()) } catch (e) { }
        }
    }

    // ── Keybind helpers ──────────────────────────────────────────────
    function bindLabel(id) {
        const b = (keybinds.binds || {})[id]
        if (!b) return "—"
        const mods = (b.mods || []).join(" + ")
        if (b.alone) return (mods || "Super") + " (tap)"
        if (!b.key) return mods || "—"
        return mods ? mods + " + " + b.key : b.key
    }

    function bindDesc(id) {
        const b = (keybinds.binds || {})[id]
        return b ? b.description : id
    }

    function keyName(event) {
        const map = {
            32: "Space", 16777220: "Return", 16777216: "Escape",
            16777264: "F1", 16777265: "F2", 16777266: "F3", 16777267: "F4",
            16777221: "Enter", 16777222: "Insert", 16777219: "Backspace",
            16777223: "Delete", 16777232: "Home", 16777233: "End",
            16777234: "Left", 16777235: "Up", 16777236: "Right", 16777237: "Down",
            16777238: "PageUp", 16777239: "PageDown"
        }
        if (map[event.key]) return map[event.key]
        if (event.key === Qt.Key_Tab) return "Tab"
        const t = event.text
        if (t && t.length === 1)
            return t.toUpperCase()
        return ""
    }

    function captureKey(event) {
        if (!capturingId) return
        if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control
            || event.key === Qt.Key_Alt)
            return

        const next = JSON.parse(JSON.stringify(keybinds))
        if (!next.binds) next.binds = {}
        if (!next.binds[capturingId]) next.binds[capturingId] = { description: capturingId }
        const slot = next.binds[capturingId]

        // Super / mainMod by itself — used for the Start menu.
        if (event.key === Qt.Key_Meta) {
            slot.key = ""
            slot.mods = ["Super"]
            slot.alone = true
            keybinds = next
            capturingId = ""
            event.accepted = true
            return
        }

        const name = keyName(event)
        if (!name) return
        const mods = []
        if (event.modifiers & Qt.MetaModifier) mods.push("Super")
        if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl")
        if (event.modifiers & Qt.AltModifier) mods.push("Alt")
        if (event.modifiers & Qt.ShiftModifier) mods.push("Shift")
        slot.key = name
        slot.mods = mods
        slot.alone = false
        keybinds = next
        capturingId = ""
        event.accepted = true
    }

    onCapturingIdChanged: {
        if (capturingId)
            captureLayer.forceActiveFocus()
    }

    // ── Reusable row ─────────────────────────────────────────────────
    component SettingRow: RowLayout {
        id: srow
        property string label: ""
        property string hint: ""
        Layout.fillWidth: true
        spacing: 10

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                text: srow.label
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
                color: ArchTheme.textPrimary
                elide: Text.ElideRight
            }
            Text {
                visible: srow.hint !== ""
                text: srow.hint
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: ArchTheme.textTertiary
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }

    component Divider: Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: ArchTheme.border
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Header + tabs
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: Icons.settings
                font.family: ArchTheme.fontFamily
                font.pixelSize: 18
                color: ArchTheme.accent
            }
            Text {
                text: "Settings"
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeTitle
                font.weight: Font.DemiBold
                color: ArchTheme.textPrimary
            }
            Item { Layout.fillWidth: true }

            Repeater {
                model: [
                    { id: "appearance", label: "Appearance" },
                    { id: "taskbar", label: "Taskbar" },
                    { id: "keybinds", label: "Keybinds" }
                ]
                delegate: FBtn {
                    required property var modelData
                    text: modelData.label
                    implicitHeight: 28
                    highlighted: root.tab === modelData.id
                    onClicked: root.tab = modelData.id
                }
            }
        }

        // ── Appearance ──────────────────────────────────────────────
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "appearance"
            contentWidth: width
            contentHeight: appearanceCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }

            ColumnLayout {
                id: appearanceCol
                width: parent.width
                spacing: 10

                Text {
                    text: "Accent colour"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        model: root.accentSwatches
                        delegate: Rectangle {
                            required property string modelData
                            width: 34
                            height: 34
                            radius: ArchTheme.radiusCard
                            color: modelData
                            border.width: selected ? 2 : 0
                            border.color: ArchTheme.textPrimary

                            readonly property bool selected:
                                Qt.color(modelData) === Qt.color(
                                    (shellState.settings.theme
                                     && shellState.settings.theme.accent) || "#60cdff")

                            Text {
                                anchors.centerIn: parent
                                visible: parent.selected
                                text: Icons.check
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: 14
                                color: "#ff10222e"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shellState.setAccent(modelData)
                            }
                        }
                    }
                }

                Divider { }

                SettingRow {
                    label: "Glass transparency"
                    hint: "Lower is more transparent. Blur comes from Hyprland."
                    Text {
                        text: Math.round((root.taskbarSettings.opacity || 0.72) * 100) + "%"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                        color: ArchTheme.accent
                        Layout.preferredWidth: 42
                        horizontalAlignment: Text.AlignRight
                    }
                    FSlider {
                        Layout.preferredWidth: 170
                        from: 0.35
                        to: 1.0
                        value: root.taskbarSettings.opacity || 0.72
                        onMoved: shellState.setTaskbarOpacity(Math.round(value * 100) / 100)
                    }
                }

                SettingRow {
                    label: "Glass tint"
                    hint: "Base colour mixed under the blur."
                    Repeater {
                        model: ["#1c1c1c", "#202020", "#101014", "#1a1f28", "#241c24"]
                        delegate: Rectangle {
                            required property string modelData
                            width: 26
                            height: 26
                            radius: ArchTheme.radius
                            color: modelData
                            border.width: (root.taskbarSettings.color || "#1c1c1c") === modelData ? 2 : 1
                            border.color: (root.taskbarSettings.color || "#1c1c1c") === modelData
                                ? ArchTheme.accent : ArchTheme.border
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: shellState.setTaskbarColor(modelData)
                            }
                        }
                    }
                }

                Divider { }

                SettingRow {
                    label: "Taskbar position"
                    FCombo {
                        model: ["top", "bottom"]
                        currentIndex: root.taskbarSettings.position === "bottom" ? 1 : 0
                        onActivated: shellState.setTaskbarPosition(currentText)
                    }
                }

                SettingRow {
                    label: "Taskbar height"
                    Text {
                        text: (root.taskbarSettings.height || 48) + " px"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                        color: ArchTheme.accent
                        Layout.preferredWidth: 48
                        horizontalAlignment: Text.AlignRight
                    }
                    FSlider {
                        Layout.preferredWidth: 170
                        from: 36
                        to: 72
                        stepSize: 2
                        value: root.taskbarSettings.height || 48
                        onMoved: shellState.setTaskbarHeight(Math.round(value))
                    }
                }

                SettingRow {
                    label: "Desktops shown on bar"
                    FSpin {
                        from: 3
                        to: 9
                        value: (shellState.settings.workspaces
                                && shellState.settings.workspaces.showOnBar) || 5
                        onValueModified: shellState.setWorkspacesOnBar(value)
                    }
                }

                SettingRow {
                    label: "Temperature unit"
                    FCombo {
                        model: ["celsius", "fahrenheit"]
                        currentIndex: (shellState.settings.weather
                                       && shellState.settings.weather.unit === "fahrenheit") ? 1 : 0
                        onActivated: shellState.setWeatherUnit(currentText)
                    }
                }

                Divider { }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Appearance changes save and apply straight away."
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                    FBtn {
                        text: "Reset all"
                        danger: true
                        onClicked: shellState.resetSettings()
                    }
                }
            }
        }

        // ── Taskbar layout ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "taskbar"
            spacing: 10

            // Placed modules, grouped by zone
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: zonesCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }

                ColumnLayout {
                    id: zonesCol
                    width: parent.width - 12
                    spacing: 10

                    Repeater {
                        model: [
                            { zone: "left", label: "Left" },
                            { zone: "center", label: "Centre" },
                            { zone: "right", label: "Right" }
                        ]

                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: modelData.label
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textTertiary
                            }

                            Repeater {
                                model: shellState.zoneModules(modelData.zone)

                                delegate: FCard {
                                    required property string modelData
                                    required property int index
                                    readonly property var meta: shellState.moduleMeta(modelData)
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 38

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 6
                                        spacing: 8

                                        Text {
                                            text: meta.icon
                                            font.family: ArchTheme.fontFamily
                                            font.pixelSize: 14
                                            color: ArchTheme.accent
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: meta.label
                                            font.family: ArchTheme.fontFamily
                                            font.pixelSize: ArchTheme.sizeSmall
                                            color: ArchTheme.textPrimary
                                            elide: Text.ElideRight
                                        }
                                        FIconBtn {
                                            glyph: Icons.chevronUp
                                            diameter: 26
                                            glyphSize: 11
                                            enabled: index > 0
                                            onClicked: shellState.moveModule(modelData, -1)
                                        }
                                        FIconBtn {
                                            glyph: Icons.chevronDown
                                            diameter: 26
                                            glyphSize: 11
                                            onClicked: shellState.moveModule(modelData, 1)
                                        }
                                        FIconBtn {
                                            glyph: Icons.trash
                                            diameter: 26
                                            glyphSize: 12
                                            enabled: modelData !== "Start"
                                            onClicked: shellState.removeModuleFromBar(modelData)
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: shellState.zoneModules(modelData.zone).length === 0
                                text: "Empty"
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                                color: ArchTheme.textDisabled
                            }
                        }
                    }
                }
            }

            // Modules not on the bar
            FCard {
                Layout.preferredWidth: 210
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Text {
                        text: "Not on the bar"
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.availableModules
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: FScroll { }

                        delegate: Rectangle {
                            id: availRow
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            height: 34
                            radius: ArchTheme.radius
                            color: addMa.containsMouse ? ArchTheme.layerHover : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 4
                                spacing: 6

                                Text {
                                    text: availRow.modelData.icon
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: 13
                                    color: ArchTheme.textSecondary
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: availRow.modelData.label
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                    color: ArchTheme.textPrimary
                                    elide: Text.ElideRight
                                }
                                Repeater {
                                    model: [
                                        { z: "left", g: "L" },
                                        { z: "center", g: "C" },
                                        { z: "right", g: "R" }
                                    ]
                                    delegate: FIconBtn {
                                        required property var modelData
                                        glyph: modelData.g
                                        diameter: 24
                                        glyphSize: 10
                                        opacity: addMa.containsMouse ? 1 : 0
                                        enabled: addMa.containsMouse
                                        onClicked: shellState.addModuleToZone(
                                            availRow.modelData.id, modelData.z)
                                    }
                                }
                            }

                            MouseArea {
                                id: addMa
                                anchors.fill: parent
                                hoverEnabled: true
                                z: -1
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Hover a module and pick left, centre or right."
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeCaption
                        color: ArchTheme.textTertiary
                    }
                }
            }
        }

        // ── Keybinds ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "keybinds"
            spacing: 6

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.capturingId
                    ? "Press the new shortcut now (Esc to cancel)…"
                    : "Click a row, then press the new keys. Save when done."
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeCaption
                color: root.capturingId ? ArchTheme.accent : ArchTheme.textTertiary
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                model: root.bindOrder
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }

                delegate: Rectangle {
                    required property string modelData
                    width: ListView.view ? ListView.view.width - 12 : 0
                    height: 36
                    radius: ArchTheme.radius
                    color: root.capturingId === modelData ? ArchTheme.accentMuted
                         : (rowMa.containsMouse ? ArchTheme.layerHover : ArchTheme.layer)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        Text {
                            Layout.fillWidth: true
                            text: root.bindDesc(modelData)
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            color: ArchTheme.textPrimary
                            elide: Text.ElideRight
                        }
                        Text {
                            text: root.capturingId === modelData ? "…" : root.bindLabel(modelData)
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            color: ArchTheme.accent
                        }
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.capturingId = modelData
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "Shortcuts take effect after saving — Hyprland reloads them."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeCaption
                    color: ArchTheme.textTertiary
                }
                FBtn {
                    text: "Save keybinds"
                    highlighted: true
                    onClicked: shellState.persistKeybinds(root.keybinds)
                }
            }
        }
    }

    // Key capture overlay
    Rectangle {
        id: captureLayer
        anchors.fill: parent
        visible: root.capturingId !== ""
        color: ArchTheme.scrim
        focus: visible
        z: 20

        Text {
            anchors.centerIn: parent
            text: "Press the new shortcut\nEsc to cancel"
            horizontalAlignment: Text.AlignHCenter
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeTitle
            color: ArchTheme.textPrimary
        }

        Keys.onPressed: event => root.captureKey(event)
        Keys.onEscapePressed: event => {
            root.capturingId = ""
            event.accepted = true
        }
    }
}
