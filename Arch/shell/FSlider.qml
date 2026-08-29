import QtQuick
import QtQuick.Controls
import "theme"

Slider {
    id: root

    implicitHeight: 24
    live: true

    background: Rectangle {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 180
        width: root.availableWidth
        height: 4
        radius: 2
        color: ArchTheme.hoverStrong

        Rectangle {
            width: root.visualPosition * parent.width
            height: parent.height
            radius: 2
            color: root.enabled ? ArchTheme.accent : ArchTheme.textDisabled
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: 16
        implicitHeight: 16
        radius: 8
        color: ArchTheme.textPrimary
        border.width: root.pressed ? 5 : (root.hovered ? 4 : 5)
        border.color: root.enabled ? ArchTheme.accent : ArchTheme.textDisabled
        scale: root.pressed ? 0.88 : 1.0

        Behavior on scale { NumberAnimation { duration: ArchTheme.animFast } }
        Behavior on border.width { NumberAnimation { duration: ArchTheme.animFast } }
    }
}
