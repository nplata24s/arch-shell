import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Hyprland
import "theme"

Item {
    id: root
    required property var shellState
    implicitWidth: 420
    implicitHeight: 400

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Text {
            text: "Task view"
            font.pixelSize: ArchTheme.sizeTitle
            font.weight: Font.DemiBold
            color: ArchTheme.textPrimary
            font.family: ArchTheme.fontFamily
        }

        Text {
            text: "Click a window to switch to it."
            color: ArchTheme.textSecondary
            font.family: ArchTheme.fontFamily
            font.pixelSize: ArchTheme.sizeSmall
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: Hyprland.toplevels
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: FScroll { }

            delegate: Rectangle {
                required property var modelData
                width: ListView.view ? ListView.view.width : 0
                height: 42
                radius: ArchTheme.radiusCard
                color: modelData.activated ? ArchTheme.accentMuted : (ma.containsMouse ? ArchTheme.layerHover : ArchTheme.layer)

                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    Text {
                        width: parent.width
                        text: modelData.title || "Untitled"
                        elide: Text.ElideRight
                        color: ArchTheme.textPrimary
                        font.family: ArchTheme.fontFamily
                    }
                    Text {
                        width: parent.width
                        text: modelData.workspace ? ("Desktop " + modelData.workspace.id) : ""
                        color: ArchTheme.textSecondary
                        font.family: ArchTheme.fontFamily
                        font.pixelSize: ArchTheme.sizeSmall
                    }
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (modelData.workspace)
                            Hyprland.dispatch("workspace " + modelData.workspace.id)
                        if (modelData.address)
                            Hyprland.dispatch("focuswindow address:" + modelData.address)
                        shellState.close()
                    }
                }
            }
        }
    }
}
