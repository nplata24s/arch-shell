import QtQuick
import "theme"

// Glass card used to group content inside flyouts.
Rectangle {
    radius: ArchTheme.radiusCard
    color: ArchTheme.layer
    border.width: 1
    border.color: ArchTheme.border

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: parent.radius
        anchors.rightMargin: parent.radius
        anchors.topMargin: 1
        height: 1
        color: ArchTheme.glassHighlight
        opacity: 0.5
    }
}
