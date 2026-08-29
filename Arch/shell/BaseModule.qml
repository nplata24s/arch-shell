import QtQuick
import "theme"

// Generic taskbar button. Start draws the Windows-style four-pane logo;
// every other module renders its Nerd Font glyph.
Item {
    id: root

    required property string moduleId
    required property string label
    required property string icon

    property var shellState
    property bool hasPopup: false

    readonly property bool isStart: moduleId === "Start"
    readonly property bool open: shellState ? shellState.isOpen(moduleId) : false
    readonly property string glyph: {
        if (icon)
            return icon
        return shellState ? shellState.moduleMeta(moduleId).icon : ""
    }

    implicitWidth: 34
    implicitHeight: 34

    Rectangle {
        id: surface
        anchors.centerIn: parent
        width: 34
        height: 34
        radius: ArchTheme.radiusCard
        color: root.open ? ArchTheme.accentMuted
             : (ma.containsMouse ? ArchTheme.layerHover : "transparent")

        Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

        // Windows-style Start logo
        Grid {
            visible: root.isStart
            anchors.centerIn: parent
            rows: 2
            columns: 2
            rowSpacing: 2.5
            columnSpacing: 2.5
            Repeater {
                model: 4
                Rectangle {
                    width: 6
                    height: 6
                    radius: 1.5
                    color: root.open || ma.containsMouse
                        ? ArchTheme.accent : ArchTheme.textPrimary
                    Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }
                }
            }
        }

        Text {
            visible: !root.isStart
            anchors.centerIn: parent
            text: root.glyph
            font.family: ArchTheme.fontFamily
            font.pixelSize: 15
            color: root.open ? ArchTheme.accent : ArchTheme.textPrimary
            Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }
        }

        // Fluent selection line
        Rectangle {
            visible: root.open
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            width: 14
            height: 2
            radius: 1
            color: ArchTheme.accent
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (!shellState)
                return
            if (root.isStart || root.hasPopup)
                shellState.open(moduleId)
        }
    }
}
