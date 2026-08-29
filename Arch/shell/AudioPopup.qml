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
    implicitHeight: 420

    property var audio: ({
        master_volume: 0, master_mute: false,
        input_volume: 0, input_mute: false,
        outputs: [], inputs: [], apps: []
    })
    property int section: 0

    function refresh() { fetchProc.running = true }

    function setVol(type, id, val) {
        Quickshell.execDetached(["bash", shellState.scriptsPath + "/audio_control.sh",
            "set-volume", type, id, String(Math.round(val))])
        refresh()
    }

    function toggleMute(type, id) {
        Quickshell.execDetached(["bash", shellState.scriptsPath + "/audio_control.sh",
            "toggle-mute", type, id])
        refresh()
    }

    Process {
        id: fetchProc
        command: ["python3", shellState.scriptsPath + "/audio_state.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.audio = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    Component.onCompleted: fetchProc.running = true

    component DeviceRow: RowLayout {
        required property var device
        required property string kind
        Layout.fillWidth: true
        Text {
            text: device.is_default ? "●" : "○"
            color: ArchTheme.accent
        }
        Text {
            text: device.name
            Layout.fillWidth: true
            elide: Text.ElideRight
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }
        Text {
            text: device.volume + "%"
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }
        FBtn {
            text: "Use"
            visible: !device.is_default
            font.family: ArchTheme.fontFamily
            onClicked: {
                Quickshell.execDetached(["bash", shellState.scriptsPath + "/audio_control.sh",
                    "set-default", kind, device.description || device.name])
                refresh()
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Audio"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: root.section
            onCurrentIndexChanged: root.section = currentIndex
            TabButton {
                text: "Output"
                font.family: ArchTheme.fontFamily
                background: Rectangle {
                    radius: ArchTheme.radius
                    color: parent.checked ? ArchTheme.accentMuted : (parent.hovered ? ArchTheme.layerHover : "transparent")
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? ArchTheme.accent : ArchTheme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            TabButton {
                text: "Input"
                font.family: ArchTheme.fontFamily
                background: Rectangle {
                    radius: ArchTheme.radius
                    color: parent.checked ? ArchTheme.accentMuted : (parent.hovered ? ArchTheme.layerHover : "transparent")
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? ArchTheme.accent : ArchTheme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
            TabButton {
                text: "Streams"
                font.family: ArchTheme.fontFamily
                background: Rectangle {
                    radius: ArchTheme.radius
                    color: parent.checked ? ArchTheme.accentMuted : (parent.hovered ? ArchTheme.layerHover : "transparent")
                }
                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: parent.checked ? ArchTheme.accent : ArchTheme.textPrimary
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.section

            // Output
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: outCol.implicitHeight
                ColumnLayout {
                    id: outCol
                    width: parent.width
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: audio.master_mute ? "󰝟" : "󰕾"; font.pixelSize: 16; font.family: ArchTheme.fontFamily }
                        FSlider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: audio.master_volume || 0
                            onMoved: setVol("sink", "@DEFAULT@", value)
                        }
                        Text {
                            text: Math.round(audio.master_volume || 0) + "%"
                            color: ArchTheme.textSecondary
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            Layout.preferredWidth: 36
                        }
                        FBtn {
                            text: audio.master_mute ? "Unmute" : "Mute"
                            font.family: ArchTheme.fontFamily
                            onClicked: toggleMute("sink", "@DEFAULT@")
                        }
                    }
                    Text {
                        text: "Devices"
                        font.weight: Font.DemiBold
                        color: ArchTheme.textPrimary
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                    }
                    Repeater {
                        model: audio.outputs || []
                        delegate: DeviceRow {
                            required property var modelData
                            device: modelData
                            kind: "sink"
                        }
                    }
                }
            }

            // Input
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: inCol.implicitHeight
                ColumnLayout {
                    id: inCol
                    width: parent.width
                    spacing: 8
                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: audio.input_mute ? "󰍭" : "󰍬"; font.pixelSize: 16; font.family: ArchTheme.fontFamily }
                        FSlider {
                            Layout.fillWidth: true
                            from: 0; to: 100
                            value: audio.input_volume || 0
                            onMoved: setVol("source", "@DEFAULT@", value)
                        }
                        Text {
                            text: Math.round(audio.input_volume || 0) + "%"
                            color: ArchTheme.textSecondary
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                            Layout.preferredWidth: 36
                        }
                        FBtn {
                            text: audio.input_mute ? "Unmute" : "Mute"
                            font.family: ArchTheme.fontFamily
                            onClicked: toggleMute("source", "@DEFAULT@")
                        }
                    }
                    Text {
                        text: "Devices"
                        font.weight: Font.DemiBold
                        color: ArchTheme.textPrimary
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                    }
                    Repeater {
                        model: audio.inputs || []
                        delegate: DeviceRow {
                            required property var modelData
                            device: modelData
                            kind: "source"
                        }
                    }
                }
            }

            // Streams
            Flickable {
                clip: true
                contentWidth: width
                contentHeight: appCol.implicitHeight
                ColumnLayout {
                    id: appCol
                    width: parent.width
                    spacing: 8
                    Text {
                        visible: (audio.apps || []).length === 0
                        text: "No apps are playing audio right now."
                        color: ArchTheme.textSecondary
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Repeater {
                        model: audio.apps || []
                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                text: modelData.name
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                color: ArchTheme.textPrimary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                            }
                            Text {
                                text: modelData.description || ""
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                color: ArchTheme.textSecondary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                FSlider {
                                    Layout.fillWidth: true
                                    from: 0; to: 100
                                    value: modelData.volume || 0
                                    onMoved: {
                                        Quickshell.execDetached(["bash", shellState.scriptsPath + "/audio_control.sh",
                                            "set-stream-volume", "sink-input", modelData.id, String(Math.round(value))])
                                    }
                                }
                                Text {
                                    text: modelData.volume + "%"
                                    color: ArchTheme.textSecondary
                                    font.family: ArchTheme.fontFamily
                                    font.pixelSize: ArchTheme.sizeSmall
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
