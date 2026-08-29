import QtQuick
import Quickshell.Hyprland
import "theme"

Row {
    id: root

    required property var shellState
    spacing: 7
    height: 32

    property int maxShown: {
        const _ = shellState ? shellState.settingsRev : 0
        return shellState && shellState.settings.workspaces && shellState.settings.workspaces.showOnBar
            ? shellState.settings.workspaces.showOnBar : 5
    }

    function workspaceForId(id) {
        for (let i = 0; i < Hyprland.workspaces.count; i++) {
            const w = Hyprland.workspaces.get(i)
            if (w && w.id === id)
                return w
        }
        return null
    }

    Repeater {
        model: root.maxShown

        delegate: Item {
            required property int index
            readonly property int wsId: index + 1
            readonly property var wsObj: root.workspaceForId(wsId)
            readonly property bool isActive: wsObj ? wsObj.focused
                : (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === wsId)
            readonly property bool hasWindows: wsObj && wsObj.lastIpcObject
                ? (wsObj.lastIpcObject.windows || 0) > 0 : false

            width: 22
            height: 32

            Rectangle {
                anchors.centerIn: parent
                width: parent.isActive ? 18 : (parent.hasWindows ? 9 : 7)
                height: parent.isActive ? 7 : (parent.hasWindows ? 9 : 7)
                radius: height / 2
                color: parent.isActive ? ArchTheme.workspaceActive
                     : parent.hasWindows ? ArchTheme.workspaceOccupied
                     : ArchTheme.workspaceEmpty
                opacity: hoverArea.containsMouse && !parent.isActive ? 1 : 0.9

                Behavior on width { NumberAnimation { duration: ArchTheme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: ArchTheme.animNormal; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: ArchTheme.animNormal } }
            }

            MouseArea {
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("workspace " + parent.wsId)
            }
        }
    }
}
