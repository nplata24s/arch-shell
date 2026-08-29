import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState

    implicitWidth: 380
    implicitHeight: 480

    property var net: ({ radio: "disabled", bt_power: "no" })
    property int brightness: 100
    property bool brightnessPresent: false
    property bool night: false
    readonly property bool dnd: shellState ? shellState.dnd : false
    property bool recording: false
    property string power: "balanced"
    property int updates: 0

    function refreshAll() {
        netProc.running = true
        brightProc.running = true
        nightProc.running = true
        recProc.running = true
        powerProc.running = true
        updProc.running = true
    }

    Process {
        id: netProc
        command: ["bash", shellState.scriptsPath + "/network_state.sh"]
        stdout: StdioCollector { onStreamFinished: { try { root.net = JSON.parse(text) } catch (e) { } } }
    }
    Process {
        id: brightProc
        command: ["bash", shellState.scriptsPath + "/brightness.sh", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.brightnessPresent = d.present
                    root.brightness = d.percent
                } catch (e) { }
            }
        }
    }
    Process {
        id: nightProc
        command: ["bash", shellState.scriptsPath + "/night_light.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { root.night = JSON.parse(text).running } catch (e) { } } }
    }
    Process {
        id: recProc
        command: ["bash", shellState.scriptsPath + "/recorder.sh", "status"]
        stdout: StdioCollector { onStreamFinished: { try { root.recording = JSON.parse(text).running } catch (e) { } } }
    }
    Process {
        id: powerProc
        command: ["bash", shellState.scriptsPath + "/power_profile.sh", "get"]
        stdout: StdioCollector { onStreamFinished: { try { root.power = JSON.parse(text).active } catch (e) { } } }
    }
    Process {
        id: updProc
        command: ["bash", shellState.scriptsPath + "/updates.sh", "count"]
        stdout: StdioCollector { onStreamFinished: { try { root.updates = JSON.parse(text).count } catch (e) { } } }
    }

    Component.onCompleted: refreshAll()

    Flickable {
        id: scroller
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: FScroll { }

        ColumnLayout {
            id: col
            width: scroller.width
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: Icons.quickSettings
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: 18
                    color: ArchTheme.accent
                }
                Text {
                    text: "Quick settings"
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeTitle
                    font.weight: Font.DemiBold
                    color: ArchTheme.textPrimary
                }
                Item { Layout.fillWidth: true }
                FIconBtn {
                    glyph: Icons.settings
                    diameter: 28
                    glyphSize: 13
                    onClicked: shellState.open("Settings")
                }
            }

            GridLayout {
                columns: 2
                columnSpacing: 8
                rowSpacing: 8
                Layout.fillWidth: true

                Repeater {
                    model: [
                        { label: "Wi‑Fi", glyph: Icons.wifi, on: root.net.radio === "enabled", action: "wifi" },
                        { label: "Bluetooth", glyph: Icons.bluetooth, on: root.net.bt_power === "yes", action: "bt" },
                        { label: "Night light", glyph: Icons.nightLight, on: root.night, action: "night" },
                        { label: "Do not disturb", glyph: Icons.bellOff, on: root.dnd, action: "dnd" },
                        { label: "Record screen", glyph: Icons.record, on: root.recording, action: "rec" },
                        { label: "Gaming", glyph: Icons.gaming, on: false, action: "game" }
                    ]

                    delegate: Rectangle {
                        id: tile
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        radius: ArchTheme.radiusCard
                        color: modelData.on ? ArchTheme.accent
                             : (tileMa.containsMouse ? ArchTheme.layerHover : ArchTheme.layer)
                        border.color: modelData.on ? "transparent" : ArchTheme.border
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Text {
                                text: tile.modelData.glyph
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: 17
                                color: tile.modelData.on ? ArchTheme.textOnAccent : ArchTheme.textPrimary
                            }
                            Text {
                                Layout.fillWidth: true
                                text: tile.modelData.label
                                color: tile.modelData.on ? ArchTheme.textOnAccent : ArchTheme.textPrimary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                switch (modelData.action) {
                                case "wifi":
                                    Quickshell.execDetached(["bash", shellState.scriptsPath + "/network_control.sh", "toggle-wifi"])
                                    Qt.callLater(refreshAll)
                                    break
                                case "bt":
                                    Quickshell.execDetached(["bash", shellState.scriptsPath + "/network_control.sh", "toggle-bt"])
                                    Qt.callLater(refreshAll)
                                    break
                                case "night":
                                    Quickshell.execDetached(["bash", shellState.scriptsPath + "/night_light.sh", "toggle"])
                                    nightProc.running = true
                                    break
                                case "dnd":
                                    if (shellState)
                                        shellState.toggleDnd()
                                    break
                                case "rec":
                                    Quickshell.execDetached(["bash", shellState.scriptsPath + "/recorder.sh", "toggle"])
                                    recProc.running = true
                                    break
                                case "game":
                                    shellState.open("GamingMode")
                                    break
                                }
                            }
                        }
                    }
                }
            }

            Text {
                visible: brightnessPresent
                text: Icons.brightness + "  Brightness  " + brightness + "%"
                color: ArchTheme.textSecondary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
            }

            FSlider {
                visible: brightnessPresent
                Layout.fillWidth: true
                from: 1
                to: 100
                value: brightness
                onPressedChanged: {
                    if (!pressed)
                        Quickshell.execDetached(["bash", shellState.scriptsPath + "/brightness.sh", "set", String(Math.round(value))])
                }
            }

            Text {
                text: Icons.battery + "  Power profile"
                color: ArchTheme.textSecondary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
            }

            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: ["power-saver", "balanced", "performance"]
                    delegate: FBtn {
                        required property string modelData
                        text: modelData === "power-saver" ? "Saver" : (modelData === "performance" ? "Perf" : "Balanced")
                        Layout.fillWidth: true
                        highlighted: root.power === modelData
                        onClicked: {
                            Quickshell.execDetached(["bash", shellState.scriptsPath + "/power_profile.sh", "set", modelData])
                            powerProc.running = true
                        }
                    }
                }
            }

            GridLayout {
                columns: 2
                columnSpacing: 6
                rowSpacing: 6
                Layout.fillWidth: true
                FBtn { text: "Audio"; Layout.fillWidth: true; onClicked: shellState.open("Audio") }
                FBtn { text: "Network"; Layout.fillWidth: true; onClicked: shellState.open("NetworkBluetooth") }
                FBtn { text: "Clipboard"; Layout.fillWidth: true; onClicked: shellState.open("Clipboard") }
                FBtn { text: "Notes"; Layout.fillWidth: true; onClicked: shellState.open("Notes") }
                FBtn { text: "Calculator"; Layout.fillWidth: true; onClicked: shellState.open("Calculator") }
                FBtn {
                    text: "Colour picker"
                    Layout.fillWidth: true
                    font.family: ArchTheme.fontFamily
                    onClicked: {
                        shellState.close()
                        Quickshell.execDetached(["hyprpicker", "-a"])
                    }
                }
                FBtn { text: "Wallpaper"; Layout.fillWidth: true; onClicked: shellState.open("Wallpaper") }
                FBtn { text: updates > 0 ? ("Updates (" + updates + ")") : "Updates"; Layout.fillWidth: true; onClicked: shellState.open("SystemUpdates") }
            }
        }
    }
}
