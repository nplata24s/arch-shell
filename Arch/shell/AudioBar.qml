import QtQuick
import Quickshell.Io
import "theme"

BarChip {
    id: root
    required property var shellState

    property var audio: ({ volume: 0, mute: false })

    active: shellState ? shellState.isOpen("Audio") : false
    onActivated: if (shellState) shellState.open("Audio")

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.audio.mute ? Icons.volumeOff : Icons.volume
        font.family: ArchTheme.fontFamily
        font.pixelSize: 15
        color: root.audio.mute ? ArchTheme.textTertiary
             : (root.active ? ArchTheme.accent : ArchTheme.textPrimary)
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: (root.audio.volume || 0) + "%"
        font.family: ArchTheme.fontFamily
        font.pixelSize: ArchTheme.sizeSmall
        color: root.audio.mute ? ArchTheme.textTertiary : ArchTheme.textSecondary
    }

    Process {
        id: fetchProc
        command: ["python3", shellState.scriptsPath + "/audio_state.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.audio = { volume: d.master_volume || 0, mute: d.master_mute || false }
                } catch (e) { }
            }
        }
    }

    Timer {
        interval: 2500
        running: true
        repeat: true
        onTriggered: fetchProc.running = true
    }

    Component.onCompleted: fetchProc.running = true
}
