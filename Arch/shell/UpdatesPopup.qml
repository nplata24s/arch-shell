import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState
    implicitWidth: 400
    implicitHeight: 360

    property var info: ({ count: 0, packages: [] })

    Process {
        id: listProc
        command: ["bash", shellState.scriptsPath + "/updates.sh", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.info = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Component.onCompleted: listProc.running = true

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "System updates"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Text {
            text: info.count === 0 ? "System is up to date" : info.count + " updates available"
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 3
            model: info.packages || []
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }

            delegate: Text {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                text: modelData
                elide: Text.ElideRight
                color: ArchTheme.textPrimary
                font.family: ArchTheme.fontFamily
                font.pixelSize: ArchTheme.sizeSmall
            }
        }

        FBtn {
            text: "Update in terminal"
            Layout.fillWidth: true
            font.family: ArchTheme.fontFamily
            enabled: info.count > 0
            onClicked: {
                Quickshell.execDetached(["kitty", "-e", "bash", "-lc", "sudo pacman -Syu; echo; read -n1 -p 'Press any key to close'"])
                shellState.close()
            }
        }
    }
}
