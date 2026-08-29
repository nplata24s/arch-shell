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
    implicitHeight: 400

    property var walls: []

    Process {
        id: listProc
        command: ["bash", shellState.scriptsPath + "/wallpaper.sh", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.walls = JSON.parse(text) } catch (e) { root.walls = [] }
            }
        }
    }

    Component.onCompleted: listProc.running = true

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Wallpaper"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: walls.length === 0
            text: "No images found in Pictures or Pictures/Wallpapers."
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: root.walls
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }

            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: 40
                radius: ArchTheme.radiusCard
                color: ma.containsMouse ? ArchTheme.layerHover : ArchTheme.layer

                Text {
                    anchors.fill: parent
                    anchors.margins: 8
                    text: modelData.name
                    elide: Text.ElideRight
                    color: ArchTheme.textPrimary
                    font.family: ArchTheme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Quickshell.execDetached(["bash", shellState.scriptsPath + "/wallpaper.sh", "set", modelData.path])
                        shellState.close()
                    }
                }
            }
        }
    }
}
