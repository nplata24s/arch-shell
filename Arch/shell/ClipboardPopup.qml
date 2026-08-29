import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "theme"

Item {
    id: root
    required property var shellState
    implicitWidth: 420
    implicitHeight: 420

    property var clips: []

    function refresh() { fetchProc.running = true }

    Process {
        id: fetchProc
        command: ["bash", shellState.scriptsPath + "/clipboard_list.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.clips = JSON.parse(text) } catch (e) { root.clips = [] }
            }
        }
    }

    Component.onCompleted: fetchProc.running = true

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Clipboard"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: clips.length === 0
                ? "No history yet. Copy something and it will show up here (needs cliphist)."
                : "Click an item to copy it again."
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: root.clips
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }

            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: 44
                radius: ArchTheme.radiusCard
                color: ma.containsMouse ? ArchTheme.layerHover : ArchTheme.layer

                Text {
                    anchors.fill: parent
                    anchors.margins: 8
                    text: modelData.text
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                    color: ArchTheme.textPrimary
                    font.family: ArchTheme.fontFamily
                    font.pixelSize: ArchTheme.sizeSmall
                    verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Quickshell.execDetached(["bash", shellState.scriptsPath + "/clipboard_copy.sh", modelData.id])
                        shellState.close()
                    }
                }
            }
        }
    }
}
