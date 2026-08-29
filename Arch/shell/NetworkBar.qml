import QtQuick
import Quickshell.Io
import "theme"

BarChip {
    id: root
    required property var shellState

    property var net: ({
        connected: false, ssid: "", radio: "disabled", eth_connected: false,
        bt_power: "no", bt_connected: false, bt_device: "", bt_present: false
    })

    active: shellState ? shellState.isOpen("NetworkBluetooth") : false
    onActivated: if (shellState) shellState.open("NetworkBluetooth")

    readonly property string glyph: {
        if (net.eth_connected && !net.connected) return Icons.ethernet
        if (net.connected) return Icons.wifi
        return Icons.wifiOff
    }

    readonly property string caption: {
        if (net.eth_connected && !net.connected) return "Wired"
        if (net.connected)
            return net.ssid.length > 12 ? net.ssid.slice(0, 11) + "…" : net.ssid
        if (net.radio === "disabled") return "Off"
        return "Offline"
    }

    readonly property bool btOn: net.bt_power === "yes"
    readonly property string btCaption: {
        const name = net.bt_device || ""
        if (!net.bt_connected || !name)
            return ""
        return name.length > 12 ? name.slice(0, 11) + "…" : name
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.glyph
        font.family: ArchTheme.fontFamily
        font.pixelSize: 15
        color: root.net.connected || root.net.eth_connected
            ? (root.active ? ArchTheme.accent : ArchTheme.textPrimary)
            : ArchTheme.textTertiary
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.caption
        font.family: ArchTheme.fontFamily
        font.pixelSize: ArchTheme.sizeSmall
        color: ArchTheme.textSecondary
    }

    Rectangle {
        visible: root.net.bt_present !== false
        width: 1
        height: 12
        anchors.verticalCenter: parent.verticalCenter
        color: ArchTheme.border
    }

    Text {
        visible: root.net.bt_present !== false
        anchors.verticalCenter: parent.verticalCenter
        text: root.btOn ? Icons.bluetooth : Icons.bluetoothOff
        font.family: ArchTheme.fontFamily
        font.pixelSize: 15
        color: root.net.bt_connected
            ? (root.active ? ArchTheme.accent : ArchTheme.textPrimary)
            : (root.btOn ? ArchTheme.textSecondary : ArchTheme.textTertiary)
    }

    Text {
        visible: root.btCaption !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.btCaption
        font.family: ArchTheme.fontFamily
        font.pixelSize: ArchTheme.sizeSmall
        color: ArchTheme.textSecondary
    }

    Process {
        id: fetchProc
        command: ["bash", shellState.scriptsPath + "/network_state.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.net = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    Component.onCompleted: fetchProc.running = true
}
