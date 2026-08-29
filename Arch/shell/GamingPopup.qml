import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState
    implicitWidth: 360
    implicitHeight: 200

    property bool gaming: false

    Process {
        id: toggleProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.gaming = JSON.parse(text).enabled } catch (e) { }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            text: "Gaming mode"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: gaming
                ? "On — animations and blur are off for extra performance."
                : "Off — normal desktop effects. Turn on before a game."
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        FSwitch {
            text: gaming ? "Gaming mode on" : "Gaming mode off"
            checked: root.gaming
            font.family: ArchTheme.fontFamily
            onClicked: {
                toggleProc.command = ["bash", shellState.scriptsPath + "/gaming_mode.sh"]
                toggleProc.running = true
            }
        }
    }

    Component.onCompleted: {
        const flag = Quickshell.env("HOME") + "/.config/arch-shell/gaming.flag"
        // Presence is checked by toggling status via a cheap test: file existence is handled in script only on toggle.
        // Seed from a one-shot process:
        seedProc.running = true
    }

    Process {
        id: seedProc
        command: ["bash", "-c", "test -f \"$HOME/.config/arch-shell/gaming.flag\" && echo true || echo false"]
        stdout: StdioCollector {
            onStreamFinished: root.gaming = text.trim() === "true"
        }
    }
}
