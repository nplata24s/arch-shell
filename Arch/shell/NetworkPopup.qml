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
    implicitHeight: 440

    property string tab: "network"
    property string btBusy: ""
    property string error: ""
    property var net: ({
        radio: "disabled", connected: false, ssid: "", signal: 0,
        networks: [], eth_connected: false, bt_power: "no",
        bt_present: false, bt_connected: false, bt_device: "",
        bt_discovering: false, bt_devices: []
    })

    readonly property bool btOn: root.net.bt_power === "yes"
    readonly property var btDevices: root.net.bt_devices || []

    function script(name) {
        return shellState.scriptsPath + "/" + name
    }

    function refresh() { fetchProc.running = true }

    function btCmd(...parts) {
        const args = ["python3", script("bluetooth.py")]
        for (let i = 0; i < parts.length; i++)
            args.push(String(parts[i]))
        return args
    }

    Process {
        id: fetchProc
        command: ["bash", root.script("network_state.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.net = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Process {
        id: btActionProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.btBusy = ""
                try {
                    const d = JSON.parse(text)
                    if (d && d.error)
                        root.error = String(d.error)
                    else
                        root.error = ""
                } catch (e) { }
                refreshTimer.interval = 400
                refreshTimer.restart()
            }
        }
    }

    // BlueZ stops scanning when the client that started it disconnects.
    Process {
        id: btScanProc
        running: root.tab === "bluetooth" && root.btOn
        command: root.btCmd("scan-hold")
    }

    Timer {
        interval: root.tab === "bluetooth" ? 1500 : 3000
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    Timer {
        id: refreshTimer
        interval: 1500
        repeat: false
        onTriggered: root.refresh()
    }

    Component.onCompleted: fetchProc.running = true

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { id: "network", label: "Network" },
                    { id: "bluetooth", label: "Bluetooth" }
                ]
                delegate: FBtn {
                    required property var modelData
                    text: modelData.label
                    implicitHeight: 28
                    highlighted: root.tab === modelData.id
                    onClicked: {
                        root.tab = modelData.id
                        root.error = ""
                        root.refresh()
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        Text {
            visible: root.error !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.error
            color: ArchTheme.danger
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeCaption
        }

        // ── Network ─────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "network"
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "WiFi"
                    color: ArchTheme.textPrimary
                    font.family: ArchTheme.fontFamily
                }
                Item { Layout.fillWidth: true }
                FSwitch {
                    checked: root.net.radio === "enabled"
                    onClicked: {
                        Quickshell.execDetached(["bash", root.script("network_control.sh"), "toggle-wifi"])
                        refreshTimer.interval = 1200
                        refreshTimer.restart()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: ArchTheme.textSecondary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
                text: {
                    if (root.net.eth_connected) return "Ethernet connected"
                    if (root.net.connected)
                        return "Connected to " + root.net.ssid + " (" + root.net.signal + "%)"
                    if (root.net.radio === "disabled") return "WiFi is off"
                    return "Not connected"
                }
            }

            FBtn {
                text: "Disconnect"
                visible: root.net.connected
                onClicked: {
                    Quickshell.execDetached(["bash", root.script("network_control.sh"), "disconnect"])
                    refreshTimer.interval = 1200
                    refreshTimer.restart()
                }
            }

            Text {
                text: "Networks"
                font.weight: Font.DemiBold
                color: ArchTheme.textPrimary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                model: root.net.networks || []
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: 36
                    radius: ArchTheme.radius
                    color: netMa.containsMouse ? ArchTheme.layerHover
                         : (modelData.active ? ArchTheme.accentMuted : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        Text {
                            text: modelData.active ? "●" : Icons.wifi
                            color: modelData.active ? ArchTheme.accent : ArchTheme.textSecondary
                            font.family: ArchTheme.fontFamily
                        }
                        Text {
                            text: modelData.ssid
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: ArchTheme.textPrimary
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                        Text {
                            text: modelData.signal + "%"
                            color: ArchTheme.textSecondary
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: ArchTheme.sizeSmall
                        }
                    }

                    MouseArea {
                        id: netMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !modelData.active
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached(["bash", root.script("network_control.sh"),
                                "connect", modelData.ssid])
                            refreshTimer.interval = 1500
                            refreshTimer.restart()
                        }
                    }
                }
            }
        }

        // ── Bluetooth ───────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tab === "bluetooth"
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Bluetooth"
                    color: ArchTheme.textPrimary
                    font.family: ArchTheme.fontFamily
                }
                Item { Layout.fillWidth: true }
                FSwitch {
                    checked: root.btOn
                    enabled: root.btBusy === ""
                    onClicked: {
                        root.btBusy = "power"
                        btActionProc.command = root.btCmd("power", "toggle")
                        btActionProc.running = true
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: ArchTheme.textSecondary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
                text: {
                    if (!root.net.bt_present)
                        return "No Bluetooth adapter found"
                    if (!root.btOn)
                        return "Bluetooth is off"
                    if (root.net.bt_connected)
                        return "Connected to " + root.net.bt_device
                    if (root.net.bt_discovering || btScanProc.running)
                        return "Scanning — put a device in pairing mode"
                    return "Not connected"
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                model: root.btDevices
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: FScroll { }

                Text {
                    visible: root.btDevices.length === 0 && root.btOn
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "No devices yet. Leave this tab open while the device is in pairing mode."
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    color: ArchTheme.textTertiary
                }

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view ? ListView.view.width : 0
                    height: 40
                    radius: ArchTheme.radius
                    color: btMa.containsMouse ? ArchTheme.layerHover
                         : (modelData.connected ? ArchTheme.accentMuted : "transparent")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 8

                        Text {
                            text: modelData.connected ? "●" : Icons.bluetooth
                            color: modelData.connected ? ArchTheme.accent : ArchTheme.textSecondary
                            font.family: ArchTheme.fontFamily
                            font.pixelSize: 14
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.address
                                elide: Text.ElideRight
                                color: ArchTheme.textPrimary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeSmall
                            }
                            Text {
                                Layout.fillWidth: true
                                text: {
                                    if (root.btBusy === modelData.address)
                                        return "Connecting…"
                                    if (modelData.connected)
                                        return "Connected"
                                    if (modelData.paired)
                                        return "Paired"
                                    return "Available"
                                }
                                elide: Text.ElideRight
                                color: ArchTheme.textTertiary
                                font.family: ArchTheme.fontFamily
                                font.pixelSize: ArchTheme.sizeCaption
                            }
                        }
                        FIconBtn {
                            glyph: Icons.trash
                            diameter: 26
                            glyphSize: 12
                            visible: modelData.paired && !modelData.connected
                            enabled: root.btBusy === ""
                            onClicked: {
                                root.btBusy = modelData.address
                                btActionProc.command = root.btCmd("remove", modelData.address)
                                btActionProc.running = true
                            }
                        }
                    }

                    MouseArea {
                        id: btMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: root.btBusy === ""
                        z: -1
                        onClicked: {
                            root.btBusy = modelData.address
                            btActionProc.command = root.btCmd(
                                modelData.connected ? "disconnect" : "connect",
                                modelData.address)
                            btActionProc.running = true
                        }
                    }
                }
            }
        }
    }
}
