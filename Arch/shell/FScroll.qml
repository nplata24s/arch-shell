import QtQuick
import QtQuick.Controls
import "theme"

ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded
    implicitWidth: 10
    padding: 2

    contentItem: Rectangle {
        implicitWidth: root.hovered || root.pressed ? 6 : 3
        implicitHeight: 40
        radius: width / 2
        color: root.pressed ? ArchTheme.textSecondary : ArchTheme.textTertiary
        opacity: root.active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ArchTheme.animNormal } }
        Behavior on implicitWidth { NumberAnimation { duration: ArchTheme.animFast } }
    }

    background: Rectangle {
        radius: width / 2
        color: ArchTheme.layer
        opacity: root.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: ArchTheme.animNormal } }
    }
}
