import QtQuick
import Quickshell.Io
import "theme"

BarChip {
    id: root
    required property var shellState

    property string layoutCode: "US"

    onActivated: switchProc.running = true

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.layoutCode
        font.family: ArchTheme.fontFamily
        font.pixelSize: ArchTheme.sizeSmall
        color: ArchTheme.textSecondary
    }

    Process {
        id: layoutProc
        running: true
        command: ["bash", "-c", "hyprctl devices -j | python3 -c \"import json,sys; d=json.load(sys.stdin); ks=d.get('keyboards',[]); print(ks[0].get('active_keymap','US') if ks else 'US')\""]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim()) root.layoutCode = text.trim().slice(0, 3).toUpperCase()
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: layoutProc.running = true
    }

    Process {
        id: switchProc
        command: ["hyprctl", "switchxkblayout", "all", "next"]
        running: false
        onExited: layoutProc.running = true
    }
}
