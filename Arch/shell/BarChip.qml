import QtQuick
import "theme"

// Shared taskbar surface: hover glass, accent tint when its flyout is open,
// and a Fluent selection line. Children are laid out in a row.
Rectangle {
    id: root

    property bool active: false
    property int spacing: 7
    property int hPadding: 10
    signal activated()

    default property alias content: holder.data

    implicitHeight: 34
    implicitWidth: holder.implicitWidth + hPadding * 2
    radius: ArchTheme.radiusCard
    color: root.active ? ArchTheme.accentMuted
         : (ma.containsMouse ? ArchTheme.layerHover : "transparent")

    Behavior on color { ColorAnimation { duration: ArchTheme.animFast } }

    Row {
        id: holder
        anchors.centerIn: parent
        spacing: root.spacing
    }

    Rectangle {
        visible: root.active
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 2
        width: Math.min(16, root.width - 8)
        height: 2
        radius: 1
        color: ArchTheme.accent
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
